#!/bin/bash
set -e

# This script deploys OpenShift cluster and MAS application

## Variables
# Storage class, you can use 'odf' or 'nfs'
export STORAGE_TYPE="nfs"
# Storage class variables
export MONGODB_STORAGE_CLASS="gce-pd-ssd"
export KAFKA_STORAGE_CLASS="gce-pd-ssd"
export SLS_STORAGE_CLASS="gce-pd-ssd"
export UDS_STORAGE_CLASS="gce-pd-ssd"
export CPD_METADATA_STORAGE_CLASS="gce-pd-ssd"
[ $STORAGE_TYPE == "nfs" ] && export CPD_PRIMARY_STORAGE_CLASS="nfs-client" || export CPD_PRIMARY_STORAGE_CLASS="ocs-storagecluster-cephfs"
[ $STORAGE_TYPE == "nfs" ] && export CPD_SERVICE_STORAGE_CLASS="nfs-client" || export CPD_SERVICE_STORAGE_CLASS="ocs-storagecluster-cephfs"

# DB2WH variables
export DB2_META_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
export DB2_DATA_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
export DB2_BACKUP_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
export DB2_LOGS_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
export DB2_TEMP_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS

# Variables required by ocp_provision Ansible role
CLUSTER_TYPE_ORIG=$CLUSTER_TYPE
export CLUSTER_TYPE="ipi"
export IPI_PLATFORM="gcp"
export IPI_REGION=$DEPLOY_REGION
export IPI_CONTROLPLANE_TYPE="e2-standard-8"
export IPI_COMPUTE_TYPE="e2-standard-16"
export IPI_BASE_DOMAIN=$BASE_DOMAIN
export IPI_PULL_SECRET_FILE=$OPENSHIFT_PULL_SECRET_FILE_PATH
export GOOGLE_APPLICATION_CREDENTIALS=${GIT_REPO_HOME}/service-account.json
export GOOGLE_PROJECTID=$GOOGLE_PROJECTID
export SSH_PUB_KEY=$SSH_KEY_NAME
log "Below are Cloud specific deployment parameters,"
log " STORAGE_TYPE=$STORAGE_TYPE"
log " MONGODB_STORAGE_CLASS: $MONGODB_STORAGE_CLASS"
log " KAFKA_STORAGE_CLASS: $KAFKA_STORAGE_CLASS"
log " SLS_STORAGE_CLASS: $SLS_STORAGE_CLASS"
log " UDS_STORAGE_CLASS: $UDS_STORAGE_CLASS"
log " CPD_PRIMARY_STORAGE_CLASS: $CPD_PRIMARY_STORAGE_CLASS"
log " CPD_METADATA_STORAGE_CLASS: $CPD_METADATA_STORAGE_CLASS"
log " CPD_SERVICE_STORAGE_CLASS: $CPD_SERVICE_STORAGE_CLASS"
log " SSH_PUB_KEY: $SSH_PUB_KEY"

## Download files from cloud storage bucket
# Download SLS certificate
cd $GIT_REPO_HOME
if [[ ${SLS_PUB_CERT_URL,,} =~ ^https? ]]; then
  log "Downloading SLS certificate from HTTP URL"
  wget "$SLS_PUB_CERT_URL" -O sls.crt
fi
if [[ -f sls.crt ]]; then
  chmod 600 sls.crt
fi
# Download UDS certificate
cd $GIT_REPO_HOME
if [[ ${UDS_PUB_CERT_URL,,} =~ ^https? ]]; then
  log "Downloading UDS certificate from HTTP URL"
  wget "$UDS_PUB_CERT_URL" -O uds.crt
fi
if [[ -f uds.crt ]]; then
  chmod 600 uds.crt
fi
# Download service account credentials file
cd $GIT_REPO_HOME
if [[ ${GOOGLE_APPLICATION_CREDENTIALS_FILE,,} =~ ^https? ]]; then
  log "Downloading service account credentials file from HTTP URL"
  wget "$GOOGLE_APPLICATION_CREDENTIALS_FILE" -O service-account.json
