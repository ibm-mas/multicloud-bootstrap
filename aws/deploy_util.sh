IAM_CREATE() {
    if [[ -f "/tmp/iam-user-created" ]]; then
    log "deploy.sh /tmp/iam-user-created exists; iam user creation skipped AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID..."
    else
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
    # on successful user and policy creation, create a file /tmp/iam-user-created
    echo "COMPLETE" > /tmp/iam-user-created
    chmod a+rw /tmp/iam-user-created
    # Put some delay for IAM permissions to be applied in the backend
    sleep 60
    fi
}

OCP_CREATE(){
    
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
worker_instance_volume_type		= "$EBSVolumeType"
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

  if [ -n "$EXISTING_NETWORK" ]; then

# Reading custom cidr ranges for VPC & subnets (both private & public subnets)
log "==== Reading of custom cidr range of VPC & subnets started ===="
export vpc_cidr=$(aws ec2 describe-vpcs  --vpc-ids $EXISTING_NETWORK --query "Vpcs[*].{VPC_CIDR_BLOCK:CidrBlock}" --output=text)

export master_subnet_cidr1=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PRIVATE_SUBNET1_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)
export master_subnet_cidr2=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PRIVATE_SUBNET2_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)
export master_subnet_cidr3=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PRIVATE_SUBNET3_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)

export worker_subnet_cidr1=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PUBLIC_SUBNET1_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)
export worker_subnet_cidr2=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PUBLIC_SUBNET2_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)
export worker_subnet_cidr3=$(aws ec2 describe-subnets --subnet-ids $EXISTING_PUBLIC_SUBNET3_ID --region $DEPLOY_REGION --filter Name=vpc-id,Values=$EXISTING_NETWORK --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text)

cat <<EOT >>terraform.tfvars
vpc_cidr                        = "$vpc_cidr"
master_subnet_cidr1             = "$master_subnet_cidr1"
master_subnet_cidr2             = "$master_subnet_cidr2"
master_subnet_cidr3             = "$master_subnet_cidr3"
worker_subnet_cidr1             = "$worker_subnet_cidr1"
worker_subnet_cidr2             = "$worker_subnet_cidr2"
worker_subnet_cidr3             = "$worker_subnet_cidr3"
EOT

  fi

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

  export AWS_VPC_ID="$(terraform output -raw vpcid)"
  log "AWS_VPC_ID ===> ${AWS_VPC_ID}"

  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
  log "==== Adding PID limits to worker nodes ===="
  oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml
  log "==== Creating storage classes namely, gp2, ocs-storagecluster-ceph-rbd, ocs-storagecluster-cephfs, & openshift-storage.noobaa.io ===="
  oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/gp2.yaml
  oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/ocs-storagecluster-cephfs.yaml
  oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/ocs-storagecluster-ceph-rbd.yaml
  oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/openshift-storage.noobaa.io.yaml
  # Ensure only gp2 is set as default storage class
  oc patch storageclass gp3-csi -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'

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

  # Backup deployment context
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
  log "OCP cluster deployment context backed up at $DEPLOYMENT_CONTEXT_UPLOAD_PATH in file $CLUSTER_NAME.zip"

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

}

