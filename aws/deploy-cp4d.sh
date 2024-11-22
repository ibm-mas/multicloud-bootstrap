#!/bin/bash
# Script to deploy CP4D and configure it with the MAS instance

# Fail the script if any of the steps fail
# set -e

RED='\033[0;31m'
BLUE='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

# Functions
usage() {
  echo
  echo "Usage: "
  echo "  $ deploy-cp4d.sh -s stack-name -r region-code -e entitlement-key"
  echo
  echo "Optional:"
  echo "  -u  openshift-user"
  echo "  -p  openshift-password"
  echo
  echo "Provide the parameters 'openshift-user' and 'openshift-password' if the OpenShift user and password has been changed."
  echo
  echo "For example, "
  echo "  $ deploy-cp4d.sh -s mas-cp4d -r us-east-1 -e asdFHJKsdUd....P,ii2SdWOjak -u masocpuser -p masocpuserpass"
  echo
  exit 1
}

echoGreen() {
  echo -e "${GREEN}$1${NC}"
}

echoBlue() {
  echo -e "${BLUE}$1${NC}"
}

echoRed() {
  echo -e "\n${RED}$1${NC}"
}

# Read arguments
if [[ $# -eq 0 ]]; then
  echoRed "No arguments provided with $0. Exiting..."
  usage
else
  while getopts 's:r:e:u:p:?h' c; do
    case $c in
    s)
      STACK_NAME=$OPTARG
      ;;
    r)
      REGION=$OPTARG
      ;;
    e)
      ER_KEY=$OPTARG
      ;;
    u)
      OPENSHIFT_USER=$OPTARG
      ;;
    p)
      OPENSHIFT_PASSWORD=$OPTARG
      ;;
    h | *)
      usage
      ;;
    esac
  done
fi

echoBlue "\n:: Script Inputs ::\n"
echo "  Stack name = $STACK_NAME"
echo "  Region = $REGION"
echo "  Entitlement key = $ER_KEY"
echo "  OpenShift user = $OPENSHIFT_USER"
echo "  OpenShift password = $OPENSHIFT_PASSWORD"
echo -e "\n"

# Check for supported region
if [[ -z $REGION ]]; then
  echoRed "ERROR: Parameter 'region-code' not provided"
  usage
fi
SUPPORTED_REGIONS="us-east-1;us-east-2;us-west-2;ca-central-1;eu-north-1;eu-west-1;eu-west-2;eu-west-3;eu-central-1;ap-northeast-1;ap-northeast-2;ap-northeast-3;ap-south-1;ap-southeast-1;ap-southeast-2;sa-east-1;ap-east-1;ap-southeast-3;eu-south-1;me-south-1;me-central-1;af-south-1"
if [[ ${SUPPORTED_REGIONS,,} =~ $REGION ]]; then
  echoGreen "Supported region is provided.\n"
else
  echoRed "ERROR: Empty or unsupported region provided"
  echo -e "\nSupported regions are $SUPPORTED_REGIONS"
  usage
fi

if [[ (-z $STACK_NAME) ]]; then
  echoRed "ERROR: Parameter 'stack-name' is empty"
  usage
fi

# Creating and exporting MAS_CONFIG_DIR path
export MAS_CONFIG_DIR=/tmp/masconfigdir
[ -d "$MAS_CONFIG_DIR" ] && rmdir $MAS_CONFIG_DIR
mkdir -p $MAS_CONFIG_DIR

if [[ -z $ER_KEY ]]; then
  echoRed "ERROR: Parameter 'entitlement-key' is empty"
  usage
fi

