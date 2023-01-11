#!/bin/bash
set -e

#validating product type for helper.sh
validate_prouduct_type

# This script will initiate the provisioning process of MAS. It will perform following steps,

## Variables
export AWS_DEFAULT_REGION=$DEPLOY_REGION
MASTER_INSTANCE_TYPE="m5.2xlarge"
WORKER_INSTANCE_TYPE="m5.4xlarge"
# Mongo variables
export MONGODB_STORAGE_CLASS=gp2
# Amqstreams variables
export KAFKA_STORAGE_CLASS=gp2
# IAM variables
IAM_POLICY_NAME="masocp-policy-${RANDOM_STR}"
IAM_USER_NAME="masocp-user-${RANDOM_STR}"
# SLS variables
export SLS_STORAGE_CLASS=gp2
# CP4D variables
export CPD_METADATA_STORAGE_CLASS=gp2
export CPD_SERVICE_STORAGE_CLASS="ocs-storagecluster-cephfs"

# Retrieve SSH public key
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
SSH_PUB_KEY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key)

log "Below are Cloud specific deployment parameters,"
log " AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
log " MASTER_INSTANCE_TYPE: $MASTER_INSTANCE_TYPE"
log " WORKER_INSTANCE_TYPE: $WORKER_INSTANCE_TYPE"
log " MONGODB_STORAGE_CLASS: $MONGODB_STORAGE_CLASS"
log " KAFKA_STORAGE_CLASS: $KAFKA_STORAGE_CLASS"
log " IAM_POLICY_NAME: $IAM_POLICY_NAME"
log " IAM_USER_NAME: $IAM_USER_NAME"
log " SLS_STORAGE_CLASS: $SLS_STORAGE_CLASS"
log " CPD_METADB_BLOCK_STORAGE_CLASS: $CPD_METADB_BLOCK_STORAGE_CLASS"
log " SSH_PUB_KEY: $SSH_PUB_KEY"

## Download files from S3 bucket
# Download SLS certificate
cd $GIT_REPO_HOME
if [[ ${SLS_PUB_CERT_URL,,} =~ ^https? ]]; then
  log "Downloading SLS certificate from HTTP URL"
  wget "$SLS_PUB_CERT_URL" -O sls.crt
elif [[ ${SLS_PUB_CERT_URL,,} =~ ^s3 ]]; then
  log "Downloading SLS certificate from S3 URL"
  aws s3 cp "$SLS_PUB_CERT_URL" sls.crt --region $DEPLOY_REGION
  ret=$?
        if [ $ret -ne 0 ]; then
        aws s3 cp "$SLS_PUB_CERT_URL" sls.crt --region us-east-1
        ret=$?
        if [ $ret -ne 0 ]; then
            log "Invalid SLS License URL"
        fi
        fi
fi
if [[ -f sls.crt ]]; then
  chmod 600 sls.crt
fi
# Download UDS certificate
cd $GIT_REPO_HOME
if [[ ${UDS_PUB_CERT_URL,,} =~ ^https? ]]; then
  log "Downloading UDS certificate from HTTP URL"
  wget "$UDS_PUB_CERT_URL" -O uds.crt
elif [[ ${UDS_PUB_CERT_URL,,} =~ ^s3 ]]; then
  log "Downloading UDS certificate from S3 URL"
  aws s3 cp "$UDS_PUB_CERT_URL" uds.crt --region $DEPLOY_REGION
  ret=$?
        if [ $ret -ne 0 ]; then
        aws s3 cp "$UDS_PUB_CERT_URL" uds.crt --region us-east-1
        ret=$?
        if [ $ret -ne 0 ]; then
            log "Invalid UDS License URL"
        fi
        fi
fi
if [[ -f uds.crt ]]; then
  chmod 600 uds.crt
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

