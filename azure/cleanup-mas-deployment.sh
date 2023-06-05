#!/bin/bash
# Script to cleanup the MAS deployment on Azure.
# It will delete the resource group which in turn deletes all the resources from that resource group."
# Hence, make sure you do not have any other resources created in the same resource group.
#
# Parameters:
#   -r RG_NAME: Bootnode resource group name. The cleanup process will find the OpenShift resource group automatically.
#     This is an optional parameter.
#   -u UNIQUE_STR: Unique string using which the OpenShift resource group to be deleted.
#     This is an optional parameter.
#   Both the parameters cannot be passed. Cleanup will happen either using the RG_NAME or UNIQUE_STR. Hence, either of these parameters is required.
#

# Fail the script if any of the steps fail
set -e

RED='\033[0;31m'
BLUE='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

# Functions
usage() {
  echo "Usage: cleanup-mas-deployment.sh -r bootnode-resource-group -u unique-string"
  echo " "
  echo "  - If resource group is present and it has the tag 'clusterUniqueString', you can delete the Azure deployment by resource group name."
  echo "  - If you want to cleanup the resources based on the unique string, then provide the 'unique-string' parameter."
  echo "    In this case, the associated resource group won't be deleted even if it exists. It should be deleted explicitly."
  echo ""
  echo "  Do not specify both 'bootnode-resource-group' and 'unique-string' parameters at the same time."
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -r mas-instance-rg -t IPI(UPI) "
  echo "   cleanup-mas-deployment.sh -u gr5t67 -t IPI(UPI) "
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
  echoRed "No arguments provided with $0. Exiting.."
  usage
else
  while getopts 'r:u:t?h' c; do
    case $c in
    r)
      RG_NAME=$OPTARG
      ;;
    u)
      UNIQUE_STR=$OPTARG
      ;;
    h | *)
      usage
      ;;
    esac
  done
fi
echoBlue "==== Execution started at `date` ===="
echo "Script Inputs:"
echo " Bootnode resource group = $RG_NAME"
echo " Unique string = $UNIQUE_STR"

# Check if bootnode resource group or unique string is provided
if [[ (-z $RG_NAME) && (-z $UNIQUE_STR) ]]; then
  echoRed "ERROR: Both the parameters 'bootnode-resource-group' and 'unique-string' are empty, one of these should have a value"
  usage
fi

# If resource group is provided, do not specify unique string
if [[ (-n $RG_NAME) && (-n $UNIQUE_STR) ]]; then
  echoRed "ERROR: Do not specify both 'bootnode-resource-group' and 'unique-string'. If 'bootnode-resource-group' is specified, do not specify 'unique-string'."
  usage
fi

# Get subscription Id
SUB_ID=$(az account show | jq ".id" | tr -d '"')
echo "SUB_ID: $SUB_ID"

# Check if Subscription ID is retreived, if not, it might be the login issue
if [[ -z $SUB_ID ]]; then
  echoRed "ERROR: Could not retrieve subscription id, make sure you are logged in using 'az login' command."
  exit 1
fi

# Check if bootnode resource group exists
if [[ -n $RG_NAME ]]; then
  set +e
  output=$(az group exists -n $RG_NAME)
  if [[ $output == "false" ]]; then
    echoRed "ERROR: Bootnode resource group $RG_NAME does not exist"
    exit 1
  fi
  set -e
fi

if [[ -n $RG_NAME ]]; then
  # Get the cluster unique string
  UNIQ_STR=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.outputs.clusterUniqueString.value != null).properties.outputs.clusterUniqueString.value" | tr -d '"')
  echo "Deleting by 'bootnode-resource-group' $RG_NAME"
else
  UNIQ_STR=$UNIQUE_STR
  echo "Deleting by 'unique-string' $UNIQ_STR"
fi
echo "UNIQ_STR: $UNIQ_STR"
if [[ ($UNIQ_STR == "null") || (-z $UNIQ_STR) ]]; then
  echo "Could not retrieve the unique string from the resource group. Could not find output param 'clusterUniqueString' in the deployment within the resource group."
  echo "Skipping the deletion of OCP cluster resources, will continue to delete the bootnode resource group"
