#!/bin/bash
#
# This is the init script that will call the individual Cloud specific script
#

## Inputs
export CLUSTER_TYPE=$1
export OFFERING_TYPE=$2
export DEPLOY_REGION=$3
export ACCOUNT_ID=$4
export CLUSTER_SIZE=$5
export RANDOM_STR=$6
export BASE_DOMAIN=$7
export BASE_DOMAIN_RG_NAME=$8
export SSH_KEY_NAME=$9
export DEPLOY_WAIT_HANDLE=${10}
export SLS_ENTITLEMENT_KEY=${11}
export OCP_PULL_SECRET=${12}
export MAS_LICENSE_URL=${13}
export SLS_URL=${14}
export SLS_REGISTRATION_KEY=${15}
export SLS_PUB_CERT_URL=${16}
export DRO_ENDPOINT_URL=${17}
export DRO_API_KEY=${18}
export DRO_PUB_CERT_URL=${19}
export MAS_JDBC_USER=${20}
export MAS_JDBC_PASSWORD=${21}
export MAS_JDBC_URL=${22}
export MAS_JDBC_CERT_URL=${23}
export MAS_APP_SETTINGS_DEMODATA=${24}
export EXS_OCP_URL=${25}
export EXS_OCP_USER=${26}
export EXS_OCP_PWD=${27}
export RG_NAME=${28}
export EMAIL_NOTIFICATION=${29}
export RECEPIENT=${30}
export SMTP_HOST=${31}
export SMTP_PORT=${32}
export SMTP_USERNAME=${33}
export SMTP_PASSWORD=${34}
export AZURE_SP_CLIENT_ID=${35}
export AZURE_SP_CLIENT_PWD=${36}
export SELLER_SUBSCRIPTION_ID=${37}
export TENANT_ID=${38}
export GOOGLE_PROJECTID=${39}
export GOOGLE_APPLICATION_CREDENTIALS_FILE=${40}
export BOOTNODE_VPC_ID=${41}
export BOOTNODE_SUBNET_ID=${42}
export EXISTING_NETWORK=${43}
export EXISTING_NETWORK_RG=${44}
export EXISTING_PRIVATE_SUBNET1_ID=${45}
export EXISTING_PRIVATE_SUBNET2_ID=${46}
export EXISTING_PRIVATE_SUBNET3_ID=${47}
export EXISTING_PUBLIC_SUBNET1_ID=${48}
export EXISTING_PUBLIC_SUBNET2_ID=${49}
export EXISTING_PUBLIC_SUBNET3_ID=${50}
export PRIVATE_CLUSTER=${51}
export OPERATIONAL_MODE=${52}

#true if use existing instance selected, false if provision new instance selected
export MONGO_USE_EXISTING_INSTANCE=${53}
export MONGO_FLAVOR=${54}
export MONGO_ADMIN_USERNAME=${55}
export MONGO_ADMIN_PASSWORD=${56}
export MONGO_HOSTS=${57}
export MONGO_CA_PEM_FILE=${58}
export DOCUMENTDB_VPC_ID=${59}
export AWS_MSK_PROVIDER=${60}
export DBProvisionedVPCId=${61}
export ExocpProvisionedVPCId=${62}
export EBSVolumeType=${63}
export MANAGE_TABLESPACE=${64}
export ENV_TYPE=${65}
export GIT_REPO_HOME=$(pwd)
# Load helper functions
. helper.sh
export -f log
export -f get_mas_creds
export -f retrieve_mas_ca_cert
export -f mark_provisioning_failed
export -f get_sls_endpoint_url
export -f get_sls_registration_key
export -f get_dro_endpoint_url
export -f get_dro_api_key
export -f validate_product_type

export GIT_REPO_HOME=$(pwd)

