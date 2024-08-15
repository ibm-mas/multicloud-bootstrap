#!/bin/bash
set -e

#validating product type for helper.sh
validate_product_type

# This script will initiate the provisioning process of MAS. It will perform following steps,

## Variables
export AWS_DEFAULT_REGION=$DEPLOY_REGION
MASTER_INSTANCE_TYPE="m5.2xlarge"
WORKER_INSTANCE_TYPE="m5.4xlarge"
# Mongo variables
export MONGODB_STORAGE_CLASS=gp2
# IAM variables
IAM_POLICY_NAME="masocp-policy-${RANDOM_STR}"
IAM_USER_NAME="masocp-user-${RANDOM_STR}"
# SLS variables
export SLS_STORAGE_CLASS=gp2
# DRO variables
export DRO_STORAGE_CLASS=gp2
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
# Download DRO certificate
cd $GIT_REPO_HOME
if [[ ${DRO_PUB_CERT_URL,,} =~ ^https? ]]; then
  log "Downloading DRO certificate from HTTP URL"
  wget "$DRO_PUB_CERT_URL" -O dro.crt
elif [[ ${DRO_PUB_CERT_URL,,} =~ ^s3 ]]; then
  log "Downloading DRO certificate from S3 URL"
  aws s3 cp "$DRO_PUB_CERT_URL" dro.crt --region $DEPLOY_REGION
  ret=$?
        if [ $ret -ne 0 ]; then
        aws s3 cp "$DRO_PUB_CERT_URL" dro.crt --region us-east-1
        ret=$?
        if [ $ret -ne 0 ]; then
            log "Invalid DRO License URL"
        fi
        fi
fi
if [[ -f dro.crt ]]; then
  chmod 600 dro.crt
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
#log "deploy.sh AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
if [[ -f "/tmp/iam-user-created" ]]; then
  log "deploy.sh /tmp/iam-user-created exists; iam user creation skipped..."
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
  #log " AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
  # on successful user and policy creation, create a file /tmp/iam-user-created
  echo "COMPLETE" > /tmp/iam-user-created
  chmod a+rw /tmp/iam-user-created
  # Put some delay for IAM permissions to be applied in the backend
  sleep 60