else
  # Get the OCP cluster resource group name
    OCP_CLUSTER_RG_NAME=$(az group list | jq ".[] | select(.name | contains(\"masocp-$UNIQ_STR\")).name" | tr -d '"')
    vnetname=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.parameters.openShiftClustervnetId.value != null).properties.parameters.openShiftClustervnetId.value" | tr -d '"')
    if [[ -z $vnetname ]]; then
           INSTALL_MODE=IPI
           echo "This is $INSTALL_MODE installation"
    else
         INSTALL_MODE=UPI
        echo "This is $INSTALL_MODE installation"
    fi
   echo "OCP_CLUSTER_RG_NAME: $OCP_CLUSTER_RG_NAME"
    if [[ -n $OCP_CLUSTER_RG_NAME ]]; then
    # Check if OCP cluster resource group exists
         rg=$(az group list | jq ".[] | select(.name | contains(\"$OCP_CLUSTER_RG_NAME\")).name" | tr -d '"')
         if [[ -z $rg ]]; then
           echo "OCP cluster resource group $OCP_CLUSTER_RG_NAME does not exist"
        else
            echo "Deleting resource group $OCP_CLUSTER_RG_NAME ..."
            az group delete -y --name $OCP_CLUSTER_RG_NAME --no-wait
            az group wait --name $OCP_CLUSTER_RG_NAME --deleted
            echo "Deleted resource group $OCP_CLUSTER_RG_NAME"
       fi
    else
      echo "OCP cluster resource group does not seem to exist"
      echo "Skipping the deletion of OCP cluster resource group, will continue to delete the bootnode resource group"
    fi

  # Get domain and domain resource group
  BASE_DOMAIN=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.outputs.clusterUniqueString.value != null).properties.parameters.publicDomain.value" | tr -d '"')
  DOMAINTYPE=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.outputs.clusterUniqueString.value != null).properties.parameters.privateCluster.value" | tr -d '"')
  if [ $DOMAINTYPE == "false" ]; then
  BASE_DOMAIN_RG_NAME=$(az network dns zone list | jq --arg DNS_ZONE $BASE_DOMAIN '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"')
  echo "BASE_DOMAIN=$BASE_DOMAIN"
  echo "BASE_DOMAIN_RG_NAME=$BASE_DOMAIN_RG_NAME"
  if [[ (-n $BASE_DOMAIN) || (-n $BASE_DOMAIN_RG_NAME) ]]; then
    # Delete the DNS zone A records
    A_RECS=$(az network dns record-set a list -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN | jq ".[] | select(.name == \"*.apps.masocp-$UNIQ_STR\").name" | tr -d '"')
    echo "A_RECS = $A_RECS"
    if [[ -n $A_RECS ]]; then
      for inst in $A_RECS; do
        # Delete A record
        az network dns record-set a delete -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN -n $inst --yes
        echo "Deleted record set $inst"
      done
    fi
    # Delete the DNS zone CNAME records
    CNAME_RECS=$(az network dns record-set cname list -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN | jq ".[] | select(.name == \"api.masocp-$UNIQ_STR\").name" | tr -d '"')
    echo "CNAME_RECS = $CNAME_RECS"
    if [[ -n $CNAME_RECS ]]; then
      for inst in $CNAME_RECS; do
        # Delete A record
        az network dns record-set cname delete -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN -n $inst --yes
        echo "Deleted record set $inst"
      done
    fi
  fi
fi
fi


## Delete bootnode resource group
if [[ -n $RG_NAME ]]; then
  echoBlue "Trying to delete bootnode resource group"
  # Delete the role assignments
  ROLEASMNTS=$(az role assignment list --all | jq ".[] | select(.resourceGroup == \"$RG_NAME\").id" | tr -d '"')
  echo "ROLEASMNTS = $ROLEASMNTS"
  if [[ -n $ROLEASMNTS ]]; then
    echo "Found role assignments for this Azure deployment"
    roleasnmnts=""
    for inst in $ROLEASMNTS; do
      # Add to the list
      roleasnmnts="$roleasnmnts $inst"
    done
    echo "Role assignment list: $roleasnmnts"
    az role assignment delete --ids $roleasnmnts
    sleep 10
  else
    echo "No role assignments for this Azure deployment"
  fi
  # Check if bootnode resource group exist
  rg=$(az group list | jq ".[] | select(.name | contains(\"$RG_NAME\")).name" | tr -d '"')
  if [[ -z $rg ]]; then
    echo "Bootnode resource group $RG_NAME does not exist"
  else
    # Delete the resource group of bootnode
    echo "Deleting resource group $RG_NAME ..."
     az group delete -y --name $RG_NAME --no-wait
     az group wait --name $RG_NAME --deleted
    echo "Deleted resource group $RG_NAME"
  fi
else
  echo "No 'bootnode-resource-group' specified, you may need to delete the resource group explicitly if exists, or run the script with -r 'bootnode-resource-group' parameter"
fi

if [[ $INSTALL_MODE == "UPI" ]]; then
       #Get the vnet resource name
       OCP_CLUSTER_RG_NAME=$(az network vnet list | jq --arg VNET_NAME $vnetname '.[] | select(.name==$VNET_NAME).resourceGroup' | tr -d '"')
        #Delete the bootnode subnet created in the existing vnet
        #Get bootnode subnet name
        bootnode_subnet_name=`az network vnet subnet list --resource-group $OCP_CLUSTER_RG_NAME --vnet-name $vnetname|jq '.[] | select(.name).name'|grep bootnode|tr -d '"'`
        #Disassociate the nsg
        az network nsg show -n bootnodeSubnet-nsg -g $OCP_CLUSTER_RG_NAME --query 'subnets[].id' -o tsv|grep $vnetname|xargs -L 1 az network vnet subnet update --network-security-group "" --ids
        #Will not delete if using IPI resources
        #az network nsg delete --resource-group $OCP_CLUSTER_RG_NAME --name bootnodeSubnet-nsg
        #delete the bootnodesubnet
        az network vnet subnet update --resource-group $OCP_CLUSTER_RG_NAME --name $bootnode_subnet_name --vnet-name $vnetname  --remove delegations
        az network vnet subnet delete --name  $bootnode_subnet_name --resource-group $OCP_CLUSTER_RG_NAME --vnet-name $vnetname
        for restype in Microsoft.Network/privateEndpoints Microsoft.Network/networkInterfaces Microsoft.Network/publicIPAddresses  Microsoft.Network/privateDnsZones/virtualNetworkLinks Microsoft.Storage/storageAccounts; do
        resourceId=$(az resource list --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype"| jq  '.[]'|grep -w id|tr -d '"'|tr -d ','|cut -d ":" -f 2)
        echo $resourceId
         if [[ -n $resourceId ]]; then
             az resource delete --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype" --ids $resourceId
        else
             echo " No resources of type $restype found"
        fi
        done
fi
echoBlue "==== Execution completed at `date` ===="
