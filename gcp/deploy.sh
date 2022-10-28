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
# BAS variables
export UDS_STORAGE_CLASS="gce-pd-ssd"
# CP4D variables
export CPD_METADATA_STORAGE_CLASS="gce-pd-ssd"
export CPD_SERVICE_STORAGE_CLASS="ocs-storagecluster-cephfs"
# Variables required by ocp_provision Ansible role
export CLUSTER_TYPE="ipi"
export IPI_PLATFORM="gcp"
export IPI_REGION=$DEPLOY_REGION
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

# Configure htpasswd
kubeconfigfile="/root/openshift-install/config/${CLUSTER_NAME}/auth/kubeconfig"
htpasswd -c -B -b /tmp/.htpasswd $OCP_USERNAME $OCP_PASSWORD
sleep 10
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/.htpasswd -n openshift-config --kubeconfig $kubeconfigfile
log "Created OpenShift secret for htpasswd"
oc apply -f $GIT_REPO_HOME/templates/htpasswd.yml --kubeconfig $kubeconfigfile
echo "Created OAuth configuration in OpenShift cluster"
oc adm policy add-cluster-role-to-user cluster-admin $OCP_USERNAME --kubeconfig $kubeconfigfile
echo "Updated cluster-admin role in OpenShift cluster"
sleep 60
login=failed
for VARIABLE in {0..9}
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

log "==== Adding PID limits to worker nodes ===="
oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml

# Configure IBM catalogs, deploy common services and cert manager
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