fi


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

  # Get the kubeadmin password & write it to secret file on AWS secret manager before deleting it from log file.
  cd $GIT_REPO_HOME
  set +e
  awk '/"kubeadmin"/' mas-provisioning.log > temp.txt
  sed 's/^.*msg=//' temp.txt > temp2.txt
  sed 's/^.*password://' temp2.txt > temp3.txt
  sed 's/^[[:space:]]*//g' temp3.txt > temp4.txt
  sed -i 's/\"//g' temp4.txt

  export KUBEADMIN_PASSWORD=`cat temp4.txt`
  ./create-secret.sh kubeadmin
  rm -rf temp.txt temp2.txt temp3.txt temp4.txt
  set -e

  # Backup deployment context
  rm -rf /tmp/mas-multicloud
  mkdir /tmp/mas-multicloud
  cp -r * /tmp/mas-multicloud

  # Remove sensitive data from mas-provisioning.log file before uploading it to s3 bucket.
  cd /tmp/mas-multicloud
  sed -i -e "/"kubeadmin"/d" mas-provisioning.log
  sed -i -e "/pullSecret:/d" mas-provisioning.log
  sed -i -e "/sshKey:/d" mas-provisioning.log
  sed -i -e "/"Username"/d" mas-provisioning.log
  sed -i -e "/"Password"/d" mas-provisioning.log

  # Remove the license file, pull-secret file, & database certificate files
  rm -rf db.crt entitlement.lic pull-secret.json
  cd /tmp/mas-multicloud/mongo
  rm -rf mongo-ca.pem

  # Create the zip file of deployment context
  cd /tmp
  zip -r $BACKUP_FILE_NAME mas-multicloud/*
  set +e

  # Upload the deployment context zip file to s3 bucket.

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

if [[ $ROSA == "false" ]]; then
echo "Sleeping for 10mins"
sleep 600
echo "create spectrum fusion cr"
LOGFILE=/tmp/ocs-ibm-spectrum-fusion.log
oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/ocs-ibm-spectrum-fusion.yaml &>> $LOGFILE
echo "Sleeping for 5mins"
sleep 300
fi

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e

if [[ $ROSA == "true" ]]; then
    # Below environment variable settings are required to point to EFS storage to make internal DB2 & Manage offering to work on ROSA cluster
    export CLUSTER_NAME=$(echo $EXS_OCP_URL | cut -d '.' -f 2)
	export CPD_PRIMARY_STORAGE_CLASS="efs$CLUSTER_NAME"
	export CPD_METADATA_STORAGE_CLASS="efs$CLUSTER_NAME"
	export CPD_SERVICE_STORAGE_CLASS="efs$CLUSTER_NAME"
	export DB2_META_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
	export DB2_DATA_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
	export DB2_BACKUP_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
	export DB2_LOGS_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
	export DB2_TEMP_STORAGE_CLASS=$CPD_PRIMARY_STORAGE_CLASS
	log " Patch EFS storage class as default storage class"
	oc patch storageclass gp3-csi -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
  	oc patch storageclass gp2 -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
  	oc patch storageclass gp3 -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
  	oc patch storageclass $CPD_PRIMARY_STORAGE_CLASS -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
fi

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

log "==== AWS_VPC_ID = ${AWS_VPC_ID}"
log "==== EXISTING_NETWORK = ${EXISTING_NETWORK}"
log "==== BOOTNODE_VPC_ID = ${BOOTNODE_VPC_ID}"
if [[ -n $AWS_VPC_ID ]]; then
  export VPC_ID="${AWS_VPC_ID}" #ipi
fi
if [[ -n $EXISTING_NETWORK ]]; then
  export VPC_ID="${EXISTING_NETWORK}" #upi
fi
if [[ -z $AWS_VPC_ID && -z $EXISTING_NETWORK  && -n $BOOTNODE_VPC_ID ]]; then
  export VPC_ID="${BOOTNODE_VPC_ID}" #existing ocp
fi
if [[ -z $VPC_ID && $MONGO_FLAVOR == "Amazon DocumentDB" ]]; then
  log "Failed to get the vpc id required to deploy documentdb"
  exit 32
fi
export AWS_REGION=$DEPLOY_REGION

if [[ -n $DBProvisionedVPCId ]]; then
cd $GIT_REPO_HOME
log "==== aws/deploy.sh : Invoke db-create-vpc-peer.sh starts ===="
    log "Existing instance of db @ VPC_ID=$DBProvisionedVPCId"
    export ACCEPTER_VPC_ID=${DBProvisionedVPCId}

    #If VPC ID of existing OCP cluster is inputted then assign REQUESTER_VPC_ID to it.
    if [[ -n $ExocpProvisionedVPCId ]]; then
    export REQUESTER_VPC_ID=${ExocpProvisionedVPCId}
    else
    export REQUESTER_VPC_ID=${VPC_ID}
    fi
    sh $GIT_REPO_HOME/aws/db/db-create-vpc-peer.sh
    log "==== aws/deploy.sh : Invoke db-create-vpc-peer.sh ends ===="
fi

log "==== MONGO_USE_EXISTING_INSTANCE = ${MONGO_USE_EXISTING_INSTANCE}"
if [[ $MONGO_USE_EXISTING_INSTANCE == "true" ]]; then
  if [[ $MONGO_FLAVOR == "Amazon DocumentDB" ]]; then
    export MONGODB_PROVIDER="aws"
    # setting to false, used be sls role
    export SLS_MONGO_RETRYWRITES=false
    log "==== aws/deploy.sh : Invoke docdb-create-vpc-peer.sh starts ===="
    log "Existing instance of Amazon Document DB @ VPC_ID=$DOCUMENTDB_VPC_ID"
    export ACCEPTER_VPC_ID=${DOCUMENTDB_VPC_ID}
    export REQUESTER_VPC_ID=${VPC_ID}

    sh $GIT_REPO_HOME/mongo/docdb/docdb-create-vpc-peer.sh
    log "==== aws/deploy.sh : Invoke docdb-create-vpc-peer.sh ends ===="
  fi
  export MONGODB_ADMIN_USERNAME="${MONGO_ADMIN_USERNAME}"
  export MONGODB_ADMIN_PASSWORD="${MONGO_ADMIN_PASSWORD}"
  export MONGODB_HOSTS="${MONGO_HOSTS}"
  export MONGODB_CA_PEM_LOCAL_FILE=$GIT_REPO_HOME/mongo/mongo-ca.pem
  export MONGODB_RETRY_WRITES=$SLS_MONGO_RETRYWRITES
  log " MONGODB_ADMIN_USERNAME=$MONGODB_ADMIN_USERNAME MONGODB_HOSTS=$MONGODB_HOSTS MONGODB_CA_PEM_LOCAL_FILE=${MONGODB_CA_PEM_LOCAL_FILE} MONGODB_RETRY_WRITES=$MONGODB_RETRY_WRITES"
  log "==== Existing MongoDB gencfg_mongo Started ===="
  export ROLE_NAME=gencfg_mongo && ansible-playbook ibm.mas_devops.run_role
  log "==== Existing MongoDB gencfg_mongo completed ===="
else
  ## Deploy MongoDB started
  log "==== MongoDB deployment started ==== MONGO_FLAVOR=$MONGO_FLAVOR"
  if [[ $MONGO_FLAVOR == "Amazon DocumentDB" ]]; then
    log "Provision new instance of Amazon Document DB @ VPC_ID=$VPC_ID"
    export MONGODB_PROVIDER="aws"
    # setting to false, used be sls role
    export SLS_MONGO_RETRYWRITES=false
    #by default its create (provision) action in mongo role.
    #export MONGODB_ACTION="provision"
    export DOCDB_CLUSTER_NAME="docdb-${RANDOM_STR}"
    export DOCDB_INSTANCE_IDENTIFIER_PREFIX="docdb-${RANDOM_STR}"
    export DOCDB_INSTANCE_NUMBER=3
    log "==== Invoke fetch-cidr-block.sh ===="
    source $GIT_REPO_HOME/aws/utils/fetch-cidr-block.sh
    if [ $? -ne 0 ]; then
      SCRIPT_STATUS=44
      exit $SCRIPT_STATUS
    fi
    # IPv4 CIDR of private or default subnet
    export DOCDB_CIDR_AZ1="${CIDR_BLOCKS_0}"
    export DOCDB_CIDR_AZ2="${CIDR_BLOCKS_1}"
    export DOCDB_CIDR_AZ3="${CIDR_BLOCKS_2}"
    export DOCDB_INGRESS_CIDR="${VPC_CIDR_BLOCK}"
    export DOCDB_EGRESS_CIDR="${VPC_CIDR_BLOCK}"
    log "DOCDB_CIDR_AZ1=${DOCDB_CIDR_AZ1}  DOCDB_CIDR_AZ2=${DOCDB_CIDR_AZ2} DOCDB_CIDR_AZ3=${DOCDB_CIDR_AZ3} VPC_CIDR_BLOCK=$VPC_CIDR_BLOCK"


    SUBNET_1=`aws ec2 describe-subnets --filters \
	  "Name=cidr,Values=$DOCDB_CIDR_AZ1" \
	  "Name=vpc-id,Values=$VPC_ID"  \
    --query "Subnets[*].{SUBNET_ID:SubnetId , TAG_NAME:Tags[?Key=='Name'] | [0].Value }" --output=text`

    SUBNET_ID1=`echo -e "$SUBNET_1" | awk '{print $1}'`
    TAG_NAME1=`echo -e "$SUBNET_1" | awk '{print $2}'`
    log "==== SUBNET_ID1=$SUBNET_ID1 and TAG_NAME1=$TAG_NAME1 ==== "

    SUBNET_2=`aws ec2 describe-subnets --filters \
	  "Name=cidr,Values=$DOCDB_CIDR_AZ2" \
	  "Name=vpc-id,Values=$VPC_ID"  \
    --query "Subnets[*].{SUBNET_ID:SubnetId , TAG_NAME:Tags[?Key=='Name'] | [0].Value }" --output=text`

    SUBNET_ID2=`echo -e "$SUBNET_2" | awk '{print $1}'`
    TAG_NAME2=`echo -e "$SUBNET_2" | awk '{print $2}'`
    log "==== SUBNET_ID2=$SUBNET_ID2 and TAG_NAME2=$TAG_NAME2 ==== "

    SUBNET_3=`aws ec2 describe-subnets --filters \
	  "Name=cidr,Values=$DOCDB_CIDR_AZ3" \
	  "Name=vpc-id,Values=$VPC_ID"  \
    --query "Subnets[*].{SUBNET_ID:SubnetId , TAG_NAME:Tags[?Key=='Name'] | [0].Value }" --output=text`

    SUBNET_ID3=`echo -e "$SUBNET_3" | awk '{print $1}'`
    TAG_NAME3=`echo -e "$SUBNET_3" | awk '{print $2}'`
    log "==== SUBNET_ID3=$SUBNET_ID3 and TAG_NAME3=$TAG_NAME3 ==== "

    if [[ -z "$SUBNET_ID1" ]]; then
      SCRIPT_STATUS=41
      log "Subnet ID associated with CIDR Block 10.0.128.0/20 not found"
      exit $SCRIPT_STATUS
    fi
    if [[ -z "$SUBNET_ID2" ]]; then
      SCRIPT_STATUS=41
      log "Subnet ID associated with CIDR Block 10.0.144.0/20 not found"
      exit $SCRIPT_STATUS
    fi
    if [[ -z "$SUBNET_ID3" ]]; then
      SCRIPT_STATUS=41
      log "Subnet ID associated with CIDR Block 10.0.160.0/20 not found"
      exit $SCRIPT_STATUS
    fi

    #mongo docdb role expects subnet name tag to be in this format docdb-${RANDOM_STR}, required in the create instance flow
    aws ec2 create-tags --resources $SUBNET_ID1  --tags Key=Name,Value=docdb-${RANDOM_STR}
    aws ec2 create-tags --resources $SUBNET_ID2  --tags Key=Name,Value=docdb-${RANDOM_STR}
    aws ec2 create-tags --resources $SUBNET_ID3  --tags Key=Name,Value=docdb-${RANDOM_STR}
    log "==== DocumentDB deployment started ==== @VPC_ID=${VPC_ID} ==== DOCDB_CLUSTER_NAME = ${DOCDB_CLUSTER_NAME}"
  fi
  export ROLE_NAME=mongodb && ansible-playbook ibm.mas_devops.run_role
  if [[ $MONGO_FLAVOR == "Amazon DocumentDB" && $MONGO_USE_EXISTING_INSTANCE == "false" ]]; then
    #Renaming subnet name tag to its original value, required in the create instance flow
    if [[ (-n $SUBNET_ID1) && (-n $SUBNET_ID2) && (-n $SUBNET_ID3) && (-n $TAG_NAME1) && (-n $TAG_NAME2) && (-n $TAG_NAME3) ]]; then
      log "==== Tagging subnet name to its original value ===="
      aws ec2 create-tags --resources $SUBNET_ID1  --tags Key=Name,Value=$TAG_NAME1
      aws ec2 create-tags --resources $SUBNET_ID2  --tags Key=Name,Value=$TAG_NAME2
      aws ec2 create-tags --resources $SUBNET_ID3  --tags Key=Name,Value=$TAG_NAME3
    fi
  fi
  if [[ $MONGO_FLAVOR == "MongoDB" && $MONGO_USE_EXISTING_INSTANCE == "false" ]]; then
         SCRIPT_STATUS=47
          log "New MongoDB cannot be provisioned .."
          exit $SCRIPT_STATUS
  fi
  log "==== MongoDB deployment completed ===="
  ## Deploy MongoDB completed
fi


## Copying the entitlement.lic to MAS_CONFIG_DIR
if [[ -n "$MAS_LICENSE_URL" ]]; then
  cp $GIT_REPO_HOME/entitlement.lic $MAS_CONFIG_DIR
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
      #log " AWS_ACCESS_KEY_ID_ROSA: $AWS_ACCESS_KEY_ID_ROSA"
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
  log "SLS_MONGO_RETRYWRITES=$SLS_MONGO_RETRYWRITES"
  log "==== SLS deployment started ===="
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "==== SLS deployment completed ===="

else
  log " SLS_MONGO_RETRYWRITES=$SLS_MONGO_RETRYWRITES "
  log "=== Using Existing SLS Deployment ==="
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated SLS Config YAML ==="
fi

## Deploy DRO
if [[ (-z $DRO_API_KEY) || (-z $DRO_ENDPOINT_URL) || (-z $DRO_PUB_CERT_URL) ]]; then
  # Deploy DRO
  log "==== DRO deployment started ===="
  export ROLE_NAME=dro && ansible-playbook ibm.mas_devops.run_role
  log "==== DRO deployment completed ===="

else
  log "=== Using Existing DRO Deployment ==="
  export ROLE_NAME=dro && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated DRO Config YAML ==="
fi

## Deploy CP4D
if [[ $DEPLOY_CP4D == "true" ]]; then
  log "==== CP4D deployment started ===="
  export ROLE_NAME=cp4d && ansible-playbook ibm.mas_devops.run_role
  log "==== CP4D deployment completed ===="
fi

## Create MAS Workspace
log "==== MAS Workspace generation started ===="
export ROLE_NAME=gencfg_workspace && ansible-playbook ibm.mas_devops.run_role
log "==== MAS Workspace generation completed ===="


if [[ $DEPLOY_MANAGE == "true" && (-n $MAS_JDBC_USER) && (-n $MAS_JDBC_PASSWORD) && (-n $MAS_JDBC_URL) ]]; then
  export SSL_ENABLED=false

  #Setting the DB values
	if [[ -n $MANAGE_TABLESPACE ]]; then
	   export MAS_APP_SETTINGS_TABLESPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 1)
	   export MAS_APP_SETTINGS_INDEXSPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 2)
	else
	   if [[ ${MAS_JDBC_URL,, } =~ ^jdbc:oracle? ]]; then
			log "Setting to ORACLE Values"
			export MAS_APP_SETTINGS_TABLESPACE="maxdata"
			export MAS_APP_SETTINGS_INDEXSPACE="maxindex"
	   fi
	fi
        if [[ ${MAS_JDBC_URL,, } =~ ^jdbc:sql? ]]; then
		log "Setting to MSSQL Values"
		 export MAS_APP_SETTINGS_DB2_SCHEMA="dbo"
		 export MAS_APP_SETTINGS_TABLESPACE="PRIMARY"
		 export MAS_APP_SETTINGS_INDEXSPACE="PRIMARY"
	fi
	log " MAS_APP_SETTINGS_DB_SCHEMA: $MAS_APP_SETTINGS_DB2_SCHEMA"
	log " MAS_APP_SETTINGS_TABLESPACE: $MAS_APP_SETTINGS_TABLESPACE"
	log " MAS_APP_SETTINGS_INDEXSPACE: $MAS_APP_SETTINGS_INDEXSPACE"

  if [ -n "$MAS_JDBC_CERT_URL" ]; then
    log "MAS_JDBC_CERT_URL is not empty, setting SSL_ENABLED as true"
    export SSL_ENABLED=true
  fi
  log "==== Configure JDBC started for external Oracle ==== SSL_ENABLED = $SSL_ENABLED"
  export ROLE_NAME=gencfg_jdbc && ansible-playbook ibm.mas_devops.run_role
  log "==== Configure JDBC completed for external Oracle ===="
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
  export MAS_APPWS_BINDINGS_JDBC="workspace-application"
  export ROLE_NAME=suite_app_config && ansible-playbook ibm.mas_devops.run_role
  log "==== MAS Manage configure app completed ===="
fi