## IAM
# Create IAM policy
cd $GIT_REPO_HOME/aws
policyarn=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://${GIT_REPO_HOME}/aws/iam/policy.json | jq '.Policy.Arn' | tr -d "\"")
# Create IAM user
aws iam create-user --user-name ${IAM_USER_NAME}
aws iam attach-user-policy --user-name ${IAM_USER_NAME} --policy-arn $policyarn
accessdetails=$(aws iam create-access-key --user-name ${IAM_USER_NAME})
export AWS_ACCESS_KEY_ID=$(echo $accessdetails | jq '.AccessKey.AccessKeyId' | tr -d "\"")
export AWS_SECRET_ACCESS_KEY=$(echo $accessdetails | jq '.AccessKey.SecretAccessKey' | tr -d "\"")
log " AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"

# TODO enclose with condition : based on user selection to use letsencrypt starts
# TODO hardcoding need to get it dynamically from user selection from CFT
# Variable for role suite_dns
export DNS_PROVIDER="route53"
export AWS_HOSTED_ZONE_ID="Z06693421T2UIZHSZ9AYY"
export AWS_HOSTED_ZONE="${BASE_DOMAIN}"
# TODO hardcoding, accept email from user?
export AWS_EMAIL="myawsemail@aws.com"
export ROUTE53_ISSUER_NAME="${MAS_INSTANCE_ID}-route53-le-prod"
# Variable for role suite_install
export MAS_CLUSTER_ISSUER="${MAS_INSTANCE_ID}-route53-le-prod"
export MAS_DOMAIN="${MAS_INSTANCE_ID}.${BASE_DOMAIN}"
log " AWS_HOSTED_ZONE_ID: $AWS_HOSTED_ZONE_ID"
log " AWS_EMAIL: $AWS_EMAIL"
log " ROUTE53_ISSUER_NAME: $ROUTE53_ISSUER_NAME"
log " MAS_CLUSTER_ISSUER: $MAS_CLUSTER_ISSUER"
log " MAS_DOMAIN: $MAS_DOMAIN"
#TODO enclose with condition : based on user selection to use letsencrypt ends

# Put some delay for IAM permissions to be applied in the backend
sleep 60

if [[ $OPENSHIFT_USER_PROVIDE == "false" ]]; then
  ## Provisiong OCP cluster
  # Create tfvars file
  cd $GIT_REPO_HOME/aws/ocp-terraform
  rm -rf terraform.tfvars

  if [[ $DEPLOY_REGION == "ap-northeast-1" ]]; then
    AVAILABILITY_ZONE_1="${DEPLOY_REGION}a"
    AVAILABILITY_ZONE_2="${DEPLOY_REGION}c"
    AVAILABILITY_ZONE_3="${DEPLOY_REGION}d"
  elif [[ $DEPLOY_REGION == "ca-central-1" ]]; then
    AVAILABILITY_ZONE_1="${DEPLOY_REGION}a"
    AVAILABILITY_ZONE_2="${DEPLOY_REGION}b"
    AVAILABILITY_ZONE_3="${DEPLOY_REGION}d"
  else
    AVAILABILITY_ZONE_1="${DEPLOY_REGION}a"
    AVAILABILITY_ZONE_2="${DEPLOY_REGION}b"
    AVAILABILITY_ZONE_3="${DEPLOY_REGION}c"
  fi

  cat <<EOT >>terraform.tfvars