fi
if [[ -f service-account.json ]]; then
  chmod 600 service-account.json
fi

# Read License File & Retrive SLS hostname and host id
if [[ -n "$MAS_LICENSE_URL" ]]; then
  line=$(head -n 1 entitlement.lic)
  set -- $line
  hostid=$3
  log " SLS_HOST_ID: $hostid"
  # SLS Instance name
  export SLS_LICENSE_ID="$hostid"
  log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
  log " SLS_LICENSE_ID=$SLS_LICENSE_ID"
else
  log " MAS LICENSE URL file is not available."
fi


## Create OCP cluster
log "==== OCP cluster creation started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
# Provision OCP cluster
export ROLE_NAME=ocp_provision && ansible-playbook ibm.mas_devops.run_role
log "==== OCP cluster creation completed ===="
CLUSTER_TYPE=$CLUSTER_TYPE_ORIG

# Login to GCP
gcloud auth activate-service-account --key-file=$GIT_REPO_HOME/service-account.json
sleep 5
log "Logged into using service account"

## Create bastion host
cd $GIT_REPO_HOME/gcp
set +e
./create-bastion-host.sh
retcode=$?
if [[ $retcode -ne 0 ]]; then
  log "Bastion host creation failed in Terraform step"
  exit 22
fi
set -e

## Create deployment context bucket
log "==== Deployment context bucket creation started ===="
set +e
gcloud storage buckets create gs://masocp-${RANDOM_STR}-bucket --location $DEPLOY_REGION
retcode=$?
echo "retcode=$retcode"
if [[ $retcode -ne 0 ]]; then
  log "Failed to create deployment context bucket."
  exit 23
fi
set -e
log "==== Deployment context bucket creation completed  ===="

