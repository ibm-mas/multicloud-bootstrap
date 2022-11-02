#!/bin/bash
set -e

# This script deploys OpenShift cluster and MAS application

## Variables
# Mongo variables
export MONGODB_STORAGE_CLASS="gce-pd-ssd"
# Amqstreams variables
export KAFKA_STORAGE_CLASS="gce-pd-ssd"
# SLS variables
export SLS_STORAGE_CLASS="gce-pd-ssd"
# UDS variables
export UDS_STORAGE_CLASS="gce-pd-ssd"
# CP4D variables
export CPD_PRIMARY_STORAGE_CLASS="ocs-storagecluster-cephfs"
export CPD_METADATA_STORAGE_CLASS="gce-pd-ssd"
export CPD_SERVICE_STORAGE_CLASS="ocs-storagecluster-cephfs"
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

log "Below are Cloud specific deployment parameters,"
log " MONGODB_STORAGE_CLASS: $MONGODB_STORAGE_CLASS"
log " KAFKA_STORAGE_CLASS: $KAFKA_STORAGE_CLASS"
log " SP_NAME: $SP_NAME"
log " SLS_STORAGE_CLASS: $SLS_STORAGE_CLASS"
log " UDS_STORAGE_CLASS: $UDS_STORAGE_CLASS"
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

### Read License File & Retrive SLS hostname and host id
if [[ -n "$MAS_LICENSE_URL" ]]; then
  line=$(head -n 1 entitlement.lic)
  set -- $line
  hostid=$3
  log " SLS_HOST_ID: $hostid"
  #SLS Instance name
  export SLS_LICENSE_ID="$hostid"
  log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
  log " SLS_LICENSE_ID=$SLS_LICENSE_ID"
else
  log " MAS LICENSE URL file is not available."
fi

## Create OCP cluster
log "==== OCP cluster creation started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e
# Provision OCP cluster
export ROLE_NAME=ocp_provision && ansible-playbook ibm.mas_devops.run_role
log "==== OCP cluster creation completed ===="
CLUSTER_TYPE=$CLUSTER_TYPE_ORIG

# Login to GCP
gcloud auth activate-service-account --key-file=$GIT_REPO_HOME/service-account.json

# Configure htpasswd
kubeconfigfile="/root/openshift-install/config/${CLUSTER_NAME}/auth/kubeconfig"
htpasswd -c -B -b /tmp/.htpasswd $OCP_USERNAME $OCP_PASSWORD
oc delete secret htpass-secret -n openshift-config --kubeconfig $kubeconfigfile > /dev/null 2>&1
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/.htpasswd -n openshift-config --kubeconfig $kubeconfigfile
log "Created OpenShift secret for htpasswd"
oc apply -f $GIT_REPO_HOME/templates/oauth-htpasswd.yml --kubeconfig $kubeconfigfile
echo "Created OAuth configuration in OpenShift cluster"
oc adm policy add-cluster-role-to-user cluster-admin $OCP_USERNAME --kubeconfig $kubeconfigfile
echo "Updated cluster-admin role in OpenShift cluster"
sleep 60
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
# Create a secret in the Cloud to keep OCP access credentials
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
log "==== Configure gce-pd-ssd storage class - started ===="
cd $GIT_REPO_HOME/gcp/ansible-playbooks
set +e
ansible-playbook configure-gce-pd-ssd.yaml
set -e
log "==== Configure gce-pd-ssd storage class - completed ===="

## Configure ODF on gcp cluster
log "==== Configure ODF on gcp cluster - started ===="
cd $GIT_REPO_HOME/gcp/ansible-playbooks
set +e
export CLUSTER_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/cluster-api-cluster}')
export REGION=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.region}')
export GCP_PROJECT_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.projectID}')
export GCP_SERVICEACC_EMAIL=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.serviceAccounts[0].email}')
ansible-playbook configure-odf.yaml -vvv
set -e
log "==== Configure ODF on gcp cluster - completed ===="

## Configure IBM catalogs, deploy common services and cert manager
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
set -e
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
