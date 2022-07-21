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
export CPD_METADATA_STORAGE_CLASS=managed-premium
export CPD_SERVICE_STORAGE_CLASS=azurefiles-premium

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
  chmod 600 entitlement.lic
fi

# Download SLS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${SLS_PUB_CERT_URL} ]]; then
  azcopy copy "${SLS_PUB_CERT_URL}" "sls.crt"
  chmod 600 sls.crt
fi
# Download BAS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${UDS_PUB_CERT_URL} ]]; then
  azcopy copy "${UDS_PUB_CERT_URL}" "uds.crt"
  chmod 600 uds.crt
fi

## Read License File & Retrive SLS hostname and host id
line=$(head -n 1 entitlement.lic)
set -- $line
hostid=$3
log " SLS_HOST_ID: $hostid"
# SLS Instance name
export SLS_LICENSE_ID="$hostid"
log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
log " SLS_LICENSE_ID=$SLS_LICENSE_ID"

# Deploy OCP cluster and bastion host
if [[ $OPENSHIFT_USER_PROVIDE == "false" ]]; then
  cd $GIT_REPO_HOME

  ## Create OCP cluster
  if [[ $INSTALLATION_MODE == "IPI" ]]; then
    cd $GIT_REPO_HOME/azure
    set +e
    ./create-ocp-cluster.sh
    retcode=$?
    if [[ $retcode -ne 0 ]]; then
      log "OCP cluster creation failed in Terraform step"
      exit 21
    fi
    set -e
  else
    cd $GIT_REPO_HOME/azure/upifiles
    set +e
    ./create-ocp-cluster-upi.sh
    retcode=$?
    if [[ $retcode -ne 0 ]]; then
      log "OCP cluster creation failed in UPI step"
      exit 21
    fi
    set -e
  fi

  
  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 --insecure-skip-tls-verify=true
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
  az storage blob upload --account-name ${STORAGE_ACNT_NAME} --container-name masocpcontainer --name ${DEPLOYMENT_CONTEXT_UPLOAD_PATH} --file ${BACKUP_FILE_NAME} 
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
cd $GIT_REPO_HOME/azure/azurefiles
./azurefiles-premium.sh
retcode=$?
if [[ $retcode -ne 0 ]]; then
  log "Failed to create azurefiles-premium storageclass"
  exit 27
fi

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager and SBO) started ===="
cd $GIT_REPO_HOME
set +e
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=sbo && ansible-playbook ibm.mas_devops.run_role
if [[ $? -ne 0 ]]; then
  # One reason for this failure is catalog sources not having required state information, so recreate the catalog-operator pod
  # https://bugzilla.redhat.com/show_bug.cgi?id=1807128
  echo "Deleting catalog-operator pod"
  podname=$(oc get pods -n openshift-operator-lifecycle-manager | grep catalog-operator | awk {'print $1'})
  oc logs $podname -n openshift-operator-lifecycle-manager
  oc delete pod $podname -n openshift-operator-lifecycle-manager
  sleep 10
  # Retry the step
  export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=sbo && ansible-playbook ibm.mas_devops.run_role
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
export ROLE_NAME=mongodb && ansible-playbook ibm.mas_devops.run_role
log "==== MongoDB deployment completed ===="

## Copying the entitlement.lic to MAS_CONFIG_DIR
cp $GIT_REPO_HOME/entitlement.lic $MAS_CONFIG_DIR

## Deploy Amqstreams
# log "==== Amq streams deployment started ===="
# ansible-playbook install-amqstream.yml
# log "==== Amq streams deployment completed ===="

# SLS Deployment
if [[ (-z $SLS_URL) || (-z $SLS_REGISTRATION_KEY) || (-z $SLS_PUB_CERT_URL) ]]; then
  ## Deploy SLS
  log "==== SLS deployment started ===="
  # sls and gencfg_sls are combined in common sls role
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "==== SLS deployment completed ===="

else
  log "=== Using Existing SLS Deployment ==="  #
  # works when SLS_URL is set, handled in same sls role
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated SLS Config YAML ==="
fi

# Deploy UDS
if [[ (-z $UDS_API_KEY) || (-z $UDS_ENDPOINT_URL) || (-z $UDS_PUB_CERT_URL) ]]; then
  # Deploy UDS
  log "==== UDS deployment started ===="
  # uds and gencfg_uds are combined in common uds role
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "==== UDS deployment completed ===="

else
  log "=== Using Existing UDS Deployment ==="
  # works when UDS_ENDPOINT_URL is set, handled in same uds role
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated UDS Config YAML ==="
fi

# Deploy CP4D
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
export ROLE_NAME=suite_dns && ansible-playbook ibm.mas_devops.run_role
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
