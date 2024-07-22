#!/bin/bash
set -e

#validating product type for helper.sh
validate_product_type

# This script will initiate the provisioning process of MAS. It will perform following steps,
source ./deploy_util.sh

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
log "deploy.sh AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"

IAM_CREATE
OCP_CREATE

echo "Sleeping for 10mins"
sleep 600
echo "create spectrum fusion cr"  
oc apply -f $GIT_REPO_HOME/aws/ocp-terraform/ocs/ocs-ibm-spectrum-fusion.yaml

echo "Sleeping for 5mins"
sleep 300

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME/../ibm/mas_devops/playbooks
set +e

if [[ $ROSA == "true" ]]; then
    # Use the latest catalog version to support ROSA 4.14.x cluster
    export MAS_DEVOPS_COLLECTION_VERSION=18.17.0
    export MAS_CATALOG_VERSION=v8-240405-amd64
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
  export VPC_ID="${BOOTNODE_VPC_ID}" #existing ocp #new VPCID
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

  log "==== MongoDB deployment completed ===="
  ## Deploy MongoDB completed
fi

if [[ -z $VPC_ID && $AWS_MSK_PROVIDER == "Yes" ]]; then
  log "Failed to get the vpc id required to deploy AWS MSK"
  exit 42
fi
log "==== AWS_MSK_PROVIDER=$AWS_MSK_PROVIDER VPC_ID=$VPC_ID ===="
if [[ $AWS_MSK_PROVIDER == "Yes" ]]; then
  log "==== AWS MSK deployment started ===="
  export KAFKA_CLUSTER_NAME="msk-${RANDOM_STR}"
  export KAFKA_NAMESPACE="msk-${RANDOM_STR}"
  export AWS_KAFKA_USER_NAME="mskuser-${RANDOM_STR}"
  export AWS_REGION="${DEPLOY_REGION}"
  export KAFKA_VERSION="2.8.1"
  export KAFKA_PROVIDER="aws"
  export KAFKA_ACTION="install"
  export AWS_MSK_INSTANCE_TYPE="kafka.m5.large"
  export AWS_MSK_VOLUME_SIZE="100"
  export AWS_MSK_INSTANCE_NUMBER=3

  log "==== Invoke fetch-cidr-block.sh ===="
  source $GIT_REPO_HOME/aws/utils/fetch-cidr-block.sh
  if [ $? -ne 0 ]; then
    SCRIPT_STATUS=44
    exit $SCRIPT_STATUS
  fi
  # IPv4 CIDR of private or default subnet
  export AWS_MSK_CIDR_AZ1="${CIDR_BLOCKS_0}"
  export AWS_MSK_CIDR_AZ2="${CIDR_BLOCKS_1}"
  export AWS_MSK_CIDR_AZ3="${CIDR_BLOCKS_2}"
  export AWS_MSK_INGRESS_CIDR="${VPC_CIDR_BLOCK}"
  export AWS_MSK_EGRESS_CIDR="${VPC_CIDR_BLOCK}"
  log "AWS_MSK_CIDR_AZ1=${AWS_MSK_CIDR_AZ1}  AWS_MSK_CIDR_AZ2=${AWS_MSK_CIDR_AZ2} AWS_MSK_CIDR_AZ3=${AWS_MSK_CIDR_AZ3} VPC_CIDR_BLOCK=$VPC_CIDR_BLOCK"

  export ROLE_NAME=kafka && ansible-playbook ibm.mas_devops.run_role
  log "==== AWS MSK deployment completed ===="
fi
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

## Deploy Manage
if [[ $DEPLOY_MANAGE == "true" && (-z $MAS_JDBC_USER) && (-z $MAS_JDBC_PASSWORD) && (-z $MAS_JDBC_URL) && (-z $MAS_JDBC_CERT_URL) ]]; then
  log "==== Configure internal db2 for manage started ===="
      export ROLE_NAME=db2 && ansible-playbook ibm.mas_devops.run_role
      export ROLE_NAME=suite_db2_setup_for_manage && ansible-playbook ibm.mas_devops.run_role

      #Running setupdb.sh script again such that it creates required tablespaces if it's missed creating it while invoked by ansible role.
      oc exec -n db2u c-db2wh-db01-db2u-0 -- su -lc '/tmp/setupdb.sh | tee /tmp/setupdb2.log' db2inst1
      log "==== Configure internal db2 for manage completed ===="
fi

if [[ $DEPLOY_MANAGE == "true" && (-n $MAS_JDBC_USER) && (-n $MAS_JDBC_PASSWORD) && (-n $MAS_JDBC_URL) ]]; then
  export SSL_ENABLED=false

  #Setting the DB values
	if [[ -n $MANAGE_TABLESPACE ]]; then
	   export MAS_APP_SETTINGS_TABLESPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 1)
	   export MAS_APP_SETTINGS_INDEXSPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 2)
	else
	   if [[ ${MAS_JDBC_URL,, } =~ ^jdbc:db2? ]]; then
			log "Setting to DB2 Values"
			export MAS_APP_SETTINGS_TABLESPACE="maxdata"
			export MAS_APP_SETTINGS_INDEXSPACE="maxindex"
	   elif [[ ${MAS_JDBC_URL,, } =~ ^jdbc:oracle? ]]; then
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
			log " MAS_APP_SETTINGS_DB2_SCHEMA: $MAS_APP_SETTINGS_DB2_SCHEMA"
			log " MAS_APP_SETTINGS_TABLESPACE: $MAS_APP_SETTINGS_TABLESPACE"
			log " MAS_APP_SETTINGS_INDEXSPACE: $MAS_APP_SETTINGS_INDEXSPACE"

  if [ -n "$MAS_JDBC_CERT_URL" ]; then
    log "MAS_JDBC_CERT_URL is not empty, setting SSL_ENABLED as true"
    export SSL_ENABLED=true
  fi
  log "==== Configure JDBC started for external DB2 ==== SSL_ENABLED = $SSL_ENABLED"
  export ROLE_NAME=gencfg_jdbc && ansible-playbook ibm.mas_devops.run_role
  log "==== Configure JDBC completed for external DB2 ===="
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