# Backup deployment context
cd $GIT_REPO_HOME
rm -rf /tmp/mas-multicloud
mkdir /tmp/mas-multicloud
cp -r * /tmp/mas-multicloud
cd /tmp
zip -r $BACKUP_FILE_NAME mas-multicloud/*
set +e
gsutil cp $BACKUP_FILE_NAME gs://masocp-${RANDOM_STR}-bucket/ocp-cluster-provisioning-deployment-context/
retcode=$?
echo "retcode=$retcode"
if [[ $retcode -ne 0 ]]; then
  log "Failed while uploading deployment context to Cloud Storage bucket"
  exit 23
fi
set -e
log "OCP cluster deployment context backed up at $DEPLOYMENT_CONTEXT_UPLOAD_PATH in file $CLUSTER_NAME.zip"

# Configure htpasswd
kubeconfigfile="/root/openshift-install/config/${CLUSTER_NAME}/auth/kubeconfig"
htpasswd -c -B -b /tmp/.htpasswd $OCP_USERNAME $OCP_PASSWORD
oc delete secret htpass-secret -n openshift-config --kubeconfig $kubeconfigfile | true > /dev/null 2>&1
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/.htpasswd -n openshift-config --kubeconfig $kubeconfigfile
log "Created OpenShift secret for htpasswd"
oc apply -f $GIT_REPO_HOME/templates/oauth-htpasswd.yml --kubeconfig $kubeconfigfile
log "Created OAuth configuration in OpenShift cluster"
oc adm policy add-cluster-role-to-user cluster-admin $OCP_USERNAME --kubeconfig $kubeconfigfile
log "Updated cluster-admin role in OpenShift cluster"

# Login to OCP cluster using newly htpasswd credentials
set +e
sleep 10
login=failed
for counter in {0..9}
do
  oc login --insecure-skip-tls-verify=true -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
  if [[ $? -ne 0 ]]; then
    log "OCP login failed, waiting ..."
    sleep 60
  else
    log "OCP login successful"
    login=success
    break
  fi
done
if [[ $login == "failed" ]]; then
  log "Could not login to OpenShift cluster, exiting"
  exit 1
fi
set -e

# Create a secret in the Cloud to keep OCP access credentials
export OPENSHIFT_CLUSTER_CONSOLE_URL="https:\/\/console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
export OPENSHIFT_CLUSTER_API_URL="https:\/\/api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
cd $GIT_REPO_HOME
./create-secret.sh ocp

log "==== Adding PID limits to worker nodes ===="
oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml

log "==== Adding ER key details to OCP default pull-secret ===="
cd /tmp
export OCP_SERVER="$(echo https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443)"
oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=$OCP_SERVER --insecure-skip-tls-verify=true
export OCP_TOKEN="$(oc whoami --show-token)"
oc extract secret/pull-secret -n openshift-config --keys=.dockerconfigjson --to=. --confirm
export encodedEntitlementKey=$(echo cp:$SLS_ENTITLEMENT_KEY | tr -d '\n' | base64 -w0)
export emailAddress=$(cat .dockerconfigjson | jq -r '.auths["cloud.openshift.com"].email')
jq '.auths |= . + {"cp.icr.io": { "auth" : "$encodedEntitlementKey", "email" : "$emailAddress"}}' .dockerconfigjson >/tmp/dockerconfig.json

envsubst </tmp/dockerconfig.json >/tmp/.dockerconfigjson
oc set data secret/pull-secret -n openshift-config --from-file=/tmp/.dockerconfigjson

## Configure gce-pd-ssd storage class
log "==== Storageclass gce-pd-ssd configuration started ===="
cd $GIT_REPO_HOME/gcp/ansible-playbooks
ansible-playbook configure-gce-pd-ssd.yaml
log "==== Storageclass gce-pd-ssd configuration completed ===="

## Configure storage
if [[ $STORAGE_TYPE == "odf" ]]; then
  export CLUSTER_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/cluster-api-cluster}')
  export REGION=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.region}')
  export GCP_PROJECT_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.projectID}')
  export GCP_SERVICEACC_EMAIL=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.serviceAccounts[0].email}')
  log " CLUSTER_ID=$CLUSTER_ID"
  log " REGION=$REGION"
  log " GCP_PROJECT_ID=$GCP_PROJECT_ID"
  log " GCP_SERVICEACC_EMAIL=$GCP_SERVICEACC_EMAIL"
elif [[ $STORAGE_TYPE == "nfs" ]]; then
  # Create filestore instance
  NFS_FILESTORE_NAME=${CLUSTER_NAME}-nfs
  VPCNAME=$(cat /root/openshift-install/config/$CLUSTER_NAME/cluster.tfvars.json | jq ".network" | cut -d '/' -f 10 | tr -d '\\"')
  if [[ -z $VPCNAME ]]; then
    log " ERROR: Could not retrieve VPC name"
    exit 1
  fi
  log " VPCNAME=$VPCNAME"
  zonesuffix=$(gcloud compute regions describe $DEPLOY_REGION --format=json | jq ".zones[0]" | tr -d '"' | cut -d '/' -f 9 | cut -d '-' -f 3)
  ZONENAME=${DEPLOY_REGION}-${zonesuffix}
  log " ZONENAME=$ZONENAME"
  gcloud filestore instances create $NFS_FILESTORE_NAME --file-share=name=masocp_gcp_nfs,capacity=3TB --tier=basic-ssd --network=name=$VPCNAME --region=$DEPLOY_REGION --zone=$ZONENAME
  export GCP_NFS_SERVER=$(gcloud filestore instances describe $NFS_FILESTORE_NAME --zone=$ZONENAME --location=$DEPLOY_REGION --format=json | jq ".networks[0].ipAddresses[0]" | tr -d '"')
  log "NFS filestore $NFS_FILESTORE_NAME created in GCP with IP address $GCP_NFS_SERVER"
  if [[ -z $GCP_NFS_SERVER ]]; then
    log " ERROR: Could not retrieve filestore instance IP address"
    exit 1
  fi
  
  export GCP_FILE_SHARE_NAME="/masocp_gcp_nfs"
  log " GCP_FILE_SHARE_NAME=$GCP_FILE_SHARE_NAME"
  sleep 60
fi
log "==== Storageclass configuration started ===="
cd $GIT_REPO_HOME/gcp/ansible-playbooks
ansible-playbook configure-storage.yaml --extra-vars "storage_type=$STORAGE_TYPE"
log "==== Storageclass configuration completed ===="

if [[ $STORAGE_TYPE == "odf" ]]; then
  # Add label to the Cloud storage bucket created by ODF storage
  CLDSTGBKT=$(oc get backingstores -n openshift-storage -o json | jq ".items[].spec.googleCloudStorage.targetBucket" | tr -d '"')
  log " CLDSTGBKT: $CLDSTGBKT"
  if [[ -n $CLDSTGBKT ]]; then
    log " Adding label to Cloud Storage bucket"
    gsutil label ch -l createdby:$CLUSTER_NAME gs://${CLUSTER_NAME}-bucket
  fi
fi

## Configure IBM catalogs, deploy common services and cert manager
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
log "==== OCP cluster configuration (Cert Manager) completed ===="

## Deploy MongoDB
log "==== MongoDB deployment started ===="
export ROLE_NAME=mongodb && ansible-playbook ibm.mas_devops.run_role
log "==== MongoDB deployment completed ===="

## Copying the entitlement.lic to MAS_CONFIG_DIR
if [[ -n "$MAS_LICENSE_URL" ]]; then
  cp $GIT_REPO_HOME/entitlement.lic $MAS_CONFIG_DIR
fi

if [[ $DEPLOY_MANAGE == "true" && $DEPLOY_CP4D == "true" ]]; then
  ## Deploy Amqstreams
  log "==== Amq streams deployment started ===="
  export ROLE_NAME=kafka && ansible-playbook ibm.mas_devops.run_role
  log "==== Amq streams deployment completed ===="
fi

## Deploy SLS
# sls and gencfg_sls are combined in common sls role, works when SLS_URL is set, handled in same sls role
log "==== SLS deployment started ===="
export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
log "==== SLS deployment completed ===="

# Deploy UDS
log "==== UDS deployment started ===="
# uds and gencfg_uds are combined in common uds role, works when UDS_ENDPOINT_URL is set, handled in same uds role
export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
log "==== UDS deployment completed ===="

## Deploy CP4D
if [[ $DEPLOY_CP4D == "true" ]]; then
  log "==== CP4D deployment started ===="
  export ROLE_NAME=cp4d && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=db2 && ansible-playbook ibm.mas_devops.run_role
  log "==== CP4D deployment completed ===="
fi

## Create MAS Workspace
log "==== MAS Workspace generation started ===="
export ROLE_NAME=gencfg_workspace && ansible-playbook ibm.mas_devops.run_role
log "==== MAS Workspace generation completed ===="

if [[ $DEPLOY_MANAGE == "true" ]]; then
  log "==== Configure JDBC  started ===="
  export ROLE_NAME=gencfg_jdbc && ansible-playbook ibm.mas_devops.run_role
  log "==== Configure JDBC completed ===="
fi

## Deploy MAS
log "==== MAS deployment started ===="
export ROLE_NAME=suite_install && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_config && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_verify && ansible-playbook ibm.mas_devops.run_role
log "==== MAS deployment completed ===="

## Deploy Manage
if [[ $DEPLOY_MANAGE == "true" ]]; then
  # Deploy Manage
  log "==== MAS Manage deployment started ===="
  export ROLE_NAME=suite_app_install && ansible-playbook ibm.mas_devops.run_role
  log "==== MAS Manage deployment completed ===="

  # Configure app to use the DB
  log "==== MAS Manage configure app started ===="
  export ROLE_NAME=suite_app_config && ansible-playbook ibm.mas_devops.run_role
  log "==== MAS Manage configure app completed ===="
fi