## Configure CloudWatch agent
if [[ $CLUSTER_TYPE == "aws" ]]; then
  log "Configuring CloudWatch logs agent"
  # TODO Temporary code to install CloudWatch agent. Later this will be done in AMI, and remove the code
  #-----------------------------------------
  cd /tmp
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm
  rpm -U ./amazon-cloudwatch-agent.rpm
  #-----------------------------------------
  # Create CloudWatch agent config file
  mkdir -p /opt/aws/amazon-cloudwatch-agent/bin
  cat <<EOT >> /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [{
          "file_path": "/root/ansible-devops/multicloud-bootstrap/mas-provisioning.log",
          "log_group_name": "/ibm/mas/masocp-${RANDOM_STR}",
          "log_stream_name": "mas-provisioning-logs"
        }]
      }
    }
  }
}
EOT
  # Start CloudWatch agent service
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
  sleep 60
  cd -
fi
# Check for input parameters
if [[ (-z $CLUSTER_TYPE) || (-z $DEPLOY_REGION) || (-z $RANDOM_STR) || (-z $CLUSTER_SIZE) || (-z $SLS_ENTITLEMENT_KEY) \
   || (-z $SSH_KEY_NAME) ]]; then
  log "ERROR: Required parameter not specified, please provide all the required inputs to the script."
  PRE_VALIDATION=fail
fi

if [[ $OFFERING_TYPE == "MAS Core" ]]; then
  export DEPLOY_CP4D="false"
  export DEPLOY_MANAGE="false"
elif [[ $OFFERING_TYPE == "MAS Core + Manage" ]]; then
  export DEPLOY_CP4D="false"
  export DEPLOY_MANAGE="true"
elif [[ $OFFERING_TYPE == "MAS Core + Cloud Pak for Data + Manage" ]]; then
  export DEPLOY_CP4D="true"
  export DEPLOY_MANAGE="true"
else
  log "ERROR: Incorrect value for OFFERING_TYPE - $OFFERING_TYPE"
  PRE_VALIDATION=fail
fi

## Variables
# OCP variables
export CLUSTER_NAME="masocp-${RANDOM_STR}"
export OCP_USERNAME="masocpuser"
export OCP_PASSWORD="mas${RANDOM_STR:3:3}`date +%H%M%S`${RANDOM_STR:0:3}"
if [[ (! -z $EXS_OCP_URL) && (! -z $EXS_OCP_USER) && (! -z $EXS_OCP_PWD) ]]; then
    export OCP_USERNAME=${EXS_OCP_USER}
    export OCP_PASSWORD=${EXS_OCP_PWD}
fi
export OPENSHIFT_PULL_SECRET_FILE_PATH=${GIT_REPO_HOME}/pull-secret.json
export MASTER_NODE_COUNT="3"
export WORKER_NODE_COUNT="3"
export AZ_MODE="multi_zone"
export OCP_VERSION="4.14.26"

export MAS_IMAGE_TEST_DOWNLOAD="cp.icr.io/cp/mas/admin-dashboard:5.1.27"
export BACKUP_FILE_NAME="deployment-backup-${CLUSTER_NAME}.zip"
if [[ $CLUSTER_TYPE == "aws" ]]; then
  export DEPLOYMENT_CONTEXT_UPLOAD_PATH="s3://masocp-${RANDOM_STR}-bucket-${DEPLOY_REGION}/ocp-cluster-provisioning-deployment-context/"
fi
# Mongo variables
export MAS_INSTANCE_ID="${RANDOM_STR}"
export MAS_CONFIG_DIR=/var/tmp/masconfigdir
export MONGODB_NAMESPACE="mongoce-${RANDOM_STR}"
# SLS variables
export SLS_NAMESPACE="ibm-sls-${RANDOM_STR}"
export SLS_MONGODB_CFG_FILE="${MAS_CONFIG_DIR}/mongo-${MONGODB_NAMESPACE}.yml"

# Exporting SLS_LICENSE_FILE only when product type is different than privatepublic(i.e. Paid offering)
# Paid offering does not require entitlement.lic i.e. MAS license file.
if [[ $CLUSTER_TYPE == "aws" ]]; then
  validate_product_type