cluster_name                    = "$CLUSTER_NAME"
region                          = "$DEPLOY_REGION"
az                              = "$AZ_MODE"
availability_zone1              = "${AVAILABILITY_ZONE_1}"
availability_zone2              = "${AVAILABILITY_ZONE_2}"
availability_zone3              = "${AVAILABILITY_ZONE_3}"
access_key_id                   = "$AWS_ACCESS_KEY_ID"
secret_access_key               = "$AWS_SECRET_ACCESS_KEY"
base_domain                     = "$BASE_DOMAIN"
openshift_pull_secret_file_path = "$OPENSHIFT_PULL_SECRET_FILE_PATH"
public_ssh_key                  = "$SSH_PUB_KEY"
openshift_username              = "$OCP_USERNAME"
openshift_password              = "$OCP_PASSWORD"
cpd_api_key                     = "$CPD_API_KEY"
master_instance_type            = "$MASTER_INSTANCE_TYPE"
worker_instance_type            = "$WORKER_INSTANCE_TYPE"
master_replica_count            = "$MASTER_NODE_COUNT"
worker_replica_count            = "$WORKER_NODE_COUNT"
accept_cpd_license              = "accept"
new_or_existing_vpc_subnet      = "$new_or_existing_vpc_subnet"
enable_permission_quota_check   = "$enable_permission_quota_check"
vpc_id                          = "$EXISTING_NETWORK"
master_subnet1_id               = "$EXISTING_PRIVATE_SUBNET1_ID"
master_subnet2_id               = "$EXISTING_PRIVATE_SUBNET2_ID"
master_subnet3_id               = "$EXISTING_PRIVATE_SUBNET3_ID"
worker_subnet1_id               = "$EXISTING_PUBLIC_SUBNET1_ID"
worker_subnet2_id               = "$EXISTING_PUBLIC_SUBNET2_ID"
worker_subnet3_id               = "$EXISTING_PUBLIC_SUBNET3_ID"
private_cluster                 = "$PRIVATE_CLUSTER"
EOT
  if [[ -f terraform.tfvars ]]; then
    chmod 600 terraform.tfvars
  fi
  log "==== OCP cluster creation started ===="
  # Deploy OCP cluster
  sed -i "s/<REGION>/$DEPLOY_REGION/g" variables.tf
  terraform init -input=false
  terraform plan -input=false -out=tfplan
  set +e
  terraform apply -input=false -auto-approve
  if [[ -f terraform.tfstate ]]; then
    chmod 600 terraform.tfstate
  fi
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "OCP cluster creation failed in Terraform step"
    exit 21
  fi
  set -e
  log "==== OCP cluster creation completed ===="

  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
  log "==== Adding PID limits to worker nodes ===="
  oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml

  ## Create bastion host
  cd $GIT_REPO_HOME/aws
  set +e
  if [[ ($new_or_existing_vpc_subnet == "new") && ($OPENSHIFT_USER_PROVIDE == "false") ]]; then
    ./create-bastion-host.sh
    retcode=$?
    if [[ $retcode -ne 0 ]]; then
      log "Bastion host creation failed in Terraform step"
      exit 22
    fi
  fi

  set -e

  # Backup Terraform configuration
  cd $GIT_REPO_HOME
  rm -rf /tmp/mas-multicloud
  mkdir /tmp/mas-multicloud
  cp -r * /tmp/mas-multicloud
  cd /tmp
  zip -r $BACKUP_FILE_NAME mas-multicloud/*
  set +e
  aws s3 cp $BACKUP_FILE_NAME $DEPLOYMENT_CONTEXT_UPLOAD_PATH --region $DEPLOY_REGION 
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    aws s3 cp $BACKUP_FILE_NAME $DEPLOYMENT_CONTEXT_UPLOAD_PATH --region us-east-1
    retcode=$?
  fi  
  if [[ $retcode -ne 0 ]]; then
    log "Failed while uploading deployment context to S3"
    exit 23
  fi
  set -e
  log "OCP cluster Terraform configuration backed up at $DEPLOYMENT_CONTEXT_UPLOAD_PATH in file $CLUSTER_NAME.zip"

  # Create a secret in the Cloud to keep OCP access credentials
  cd $GIT_REPO_HOME
  ./create-secret.sh ocp
else
  log "==== Existing OCP cluster provided, skipping the cluster creation, Bastion host creation and S3 upload of deployment context ===="
fi

log "==== Adding ER key details to OCP default pull-secret ===="
cd /tmp
# Login to OCP cluster
export OCP_SERVER="$(echo https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443)"
oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=$OCP_SERVER --insecure-skip-tls-verify=true
export OCP_TOKEN="$(oc whoami --show-token)"
oc extract secret/pull-secret -n openshift-config --keys=.dockerconfigjson --to=. --confirm
export encodedEntitlementKey=$(echo cp:$SLS_ENTITLEMENT_KEY | tr -d '\n' | base64 -w0)
export emailAddress=$(cat .dockerconfigjson | jq -r '.auths["cloud.openshift.com"].email')
jq '.auths |= . + {"cp.icr.io": { "auth" : "$encodedEntitlementKey", "email" : "$emailAddress"}}' .dockerconfigjson >/tmp/dockerconfig.json
envsubst </tmp/dockerconfig.json >/tmp/.dockerconfigjson
oc set data secret/pull-secret -n openshift-config --from-file=/tmp/.dockerconfigjson
chmod 600 /tmp/.dockerconfigjson /tmp/dockerconfig.json

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e

export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
if [[ $? -ne 0 ]]; then
  # One reason for this failure is catalog sources not having required state information, so recreate the catalog-operator pod
  # https://bugzilla.redhat.com/show_bug.cgi?id=1807128
  log "Deleting catalog-operator pod"
  podname=$(oc get pods -n openshift-operator-lifecycle-manager | grep catalog-operator | awk {'print $1'})
  oc logs $podname -n openshift-operator-lifecycle-manager
  oc delete pod $podname -n openshift-operator-lifecycle-manager
  sleep 10
  # Retry the step
  export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "Failed while configuring OCP cluster"
    exit 24
  fi
fi
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
if [[ (-z $SLS_URL) || (-z $SLS_REGISTRATION_KEY) || (-z $SLS_PUB_CERT_URL) ]]; then
  # Deploy SLS
  if [[ $PRODUCT_TYPE == "privatepublic" ]]; then
    # Create Products Configmap and CredetialsRequest in sls namespace for Paid Offering.
    log "Configuring sls for paid offering"
    envsubst <"$GIT_REPO_HOME"/aws/products_template.yaml >"$GIT_REPO_HOME"/aws/products.yaml
    envsubst <"$GIT_REPO_HOME"/aws/CredentialsRequest_template.yaml >"$GIT_REPO_HOME"/aws/CredentialsRequest.yaml
    oc new-project "$SLS_NAMESPACE"
    oc create -f "$GIT_REPO_HOME"/aws/products.yaml -n "$SLS_NAMESPACE"
    if [[ $ROSA == "true" ]]; then
      log "Given cluster is of ROSA type, Creating Secret directly"
      # IAM variables
      IAM_POLICY_NAME_ROSA="masocp-policy-rosa-${RANDOM_STR}"
      IAM_USER_NAME_ROSA="masocp-user-rosa-${RANDOM_STR}"
      # Create IAM policy
      policyarn=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME_ROSA} --policy-document file://${GIT_REPO_HOME}/aws/iam/policy-rosa.json | jq '.Policy.Arn' | tr -d "\"")
      # Create IAM user
      aws iam create-user --user-name ${IAM_USER_NAME_ROSA}
      aws iam attach-user-policy --user-name ${IAM_USER_NAME_ROSA} --policy-arn $policyarn
      accessdetails=$(aws iam create-access-key --user-name ${IAM_USER_NAME_ROSA})
      AWS_ACCESS_KEY_ID_ROSA=$(echo $accessdetails | jq '.AccessKey.AccessKeyId' | tr -d "\"")
      AWS_SECRET_ACCESS_KEY_ROSA=$(echo $accessdetails | jq '.AccessKey.SecretAccessKey' | tr -d "\"")
      log " AWS_ACCESS_KEY_ID_ROSA: $AWS_ACCESS_KEY_ID_ROSA"
      # Put some delay for IAM permissions to be applied in the backend
      sleep 60
      oc create secret generic "$SLS_INSTANCE_NAME"-aws-access --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID_ROSA" --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY_ROSA" -n "$SLS_NAMESPACE"
    else
      log "Given cluster is not ROSA, Creating Secret via CredentialRequest"
      oc create -f "$GIT_REPO_HOME"/aws/CredentialsRequest.yaml
    fi
  else
    log "Configuring sls for byol offering"
  fi

  log "==== SLS deployment started ===="
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "==== SLS deployment completed ===="

else
  log "=== Using Existing SLS Deployment ==="
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated SLS Config YAML ==="
fi

## Deploy UDS
if [[ (-z $UDS_API_KEY) || (-z $UDS_ENDPOINT_URL) || (-z $UDS_PUB_CERT_URL) ]]; then
  # Deploy UDS
  log "==== UDS deployment started ===="
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "==== UDS deployment completed ===="

else
  log "=== Using Existing UDS Deployment ==="
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated UDS Config YAML ==="
fi

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