if [[ -n $STACK_NAME ]]; then
  # Get MAS instance unique string
  UNIQ_STR=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null | jq ".Stacks[].Outputs[] | select(.OutputKey == \"ClusterUniqueString\").OutputValue" | tr -d '"')

  # Get OpenShift details from the stack if not provided
  if [[ -z $OPENSHIFT_USER ]]; then
    OC_USER=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null | jq ".Stacks[].Outputs[] | select(.OutputKey == \"OpenShiftUser\").OutputValue" | tr -d '"')
  elif [[ -n OPENSHIFT_USER ]]; then
    OC_USER=$OPENSHIFT_USER
  fi

  if [[ -z $OPENSHIFT_PASSWORD ]]; then
    OC_PASSWORD=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null | jq ".Stacks[].Outputs[] | select(.OutputKey == \"OpenShiftPassword\").OutputValue" | tr -d '"')
  elif [[ -n OPENSHIFT_PASSWORD ]]; then
    OC_PASSWORD=$OPENSHIFT_PASSWORD
  fi

  OC_API=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null | jq ".Stacks[].Outputs[] | select(.OutputKey == \"OpenShiftApiUrl\").OutputValue" | tr -d '"')

fi

echoBlue "\n:: OpenShift Details ::\n"
echo "  OpenShift User        : $OC_USER"
echo "  OpenShift Password    : $OC_PASSWORD"
echo "  OpenShift API URL     : $OC_API"

# Login to OCP cluster
echo -e "\nTrying to log into OpenShift\n"
oc login -u ${OC_USER} -p ${OC_PASSWORD} --server=${OC_API}

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echoRed "OpenShift Login failed. Exiting...\n"
  exit 1;
else
  echoGreen "\nOpenShift Login is successful."
fi

echoBlue "\n==== Execution started at `date` ===="

export MAS_INSTANCE_ID="${UNIQ_STR}"
export MAS_WORKSPACE_ID="wsmasocp"

# CP4D variables
export CPD_ENTITLEMENT_KEY=${ER_KEY}
export CPD_VERSION=cpd40
export MAS_CHANNEL=8.7.x
export CPD_PRIMARY_STORAGE_CLASS="ocs-storagecluster-cephfs"
export CPD_OPERATORS_NAMESPACE="ibm-cpd-operators-${UNIQ_STR}"
export CPD_INSTANCE_NAMESPACE="ibm-cpd-${UNIQ_STR}"
export CPD_SERVICES_NAMESPACE="cpd-services-${UNIQ_STR}"
export CPD_PRODUCT_VERSION=4.5.0

# DB2WH variables
export DB2_META_STORAGE_CLASS=${CPD_PRIMARY_STORAGE_CLASS}
export DB2_DATA_STORAGE_CLASS=${CPD_PRIMARY_STORAGE_CLASS}
export DB2_BACKUP_STORAGE_CLASS=${CPD_PRIMARY_STORAGE_CLASS}
export DB2_LOGS_STORAGE_CLASS=${CPD_PRIMARY_STORAGE_CLASS}
export DB2_TEMP_STORAGE_CLASS=${CPD_PRIMARY_STORAGE_CLASS}
export DB2_INSTANCE_NAME=db2wh-db01
export DB2_VERSION=11.5.7.0-cn2

export ENTITLEMENT_KEY=${ER_KEY}
export HOME=/root


export CPD_METADATA_STORAGE_CLASS=gp2
export CPD_SERVICE_STORAGE_CLASS=ocs-storagecluster-cephfs

echo
echoBlue "==== Installing Ansible Collection ===="
export MAS_DEVOPS_COLLECTION_VERSION=12.3.0
echo -e "\nMAS_DEVOPS_COLLECTION_VERSION : $MAS_DEVOPS_COLLECTION_VERSION\n"
ansible-galaxy collection install ibm.mas_devops:==${MAS_DEVOPS_COLLECTION_VERSION}
echoBlue "==== Installed Ansible Collection Successfully ===="
echo

# Deploy CP4D
echoBlue "====  CP4D deployment started    ===="
echo
export ROLE_NAME=cp4d && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=db2 && ansible-playbook ibm.mas_devops.run_role
echo
echoBlue "====  CP4D deployment completed  ===="
echo

# Configure MAS to use CP4D
echoBlue "==== MAS configuration started   ===="
echo
export ROLE_NAME=suite_config && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_verify && ansible-playbook ibm.mas_devops.run_role
echo
echoBlue "==== MAS configuration completed ===="
echo
echoBlue "==== Execution completed at `date` ====\n"
echo
echo
