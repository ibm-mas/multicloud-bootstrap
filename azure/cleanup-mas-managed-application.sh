#!/bin/bash
# Script to cleanup the MAS managed application on Azure.
# It will first delete the OCP cluster resource group, then the management resource group, and finally the application resource group 
#
# Parameters:
#   -r RG_NAME: Application resource group name. The cleanup process will find the bootnode resource group and 
#     OpenShift resource group automatically. 
#     This is a mandatory parameter.
#

# Fail the script if any of the steps fail
set -e

RED='\033[0;31m'
BLUE='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

# Functions
usage() {
  echo "Usage: cleanup-mas-deployment.sh -r app-resource-group"
  echo " "
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -r app-myapp-rg"
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
    h | *)
      usage
      ;;
    esac
  done
fi
echoBlue "==== Execution started at `date` ===="
echo "Script Inputs:"
echo " Managed application resource group = $RG_NAME"

# Check if app resource group is provided
if [[ (-z $RG_NAME) ]]; then
  echoRed "ERROR: Parameter 'app-resource-group' is empty" 
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

# Get bootnode resource group
brg=$(az managedapp list --resource-group $RG_NAME | jq '.[].managedResourceGroupId' | tr -d '"' | awk {'split($0,a,"resourceGroups"); print a[2]'} | tr -d '/')
echo "brg=$brg"
if [[ -n $brg ]]; then
  ./cleanup-mas-deployment.sh -r $brg
  
  # Delete the managed application
  mappname=$(az managedapp list --resource-group $RG_NAME | jq ".[].name" | tr -d '"')
  echo "Managed application name: $mappname"
  if [[ -n $mappname ]]; then
    az managedapp delete --name $mappname --resource-group $RG_NAME --subscription $SUB_ID
    echo "Deleted managed application $mappname"
  fi
fi

# Delete the managed application group
rg=$(az group list | jq ".[] | select(.name | contains(\"$RG_NAME\")).name" | tr -d '"')
if [[ -z $rg ]]; then
    echo "Managed application group $RG_NAME does not exist"
  else
    echo "Deleting managed application resource group $RG_NAME ..."
    az group delete --yes --name $RG_NAME
    echo "Deleted managed application resource group $RG_NAME"
fi

echoBlue "==== Execution completed at `date` ===="
