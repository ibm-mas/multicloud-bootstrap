#!/bin/bash

# This script should be executed from the machine where az login is already done. It creates all necessary resources and
# finally creates the SAS URL for VHD file to be used in the VM image offer.
#
# This script is for the developers to create the VHD image to be used for VM image offer in the Partner Center.
#
# The script uses pre-created image resource group created by bootnode-image-step-1.sh script. 
#
# Prereqs:
# - Make sure you have executed the bootnode-image-step-1.sh script to create the image resource group 
#   containing Azure compute gallery.
#
# Parameters:
#   SUBID: Azure subscription Id.
#   UNIQSTR: The unique string created by the script bootnode-image-step-1.sh. It can be found in the script output.
#
# Example commands:
# 1. To create a VHD SAS URL for the image gallery created with with unique string 20220817111805,
#    ./bootnode-image-step-2.sh "00000000-2502-4b05-0000-744604c6531d" "20220817111805"

set -e

# Check if you are logged in to Azure
az account show

# Parameters
SUBID=$1
UNIQSTR=$2

echo "Script parameters:"
echo "SUBID=$SUBID"
echo "UNIQSTR=$UNIQSTR"

if [[ (-z $SUBID) || (-z $UNIQSTR) ]]; then
  echo "ERR: Subscription ID and unique string are required parameters"
  exit 1
fi

# Create managed disk from image in image gallery
az disk create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --location eastus2 --name masocp-bootnode-image-${UNIQSTR} --gallery-image-reference /subscriptions/${SUBID}/resourceGroups/masocp-bootnode-image-rg-${UNIQSTR}/providers/Microsoft.Compute/galleries/masbyolimagegallery${UNIQSTR}/images/masocp-image-def-${UNIQSTR}/versions/1.0.0
echo "Managed disk created"

# Generate SAS URL for managed disk
disksasurl=$(az disk grant-access --resource-group masocp-bootnode-image-rg-${UNIQSTR} --name masocp-bootnode-image-${UNIQSTR} --duration-in-seconds 18000 --access-level Read | jq '.accessSas' | tr -d '"')
echo "Read access granted to the disk using SAS URL - $disksasurl"

# Create storage account
az storage account create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --name masstgacnt${UNIQSTR} --location eastus2 --sku Standard_LRS --kind StorageV2 --access-tier Hot
echo "Storage account created"

# Create container in storage account
az storage container create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --account-name masstgacnt${UNIQSTR} --name container
echo "Container created in storage account"

# Create storage writable SAS token
expiry=$(date +%Y-%m-%d --date="2 days")T23:59:59Z
echo "Writable SAS URL expiry $expiry"
sastoken=$(az storage container generate-sas --account-name masstgacnt${UNIQSTR} --https-only --name container --permissions dlrcw --expiry "$expiry" | tr -d '"' | tr -d '\n' | tr -d '\r')
echo "Created storage writable SAS token - $sastoken"
# Copy the managed disk using the SAS URL to the storage account using SAS token
targetsasurl="https://masstgacnt${UNIQSTR}.blob.core.windows.net/container/masocp-bootnode-image-${UNIQSTR}.vhd?${sastoken}"
echo "Target SAS URL - $targetsasurl"
azcopy copy "$disksasurl" "https://masstgacnt${UNIQSTR}.blob.core.windows.net/container/masocp-bootnode-image-${UNIQSTR}.vhd?${sastoken}" --blob-type PageBlob
sleep 5

# Revoke the disks read access
az disk revoke-access --name masocp-bootnode-image-${UNIQSTR} --resource-group masocp-bootnode-image-rg-${UNIQSTR}
echo "Read access revoked from the disk"

# Generate SAS for vhd
expiry=$(date +%Y-%m-%d --date="7 days")T23:59:59Z
echo "VHD SAS URL expiry $expiry"
sastoken=$(az storage container generate-sas --account-name masstgacnt${UNIQSTR} --name container --permissions rl --expiry "$expiry" | tr -d '"' | tr -d '\n' | tr -d '\r')
echo "Created VHD SAS token - $sastoken"
echo "OS VHD link: https://masstgacnt${UNIQSTR}.blob.core.windows.net/container/masocp-bootnode-image-${UNIQSTR}.vhd?$sastoken"
