#!/bin/bash
# Script to cleanup the MAS deployment on Azure.
# It will delete the resource group which in turn deletes all the resources from that resource group."
# Hence, make sure you do not have any other resources created in the same resource group.
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
  echo "  - If resource group is present and it has the tag 'clusterUniqueString', you can delete the MAS instance by resource group name."
  echo "  - If you want to cleanup the resources based on the unique string, then provide the 'unique-string' parameter."
  echo "    In this case, the associated resource group won't be deleted even if it exists. It should be deleted explicitly."
  echo ""
  echo "  Do not specify both 'bootnode-resource-group' and 'unique-string' parameters at the same time."
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -r mas-instance-rg"
  echo "   cleanup-mas-deployment.sh -u gr5t67"
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
  while getopts 'r:u:?h' c; do
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

# Check if this is IPI installation or UPI. The IPI installation will have a VNet named 'ocpfourx-vnet' in bootnode VPC. The UPI instalation 
# does not have it as the existing VNet will be in the different resource group than the bootnode resource group.
ocpvnet=$(az resource list --resource-group $RG_NAME --resource-type Microsoft.Network/virtualNetworks --name "ocpfourx-vnet" | jq '. | length')
if [[ $ocpvnet -eq 1 ]]; then
  INSTALL_MODE=IPI
else
  INSTALL_MODE=UPI
fi
echo "This is $INSTALL_MODE installation"

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
  echo "Could not retrieve the unique string from the resource group. Could not find output param 'clusterUniqueString' in the deployment within resource group."
  echo "Skipping the deletion of OCP cluster resources, will continue to delete the bootnode resource group"
