#!/bin/bash
set -e

# This script will initiate the provisioning process of MAS. It will perform following steps,

## Variables
# Mongo variables
export MONGODB_STORAGE_CLASS=managed-premium
# Amqstreams variables
export KAFKA_STORAGE_CLASS=managed-premium
# Service principle variables
SP_NAME="http://${CLUSTER_NAME}-sp"
# SLS variables
export SLS_STORAGE_CLASS=managed-premium
# BAS variables
export UDS_STORAGE_CLASS=managed-premium
# CP4D variables
export CPD_METADB_BLOCK_STORAGE_CLASS=managed-premium

log "Below are Cloud specific deployment parameters,"
log " MONGODB_STORAGE_CLASS: $MONGODB_STORAGE_CLASS"
log " KAFKA_STORAGE_CLASS: $KAFKA_STORAGE_CLASS"
log " SP_NAME: $SP_NAME"
log " SLS_STORAGE_CLASS: $SLS_STORAGE_CLASS"
log " UDS_STORAGE_CLASS: $UDS_STORAGE_CLASS"
log " SSH_PUB_KEY: $SSH_PUB_KEY"

## Download files from S3 bucket
# Download MAS license
log "==== Downloading MAS license ===="
cd $GIT_REPO_HOME
if [[ ! -z ${MAS_LICENSE_URL} ]]; then
  azcopy copy "${MAS_LICENSE_URL}" "entitlement.lic"
fi

# Download SLS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${SLS_PUB_CERT_URL} ]]; then
  azcopy copy "${SLS_PUB_CERT_URL}" "sls.crt"
fi
# Download BAS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${UDS_PUB_CERT_URL} ]]; then
  azcopy copy "${UDS_PUB_CERT_URL}" "uds.crt"
fi

## Read License File & Retrive SLS hostname and host id
line=$(head -n 1 entitlement.lic)
set -- $line
hostname=$2
hostid=$3
log " SLS_HOSTNAME: $hostname"
log " SLS_HOST_ID: $hostid"
# SLS Instance name
export SLS_INSTANCE_NAME="$hostname"
export SLS_LICENSE_ID="$hostid"

# Deploy OCP cluster and bastion host
if [[ $OPENSHIFT_USER_PROVIDE == "false" ]]; then
  cd $GIT_REPO_HOME

  ## Create OCP cluster
  cd $GIT_REPO_HOME/azure
  set +e
  ./create-ocp-cluster.sh
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "OCP cluster creation failed in Terraform step"
    exit 21
  fi
  set -e

  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
  log "==== Adding PID limits to worker nodes ===="
  oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml

  # Backup Terraform configuration
  rm -rf /tmp/ansible-devops
  mkdir /tmp/ansible-devops
  cp -r * /tmp/ansible-devops
  cd /tmp
  zip -r $BACKUP_FILE_NAME ansible-devops/*
  rm -rf /tmp/ansible-devops
  set +e
  az storage blob upload --account-name ${STORAGE_ACNT_NAME} --container-name masocpcontainer --name ${DEPLOYMENT_CONTEXT_UPLOAD_PATH} --file ${BACKUP_FILE_NAME} --auth-mode login
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "Failed while uploading deployment context to blob storage3"
    exit 23
  fi
  set -e
  log "OCP cluster Terraform configuration backed up at $DEPLOYMENT_CONTEXT_UPLOAD_PATH in file $CLUSTER_NAME.zip"

else
  log "==== Existing OCP cluster provided, skipping the cluster creation, Bastion host creation and S3 upload of deployment context ===="
fi

# Login to OCP cluster
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

# Run ansible playbook to create azurefiles storage class
log "=== Creating azurefiles-premium Storage class on OCP cluster ==="
cd $GIT_REPO_HOME/azure
./azurefiles-premium.sh
retcode=$?
if [[ $retcode -ne 0 ]]; then
  log "Failed to create azurefiles-premium storageclass"
  exit 27
fi

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager and SBO) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e
ansible-playbook ocp/configure-ocp.yml
if [[ $? -ne 0 ]]; then
  # One reason for this failure is catalog sources not having required state information, so recreate the catalog-operator pod
  # https://bugzilla.redhat.com/show_bug.cgi?id=1807128
  echo "Deleting catalog-operator pod"
  podname=$(oc get pods -n openshift-operator-lifecycle-manager | grep catalog-operator | awk {'print $1'})
  oc logs $podname -n openshift-operator-lifecycle-manager
  oc delete pod $podname -n openshift-operator-lifecycle-manager
  sleep 10
  # Retry the step
  ansible-playbook ocp/configure-ocp.yml
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "Failed while configuring OCP cluster"
    exit 24
  fi
fi
set -e
log "==== OCP cluster configuration (Cert Manager and SBO) completed ===="

## Deploy MongoDB
log "==== MongoDB deployment started ===="
ansible-playbook dependencies/install-mongodb-ce.yml
log "==== MongoDB deployment completed ===="

## Copying the entitlement.lic to MAS_CONFIG_DIR
cp $GIT_REPO_HOME/entitlement.lic $MAS_CONFIG_DIR

## Deploy Amqstreams
# log "==== Amq streams deployment started ===="
# ansible-playbook install-amqstream.yml
# log "==== Amq streams deployment completed ===="

# SLS Deployment
if [[ (-z $SLS_ENDPOINT_URL) || (-z $SLS_REGISTRATION_KEY) || (-z $SLS_PUB_CERT_URL) ]]; then
  ## Deploy SLS
  log "==== SLS deployment started ===="
  ansible-playbook dependencies/install-sls.yml
  log "==== SLS deployment completed ===="

else
  log "=== Using Existing SLS Deployment ==="
  ansible-playbook dependencies/gencfg-sls.yml
  log "=== Generated SLS Config YAML ==="
fi

#UDS Deployment
if [[ (-z $UDS_API_KEY) || (-z $UDS_ENDPOINT_URL) || (-z $UDS_PUB_CERT_URL) ]]; then
  ## Deploy UDS
  log "==== UDS deployment started ===="
  ansible-playbook dependencies/install-uds.yml
  log "==== UDS deployment completed ===="

else
  log "=== Using Existing UDS Deployment ==="
  ansible-playbook dependencies/gencfg-uds.yml
  log "=== Generated UDS Config YAML ==="
fi

# Deploy CP4D
if [[ $DEPLOY_CP4D == "true" ]]; then
  log "==== CP4D deployment started ===="
  ansible-playbook cp4d/install-services-db2.yml
  ansible-playbook cp4d/create-db2-instance.yml
  log "==== CP4D deployment completed ===="
fi

## Create MAS Workspace
log "==== MAS Workspace generation started ===="
ansible-playbook mas/gencfg-workspace.yml
log "==== MAS Workspace generation completed ===="

if [[ $DEPLOY_MANAGE == "true" ]]; then
  log "==== Configure JDBC  started ===="
  ansible-playbook mas/configure-suite-db.yml
  log "==== Configure JDBC completed ===="
fi

## Deploy MAS
log "==== MAS deployment started ===="
ansible-playbook mas/install-suite.yml
log "==== MAS deployment completed ===="

## Deploy Manage
if [[ $DEPLOY_MANAGE == "true" ]]; then
  # Deploy Manage
  log "==== MAS Manage deployment started ===="
  ansible-playbook mas/install-app.yml
  log "==== MAS Manage deployment completed ===="

  # Configure app to use the DB
  log "==== MAS Manage configure app started ===="
  ansible-playbook mas/configure-app.yml
  log "==== MAS Manage configure app completed ===="
fi