fi
if [[ ($PRODUCT_TYPE == "privatepublic") && ($CLUSTER_TYPE == "aws") ]];then
  log "Product type is privatepublic hence not exporting SLS_LICENSE_FILE variable"
else
  export SLS_LICENSE_FILE="${MAS_CONFIG_DIR}/entitlement.lic"
fi
export SLS_TLS_CERT_LOCAL_FILE_PATH="${GIT_REPO_HOME}/sls.crt"
export SLS_INSTANCE_NAME="masocp-${RANDOM_STR}"
# UDS variables
if [[ $CLUSTER_TYPE == "aws" ]]; then
  export DRO_STORAGE_CLASS="gp2"
fi
export DRO_CONTACT_EMAIL="dro.support@ibm.com"
export DRO_CONTACT_FIRSTNAME=dro
export DRO_CONTACT_LASTNAME=Support
export DRO_TLS_CERT_LOCAL_FILE_PATH="${GIT_REPO_HOME}/dro.crt"
# CP4D variables
export CPD_ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY
export CPD_VERSION=cpd40
export CPD_PRODUCT_VERSION=4.8.0
export MAS_CHANNEL=8.11.x
export MAS_CATALOG_VERSION=v9-240625-amd64
if [[ $CLUSTER_TYPE == "aws" ]]; then
  export CPD_PRIMARY_STORAGE_CLASS="ocs-storagecluster-cephfs"
fi
# DB2WH variables
export CPD_OPERATORS_NAMESPACE="ibm-cpd-operators-${RANDOM_STR}"
export CPD_INSTANCE_NAMESPACE="ibm-cpd-${RANDOM_STR}"
#CPD_SERVICES_NAMESPACE is used in roles - cp4d, cp4dv3_install, cp4dv3_install_services and suite_dns
export CPD_SERVICES_NAMESPACE="cpd-services-${RANDOM_STR}"
export ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY

# MAS variables
export MAS_ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY
export IBM_ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY
export MAS_WORKSPACE_ID="wsmasocp"
export MAS_WORKSPACE_NAME="wsmasocp"
export MAS_CONFIG_SCOPE="wsapp"
export MAS_APP_ID=manage
export MAS_APPWS_JDBC_BINDING="workspace-application"
export MAS_JDBC_CERT_LOCAL_FILE=$GIT_REPO_HOME/db.crt
export MAS_CLOUD_AUTOMATION_VERSION=1.0
export MAS_DEVOPS_COLLECTION_VERSION=20.4.0
export MAS_APP_CHANNEL=8.7.x
if [ -z "$EXISTING_NETWORK" ]; then
  export new_or_existing_vpc_subnet="new"
  export enable_permission_quota_check=true
  export PRIVATE_CLUSTER=false
  export private_or_public_cluster=public
else
   export new_or_existing_vpc_subnet="exist"
   export enable_permission_quota_check=false
   export private_or_public_cluster=public
fi
log " new_or_existing_vpc_subnet=$new_or_existing_vpc_subnet"
log " enable_permission_quota_check=$enable_permission_quota_check"


RESP_CODE=0

# Export env variables which are not set by default during userdata execution
export HOME=/root

# Decide clutser size
case $CLUSTER_SIZE in
  small)
    log "Using small size cluster"
    export MASTER_NODE_COUNT="3"
    export WORKER_NODE_COUNT="3"
    ;;
  medium)
    log "Using medium size cluster"
    export MASTER_NODE_COUNT="3"
    export WORKER_NODE_COUNT="5"
    ;;
  large)
    log "Using large size cluster"
    export MASTER_NODE_COUNT="5"
    export WORKER_NODE_COUNT="7"
    ;;
  *)
    log "Using default small size cluster"
    export MASTER_NODE_COUNT="3"
    export WORKER_NODE_COUNT="3"
    ;;
esac


