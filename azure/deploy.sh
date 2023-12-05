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
# UDS variables
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

#====================
if [[ $CLUSTER_TYPE == "azure" ]]; then
  # Perform az login
  az login --service-principal -u ${AZURE_SP_CLIENT_ID} -p ${AZURE_SP_CLIENT_PWD} --tenant ${TENANT_ID}
  az resource list -n masocp-${RANDOM_STR}-bootnode-vm

  # Get subscription ID
 # export AZURE_SUBSC_ID=`az account list | jq -r '.[].id'`
 export AZURE_SUBSC_ID=`az account list --query "[?id == '$SELLER_SUBSCRIPTION_ID'].{Id:id}" -o tsv`
  log " AZURE_SUBSC_ID: $AZURE_SUBSC_ID"
  # Get Base domain RG name
  DNS_ZONE=$BASE_DOMAIN
  export BASE_DOMAIN_RG_NAME=`az network dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
  log " BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
  # Get VNet RG name for UPI based installation
  if [[ $INSTALLATION_MODE == "UPI" ]]; then
    # Domain name with private dns - only available for UPI
    if [[ $PRIVATE_CLUSTER == "true" ]]; then
        export private_or_public_cluster="private"
        export BASE_DOMAIN_RG_NAME=`az network private-dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
         log " UPI PRIVATE CLUSTER - BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
      else
         export private_or_public_cluster="public"
         export BASE_DOMAIN_RG_NAME=`az network dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
         log " UPI PUBLIC CLUSTER - BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
      fi
       VNET_NAME=$EXISTING_NETWORK
       export EXISTING_NETWORK_RG=`az network vnet list | jq --arg VNET_NAME $VNET_NAME '.[] | select(.name==$VNET_NAME).resourceGroup' | tr -d '"'`
        #Assign the nsg name
      # export nsg_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name  $VNET_NAME|jq '.[0] | select(.name).networkSecurityGroup.id'|awk -F'/' '{print $9}'|tr -d '"'`
        #Assign the network subnet
       export  master_subnet_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME|jq '.[] | select(.name).name'|grep master|tr -d '"'`
       export  worker_subnet_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME|jq '.[] | select(.name).name'|grep worker|tr -d '"'`
       export  virtual_network_cidr=`az network vnet show --resource-group $EXISTING_NETWORK_RG -n $VNET_NAME|jq -r '.addressSpace.addressPrefixes[0]'|tr -d '"'`
       export  master_subnet_cidr=`az network vnet subnet show --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME -n master-subnet|jq  -r '.addressPrefix'`
       export  worker_subnet_cidr=`az network vnet subnet show --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME -n worker-subnet|jq  -r '.addressPrefix'`
       Ip_range=$worker_subnet_cidr
       #10.0.3.224/27
       export bastion_cidr=`echo $Ip_range|cut -d "." -f 1`.`echo $Ip_range|cut -d "." -f 2`.3.224/27
       export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
       export REQUESTER_VPC_ID=$EXISTING_NETWORK
  elif [[ $INSTALLATION_MODE == "IPI" ]]; then
    # Setting the cidr ranges for IPI mode
      export  master_subnet_name="master-subnet"
      export  worker_subnet_name="worker-subnet"
      export  virtual_network_cidr="10.0.0.0/16"
      export  master_subnet_cidr="10.0.1.0/24"
      export  worker_subnet_cidr="10.0.2.0/24"
      export bastion_cidr="10.0.3.224/27"
      export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
      export REQUESTER_VPC_ID=$EXISTING_NETWORK
   elif [[  (-n $ExocpProvisionedVPCId) ]]; then
    #exocp
     log "Existing instance of db @ VPC_ID=$DBProvisionedVPCId"
        export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
        export REQUESTER_VPC_ID=$ExocpProvisionedVPCId
  fi
     log " MASTER SUBNET NAME: $master_subnet_name "
     log " WORKER SUBNET NAME: $worker_subnet_name"
     log " VNET CIDR RANGE: $virtual_network_cidr "
     log " MASTER SUBNET CIDR RANGE: $master_subnet_cidr "
     log " WORKER SUBNET CIDR RANGE : $worker_subnet_cidr"
     log " BASTION  CIDR RANGE : $bastion_cidr"
     log " cluster_network_cidr : $cluster_network_cidr"
        #  log " NSG NAME: $nsg_name"
     log " EXISTING_NETWORK_RG: $EXISTING_NETWORK_RG"
     log " Existing database VNet ID: $ACCEPTER_VPC_ID"
     log " Vnet Id of Cluster: $REQUESTER_VPC_ID"
fi
#====================

# Deploy OCP cluster and bastion host
if [[ $OPENSHIFT_USER_PROVIDE == "false" ]]; then
  cd $GIT_REPO_HOME

  ## Create OCP cluster
    cd $GIT_REPO_HOME/azure
    set +e
    ./create-ocp-cluster.sh
    retcode=$?