else
  # Get the OCP cluster resource group name
  if [[ $INSTALL_MODE == "IPI" ]]; then
    OCP_CLUSTER_RG_NAME=$(az group list | jq ".[] | select(.name | contains(\"masocp-$UNIQ_STR\")).name" | tr -d '"')
  else
    vnetname=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.parameters.openShiftClustervnetId.value != null).properties.parameters.openShiftClustervnetId.value" | tr -d '"')
    INFRAID=$(echo $vnetname | cut -f 1 -d '-')
    echo "INFRA_ID: $INFRAID"
    OCP_CLUSTER_RG_NAME=$(az network vnet list | jq --arg VNET_NAME $vnetname '.[] | select(.name==$VNET_NAME).resourceGroup' | tr -d '"')
  fi
  echo "OCP_CLUSTER_RG_NAME: $OCP_CLUSTER_RG_NAME"
  if [[ -n $OCP_CLUSTER_RG_NAME ]]; then
    # Check if OCP cluster resource group exists
    rg=$(az group list | jq ".[] | select(.name | contains(\"$OCP_CLUSTER_RG_NAME\")).name" | tr -d '"')
    if [[ -z $rg ]]; then
      echo "OCP cluster resource group $OCP_CLUSTER_RG_NAME does not exist"
    else
      if [[ $INSTALL_MODE == "IPI" ]]; then
        # If IPI installation, delete the OCP cluster resource grup itself
        echo "Deleting resource group $OCP_CLUSTER_RG_NAME ..."
        az group delete --yes --name $OCP_CLUSTER_RG_NAME
        echo "Deleted resource group $OCP_CLUSTER_RG_NAME"
      else
        # If UPI installation, delete only the OCP cluster related resources
        # Find all resources having INFRA_ID in it
        echo "Deleting resource from resource group"
        # Delete resources by INFRA_ID
        for restype in Microsoft.Compute/virtualMachines Microsoft.Compute/disks Microsoft.Network/loadBalancers Microsoft.Network/networkInterfaces Microsoft.ManagedIdentity/userAssignedIdentities Microsoft.Network/publicIPAddresses Microsoft.Compute/images Microsoft.Network/privateDnsZones/virtualNetworkLinks Microsoft.Storage/storageAccounts; do
          unset residtodelete
          echo " Deleting by INFRA_ID, checking resource type $restype"
          for res in $(az resource list --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype" | jq --arg INFRAID $INFRAID '.[] | select(.name | contains($INFRAID)) | .name,.id,":"' | tr -d '"' | tr '\n\r' ',' | tr ':' '\n' | sed 's/^,//g' | sed 's/,$//g'); do
            resname=$(echo $res | cut -f 1 -d ',')
            resid=$(echo $res | cut -f 2 -d ',')
            residtodelete="$residtodelete $resid"
            if [[ ($res == "$INFRAID-vnet" ) || ($res == "$INFRAID-nsg" ) ]]; then
              echo " Existing VNet RG resource $resname skipping deletion"
            else
              echo " Existing VNet RG resource $resname deleting"
            fi
          done
          echo "residtodelete=$residtodelete"
          if [[ -n $residtodelete ]]; then
            az resource delete --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype" --ids $residtodelete > /dev/null
          else
            echo " No resources of type $restype found"
          fi
        done
        # Delete resources by UNIQUE_STR
        for restype in Microsoft.Network/privateDnsZones Microsoft.Storage/storageAccounts; do
          unset residtodelete
          echo " Deleting by UNIQSTR, checking resource type $restype"
          for res in $(az resource list --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype" | jq --arg UNIQSTR $UNIQUE_STR '.[] | select(.name | contains($UNIQSTR)) | .name,.id,":"' | tr -d '"' | tr '\n\r' ',' | tr ':' '\n' | sed 's/^,//g' | sed 's/,$//g'); do
            resname=$(echo $res | cut -f 1 -d ',')
            resid=$(echo $res | cut -f 2 -d ',')
            residtodelete="$residtodelete $resid"
            if [[ ($res == "$INFRAID-vnet" ) || ($res == "$INFRAID-nsg" ) ]]; then
              echo " Existing VNet RG resource $resname skipping deletion"
            else
              echo " Existing VNet RG resource $resname deleting"
            fi
          done
          echo "residtodelete=$residtodelete"
          if [[ -n $residtodelete ]]; then
            az resource delete --resource-group $OCP_CLUSTER_RG_NAME --resource-type "$restype" --ids $residtodelete > /dev/null
          else
            echo " No resources of type $restype found"
          fi
        done
        echo "Deleted OCP cluster related resources"
      fi
    fi
  else
    echo "OCP cluster resource group does not seem to exist"
    echo "Skipping the deletion of OCP cluster resource group, will continue to delete the bootnode resource group"
  fi

  # Get domain and domain resource group
  BASE_DOMAIN=$(az deployment group list --resource-group $RG_NAME | jq ".[] | select(.properties.outputs.clusterUniqueString.value != null).properties.parameters.publicDomain.value" | tr -d '"')
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

## Delete bootnode resource group
if [[ -n $RG_NAME ]]; then
  echoBlue "Trying to delete bootnode resource group"
  # Delete the role assignments
  ROLEASMNTS=$(az role assignment list --all | jq ".[] | select(.resourceGroup == \"$RG_NAME\").id" | tr -d '"')
  echo "ROLEASMNTS = $ROLEASMNTS"
  if [[ -n $ROLEASMNTS ]]; then
    echo "Found role assignments for this MAS instance"
    roleasnmnts=""
    for inst in $ROLEASMNTS; do
      # Add to the list
      roleasnmnts="$roleasnmnts $inst"
    done
    echo "Role assignment list: $roleasnmnts"
    az role assignment delete --ids $roleasnmnts
    sleep 10
  else
    echo "No role assignments for this MAS instance"
  fi
  # Check if bootnode resource group exist
  rg=$(az group list | jq ".[] | select(.name | contains(\"$RG_NAME\")).name" | tr -d '"')
  if [[ -z $rg ]]; then
    echo "Bootnode resource group $RG_NAME does not exist"
  else
    # Delete the resource group of bootnode
    echo "Deleting resource group $RG_NAME ..."
    az group delete --yes --name $RG_NAME
    echo "Deleted resource group $RG_NAME"
  fi
else
  echo "No 'bootnode-resource-group' specified, you may need to delete the resource group explicitly if exists, or run the script with -r 'bootnode-resource-group' parameter"
fi
echoBlue "==== Execution completed at `date` ===="