# Log the variable values
log "Below are common deployment parameters,"
log " OPERATIONAL_MODE: $OPERATIONAL_MODE"
log " CLUSTER_TYPE: $CLUSTER_TYPE"
log " OFFERING_TYPE: $OFFERING_TYPE"
log " DEPLOY_REGION: $DEPLOY_REGION"
log " ACCOUNT_ID: $ACCOUNT_ID"
log " CLUSTER_SIZE: $CLUSTER_SIZE"
log " RANDOM_STR: $RANDOM_STR"
log " BASE_DOMAIN: $BASE_DOMAIN"
log " BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
log " SSH_KEY_NAME: $SSH_KEY_NAME"
log " DEPLOY_WAIT_HANDLE: $DEPLOY_WAIT_HANDLE"
# Do not log ER key and OCP pull secret, uncomment in case of debugging but comment it out once done
#log " SLS_ENTITLEMENT_KEY: $SLS_ENTITLEMENT_KEY"
#log " MAS_ENTITLEMENT_KEY: $MAS_ENTITLEMENT_KEY"
#log " ENTITLEMENT_KEY: $ENTITLEMENT_KEY"
#log " OCP_PULL_SECRET: $OCP_PULL_SECRET"
log " DEPLOY_CP4D: $DEPLOY_CP4D"
log " DEPLOY_MANAGE: $DEPLOY_MANAGE"
log " MAS_LICENSE_URL: $MAS_LICENSE_URL"
log " SLS_URL: $SLS_URL"
log " SLS_REGISTRATION_KEY: $SLS_REGISTRATION_KEY"
log " SLS_PUB_CERT_URL: $SLS_PUB_CERT_URL"
log " DRO_ENDPOINT_URL: $DRO_ENDPOINT_URL"
log " DRO_API_KEY: $DRO_API_KEY"
log " DRO_PUB_CERT_URL: $DRO_PUB_CERT_URL"
log " MAS_JDBC_USER: $MAS_JDBC_USER"
log " MAS_JDBC_URL: $MAS_JDBC_URL"
log " MAS_JDBC_CERT_URL: $MAS_JDBC_CERT_URL"
log " MAS_APP_SETTINGS_DEMODATA: $MAS_APP_SETTINGS_DEMODATA"
log " EXS_OCP_URL: $EXS_OCP_URL"
log " EXS_OCP_USER: $EXS_OCP_USER"
log " RG_NAME=$RG_NAME"
log " RECEPIENT=$RECEPIENT"
log " SMTP_HOST=$SMTP_HOST"
log " SMTP_PORT=$SMTP_PORT"
log " SMTP_USERNAME=$SMTP_USERNAME"
# Do not log SMTP password, uncomment in case of debugging but comment it out once done
#log " SMTP_PASSWORD=$SMTP_PASSWORD"
log " EMAIL_NOTIFICATION: $EMAIL_NOTIFICATION"
log " VPC/VNET NETWORK(EXISTING_NETWORK)=$EXISTING_NETWORK"
log " VPC/VNET NETWORK RG(EXISTING_NETWORK_RG)=$EXISTING_NETWORK_RG"
log " DBProvisionedVPCId=$DBProvisionedVPCId"
log " OCPVPCId(ExocpProvisionedVPCId)=$ExocpProvisionedVPCId"
log " EBSVolumeType=$EBSVolumeType"
log " ENV_TYPE=$ENV_TYPE"
log " MONGO_USE_EXISTING_INSTANCE=${MONGO_USE_EXISTING_INSTANCE}"
log " MONGO_FLAVOR=${MONGO_FLAVOR}"
log " MONGO_ADMIN_USERNAME=${MONGO_ADMIN_USERNAME}"
#log " MONGO_ADMIN_PASSWORD=${MONGO_ADMIN_PASSWORD}"
log " MONGO_HOSTS=${MONGO_HOSTS}"
log " MONGO_CA_PEM_FILE=${MONGO_CA_PEM_FILE}"
log " EXISTING_PRIVATE_SUBNET1_ID=$EXISTING_PRIVATE_SUBNET1_ID"
log " EXISTING_PRIVATE_SUBNET2_ID=$EXISTING_PRIVATE_SUBNET2_ID"
log " EXISTING_PRIVATE_SUBNET3_ID=$EXISTING_PRIVATE_SUBNET3_ID"
log " EXISTING_PUBLIC_SUBNET1_ID=$EXISTING_PUBLIC_SUBNET1_ID"
log " EXISTING_PUBLIC_SUBNET2_ID=$EXISTING_PUBLIC_SUBNET2_ID"
log " EXISTING_PUBLIC_SUBNET3_ID=$EXISTING_PUBLIC_SUBNET3_ID"
log " BOOTNODE_VPC_ID=$BOOTNODE_VPC_ID"
log " BOOTNODE_SUBNET_ID=$BOOTNODE_SUBNET_ID"
log " PRIVATE_CLUSTER=$PRIVATE_CLUSTER"
log " HOME: $HOME"
log " GIT_REPO_HOME: $GIT_REPO_HOME"
log " CLUSTER_NAME: $CLUSTER_NAME"
log " OCP_USERNAME: $OCP_USERNAME"
log " OPENSHIFT_PULL_SECRET_FILE_PATH: $OPENSHIFT_PULL_SECRET_FILE_PATH"
log " MASTER_NODE_COUNT: $MASTER_NODE_COUNT"
log " WORKER_NODE_COUNT: $WORKER_NODE_COUNT"
log " AZ_MODE: $AZ_MODE"
log " MAS_IMAGE_TEST_DOWNLOAD: $MAS_IMAGE_TEST_DOWNLOAD"
log " BACKUP_FILE_NAME: $BACKUP_FILE_NAME"
log " DEPLOYMENT_CONTEXT_UPLOAD_PATH: $DEPLOYMENT_CONTEXT_UPLOAD_PATH"
log " STORAGE_ACNT_NAME: $STORAGE_ACNT_NAME"
log " MAS_INSTANCE_ID: $MAS_INSTANCE_ID"
log " MAS_CONFIG_DIR: $MAS_CONFIG_DIR"
log " CPD_PRIMARY_STORAGE_CLASS: $CPD_PRIMARY_STORAGE_CLASS"
log " CPD_PRODUCT_VERSION: $CPD_PRODUCT_VERSION"
log " MAS_APP_ID: $MAS_APP_ID"
log " MAS_WORKSPACE_ID: $MAS_WORKSPACE_ID"
log " MAS_JDBC_CERT_LOCAL_FILE: $MAS_JDBC_CERT_LOCAL_FILE"
log " MANAGE_TABLESPACE: $MANAGE_TABLESPACE"

# Get deployment options
export DEPLOY_CP4D=$(echo $DEPLOY_CP4D | cut -d '=' -f 2)
export DEPLOY_MANAGE=$(echo $DEPLOY_MANAGE | cut -d '=' -f 2)
log " DEPLOY_CP4D: $DEPLOY_CP4D"
log " DEPLOY_MANAGE: $DEPLOY_MANAGE"

cd $GIT_REPO_HOME
# Perform prevalidation checks
log "===== PRE-VALIDATION STARTED ====="
./pre-validate.sh
retcode=$?
log "Pre validation return code is $retcode"
if [[ $retcode -ne 0 ]]; then
  log "Prevalidation checks failed"
  PRE_VALIDATION=fail
  mark_provisioning_failed $retcode
else
  log "Prevalidation checks successful"
  PRE_VALIDATION=pass
fi
log "===== PRE-VALIDATION COMPLETED ($PRE_VALIDATION) ====="


# Perform the MAS deployment only if pre-validation checks are passed
if [[ $PRE_VALIDATION == "pass" ]]; then
  ## If user provided input of Openshift API url along with creds, then use the provided details for deployment of other components like CP4D, MAS etc.
  ## Otherwise, proceed with new cluster creation.
  if [[ -n $EXS_OCP_URL && -n $EXS_OCP_USER && -n $EXS_OCP_PWD ]]; then
    log "Openshift cluster details provided"
    # https://api.masocp-cluster.mas4aws.com/
    # https://api.ftmpsl-ocp-dev3.cp.fyre.ibm.com:6443/
      export INSTALLATION_MODE="EXOCP"
    log "Debug: before: CLUSTER_NAME: $CLUSTER_NAME  BASE_DOMAIN: $BASE_DOMAIN"
    split_ocp_api_url $EXS_OCP_URL
    log "Debug: after: CLUSTER_NAME: $CLUSTER_NAME  BASE_DOMAIN: $BASE_DOMAIN"
    # echo $BASE_DOMAIN
    export OCP_USERNAME=$EXS_OCP_USER
    export OCP_PASSWORD=$EXS_OCP_PWD
    export OPENSHIFT_USER_PROVIDE="true"
    export OCP_SERVER="$(echo https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443)"
    oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=$OCP_SERVER --insecure-skip-tls-verify=true

    # Perform prerequisite checks
    log "===== PRE-REQUISITE VALIDATION STARTED ====="

    source pre-requisite.sh
    retcode=$?

    log "Pre requisite return code is $retcode"
    if [[ $retcode -ne 0 ]]; then
      log "Prerequisite checks failed"
      PRE_VALIDATION=fail
      log "Debug: Pre-requisite validation failed. Proceed to create new OCP cluster later"
      mark_provisioning_failed $retcode "$SERVICE_NAME"
    else
      log "Prerequisite checks successful"
    fi
    log "===== PRE-REQUISITE CHECKS COMPLETED  ====="
  else
    ## No input from user. Generate Cluster Name, Username, and Password.
    log "Debug: No cluster details or insufficient data provided. Proceed to create new OCP cluster later"
    export OPENSHIFT_USER_PROVIDE="false"
  fi
fi
log " OPENSHIFT_USER_PROVIDE=$OPENSHIFT_USER_PROVIDE"

if [[ $PRE_VALIDATION == "pass" ]]; then
  # Create Red Hat pull secret
  echo "$OCP_PULL_SECRET" > $OPENSHIFT_PULL_SECRET_FILE_PATH
  chmod 600 $OPENSHIFT_PULL_SECRET_FILE_PATH

  ## Installing the collection depending on ENV_TYPE
  if [[ ($CLUSTER_TYPE == "aws") ]]; then
    if [[ $ENV_TYPE == "dev" ]]; then
      log "=== Building and Installing Ansible Collection Locally ==="
      cd $GIT_REPO_HOME/../ibm/mas_devops
      ansible-galaxy collection build
      ansible-galaxy collection install --force ibm-mas_devops-*.tar.gz
      log "=== Ansible Collection built and installed locally Successfully ==="
    else
      log "MAS_DEVOPS_COLLECTION_VERSION=$MAS_DEVOPS_COLLECTION_VERSION"
      log "==== Installing Ansible Collection ===="
      ansible-galaxy collection install ibm.mas_devops:==${MAS_DEVOPS_COLLECTION_VERSION}
      log "==== Installed Ansible Collection Successfully ===="
    fi
  fi

  cd $GIT_REPO_HOME

  # Create MAS_CONFIG_DIR directory
  mkdir -p $MAS_CONFIG_DIR
  chmod 700 $MAS_CONFIG_DIR

  # Call cloud specific script
  chmod +x $CLUSTER_TYPE/*.sh
  log "===== PROVISIONING STARTED ====="
  log "Calling cloud specific automation ..."
  cd $CLUSTER_TYPE
  ./deploy.sh
  retcode=$?
  log "Deployment return code is $retcode"
  if [[ $retcode -eq 0 ]]; then
    log "Deployment successful"
    log "===== PROVISIONING COMPLETED ====="
    export STATUS=SUCCESS
    export STATUS_MSG="MAS deployment completed successfully."
    export MESSAGE_TEXT="Please import the attached certificate into the browser to access MAS UI."
    export OPENSHIFT_CLUSTER_CONSOLE_URL="https:\/\/console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    export OPENSHIFT_CLUSTER_API_URL="https:\/\/api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
    export MAS_URL_INIT_SETUP="https:\/\/admin.${RANDOM_STR}.apps.${CLUSTER_NAME}.${BASE_DOMAIN}\/initialsetup"
    export MAS_URL_ADMIN="https:\/\/admin.${RANDOM_STR}.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    export MAS_URL_WORKSPACE="https:\/\/$MAS_WORKSPACE_ID.home.${RANDOM_STR}.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
    cd ../
    ./get-product-versions.sh  #Execute the script to get the versions of various products
    # Create a secret in the Cloud to keep MAS access credentials
    cd $GIT_REPO_HOME
    ./create-secret.sh mas
    RESP_CODE=0
  else
    mark_provisioning_failed $retcode
     if [[ $retcode -eq 2 ]]; then
          log "OCP Creation Successful, Suite Deployment failed"
          log "===== PROVISIONING COMPLETED ====="
          export STATUS=FAILURE
          export STATUS_MSG="OCP Creation Successful,Failed in the Ansible playbook execution"
          export MESSAGE_TEXT="Please import the attached certificate into the browser to access MAS UI."
          export OPENSHIFT_CLUSTER_CONSOLE_URL="https:\/\/console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
          export OPENSHIFT_CLUSTER_API_URL="https:\/\/api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
          export MAS_URL_INIT_SETUP="NA"
          export MAS_URL_ADMIN="NA"
          export MAS_URL_WORKSPACE="NA"
          RESP_CODE=2
        fi
  fi
fi

log " STATUS=$STATUS"
log " STATUS_MSG=$STATUS_MSG"

cd $GIT_REPO_HOME/$CLUSTER_TYPE
if [[ $CLUSTER_TYPE == "aws" ]]; then
  # Complete the template deployment
  cd $GIT_REPO_HOME/$CLUSTER_TYPE
  # Complete the CFT stack creation successfully
  log "Sending completion signal to CloudFormation stack."
   curl -k -X PUT -H 'Content-Type:' --data-binary "{\"Status\":\"SUCCESS\",\"Reason\":\"MAS deployment complete\",\"UniqueId\":\"ID-$CLUSTER_TYPE-$CLUSTER_SIZE-$CLUSTER_NAME\",\"Data\":\"${STATUS}#${STATUS_MSG}#${OPENSHIFT_CLUSTER_CONSOLE_URL}#${OPENSHIFT_CLUSTER_API_URL}#${MAS_URL_INIT_SETUP}#${MAS_URL_ADMIN}#${MAS_URL_WORKSPACE}\"}" "$DEPLOY_WAIT_HANDLE"
fi

# Send email notification
if [[ $EMAIL_NOTIFICATION == "true" ]]; then
  sleep 30
  log "Buyer has explicitly opted for email notification, sending notification"
  ./notify.sh
else
  log "Buyer chose to not send email notification"
fi

# Delete temporary password files
rm -rf /tmp/*password*

cd $GIT_REPO_HOME
# Remove sensitive data from mas-provisioning.log file before uploading it to s3 bucket.
  sed -i -e "/"kubeadmin"/d" mas-provisioning.log
  sed -i -e "/pullSecret:/d" mas-provisioning.log
  sed -i -e "/sshKey:/d" mas-provisioning.log
  sed -i -e "/"Username"/d" mas-provisioning.log
  sed -i -e "/"Password"/d" mas-provisioning.log
# Remove the license file, pull-secret file, & database certificate files
rm -rf db.crt entitlement.lic pull-secret.json
cd $GIT_REPO_HOME/mongo
rm -rf mongo-ca.pem

# Upload log file to object store
if [[ $CLUSTER_TYPE == "aws" ]]; then
  # Upload the log file to s3
  aws s3 cp $GIT_REPO_HOME/mas-provisioning.log $DEPLOYMENT_CONTEXT_UPLOAD_PATH
fi
log "Shutting down VM in a minute"
shutdown -P "+1"
exit $RESP_CODE
