#!/bin/bash

# This script should be executed from the machine where az login is already done. It creates a bootnode image in Azure compute gallery.
# Clone the bootstrap automation code respository from Github and run this script.
#
# This script is for the developers to test their changes by creating the new VM image with those changes embedded. It can also be used to
# create the final VM image at the time of release.
#
# This script creates two resource groups.
# 1. VM resource group: This RG contains the VM that is used to capture the image. For example, masocp-bootnode-vm-rg-20220706122203
# 2. Image resource group: This RG contains the Azure Compuet Gallery and the actual VM image. For example, masocp-bootnode-image-rg-20220706122203
# The suffix for the RG names is the timestamp generated by the script and it is same for this pair of resource groups.
# Once the testing is done, it is recommended to delete these resource groups.
# 
# Prereqs:
# - Make sure you have the SSH private key at /tmp/key-santosh-pawar.pem
#
# Parameters:
#  All parameters are positional parameters, so it is must to pass values for each parameter.
#  Either pass the actual value or pass '' to the parameter.
#   SUBID: Azure subscription Id.
#   ANSIBLE_COLLECTION_VERSION: If you want to build the image with specific Ansible collection, provide that value. This is normally
#     used when the Ansible collection version is locked for a specific release.
#   ANSIBLE_COLLECTION_BRANCH: If you want to build the image with Ansible collection locally built from a specific branch of ansible
#     devops repo, provide that value. This is normally used when you are testing the changes in the Ansible code in feature branch.
#     If you have specified value for ANSIBLE_COLLECTION_VERSION, this parameter will be ignored.
#     If you do not specify values for either ANSIBLE_COLLECTION_VERSION or ANSIBLE_COLLECTION_BRANCH, the Ansible collection will be
#     built locally from the master branch of Ansible collection repo, and installed.
#   BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH: If you want to build the image with specific bootstrap automation code tag or branch, provide that value. 
#     Specific branch is normally used when testing the changes from your feature branch.
#     Specific tag is normally used when the bootstrap code is locked for a specific release.
#   SSH_KEY - Pass your private key ssh-key for the region - Paste the private key
#   PUBLIC_SSH_KEY - Pass your public key for the region - Path of the .pem file
# Example commands:
# 1. To create a VM image from Ansible collection '10.0.0' and bootstrap branch 'sp-new-1',
#    ./bootnode-image-step-1.sh "00000000-2502-4b05-0000-744604c6531d" "10.0.0" "" "sp-new-1" "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCnKJvCbAH0YPXzaAGs/y1VGBJ7iK19Xwo5gNrAWxk0WiMueLuVsTMG3VIoE9Dmsg5ZOBjuQb6oOe43cONR2im92/GRnRF7siNgbXVQlgbm3o66c3Tu6zZhH8BF47sfaZuSB+5795f8NuGx3rcsnS5dhL+xpo40s+9bqxo4ni+0YdYNNciOKg5cnIiEnLfL2sPddx80xWmFUMhjO10SWvx00/GeCRiRNKBzWDyOkYxxcbBlK/l2KA0KU7GHlUAmT1YzFd6akOGzc7T9yD/gQ0PshXBgXpMRjr4HILZABZAOIKXi7z7cXsYwLhBOmI6lF7A83zNfNv4uzP936E7Z41wNmfI+1DsNBiHBN2p2DSWoL3xChYlV5OWxiHsUQt6o+8tGKjjLmU3JZBAk6lRf4JpkG7ODoVOPSblUBP7prQ69TACAGR9E7fQNeeKucVTyiek0a35b2vfh3bryVVNdnLTF8+yUu08K7q2kn3pQpr/wDqmlY13FSExqPaCHhDk= generated-by-azure" "path/blr-key.pem"
# 2. To create a VM image from latest Ansible automation code and latest bootstrap code,
#    ./bootnode-image-step-1.sh "00000000-2502-4b05-0000-744604c6531d" "" "" ""

set -e

# Check if you are logged in to Azure
az account show

# Parameters
SUBID=$1
ANSIBLE_COLLECTION_VERSION=$2
ANSIBLE_COLLECTION_BRANCH=$3
BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$4


# Variables
SSH_KEY=$5
echo "Script parameters:"
echo "SUBID=$SUBID"
echo "ANSIBLE_COLLECTION_VERSION=$ANSIBLE_COLLECTION_VERSION"
echo "ANSIBLE_COLLECTION_BRANCH=$ANSIBLE_COLLECTION_BRANCH"
echo "BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH"

if [[ -z $SUBID ]]; then
  echo "ERR: Subscription ID is a required parameter"
  exit 1
fi

# Create the VM image
UNIQSTR=$(date +%Y%m%d%H%M%S)
echo "Unique string: $UNIQSTR"
az group create --name masocp-bootnode-vm-rg-${UNIQSTR} --location eastus2
output=$(az vm create --resource-group masocp-bootnode-vm-rg-${UNIQSTR} --name bootnode-prep --image RedHat:RHEL:82gen2:latest --admin-username azureuser --ssh-key-values "$SSH_KEY" --size Standard_D2s_v3 --public-ip-sku Standard)
echo $output
vmip=$(echo $output | jq '.publicIpAddress' | tr -d '"')
echo "VM IP address: $vmip"

ssh -i $6 -o StrictHostKeyChecking=no azureuser@$vmip "cd /tmp; curl -skSL 'https://raw.githubusercontent.com/ibm-mas/multicloud-bootstrap/mas810-alpha-amka/azure/bootnode-image/prepare-bootnode-image.sh' -o prepare-bootnode-image.sh; chmod +x prepare-bootnode-image.sh; sudo su - root -c \"/tmp/prepare-bootnode-image.sh '$ANSIBLE_COLLECTION_VERSION' '$ANSIBLE_COLLECTION_BRANCH' '$BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH'\""
az vm deallocate --resource-group masocp-bootnode-vm-rg-${UNIQSTR} --name bootnode-prep
az vm generalize --resource-group masocp-bootnode-vm-rg-${UNIQSTR} --name bootnode-prep
az image create --resource-group masocp-bootnode-vm-rg-${UNIQSTR} --name masocp-bootnode-img-${UNIQSTR} --source bootnode-prep --hyper-v-generation V2
az group create --name masocp-bootnode-image-rg-${UNIQSTR} --location eastus2
az sig create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --location eastus2 --gallery-name masbyolimagegallery${UNIQSTR}
az sig image-definition create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --gallery-name masbyolimagegallery${UNIQSTR} --gallery-image-definition masocp-image-def-${UNIQSTR} --os-type Linux --publisher ibm-software --hyper-v-generation V2 --offer ibm-maximo-vm-offer --sku ibm-maximo-vm-offer-byol
az sig image-version create --resource-group masocp-bootnode-image-rg-${UNIQSTR} --location eastus2 --gallery-name masbyolimagegallery${UNIQSTR} --gallery-image-definition masocp-image-def-${UNIQSTR} --gallery-image-version 1.0.0 --target-regions eastus2=1=standard_lrs --managed-image /subscriptions/${SUBID}/resourceGroups/masocp-bootnode-vm-rg-${UNIQSTR}/providers/Microsoft.Compute/images/masocp-bootnode-img-${UNIQSTR}

# Replicate image to all supported regions
az sig image-version update --resource-group masocp-bootnode-image-rg-${UNIQSTR} --gallery-name masbyolimagegallery${UNIQSTR} --gallery-image-definition masocp-image-def-${UNIQSTR} --gallery-image-version 1.0.0 --target-regions eastus eastus2 southcentralus westus2 westus3 australiaeast southeastasia northeurope swedencentral uksouth westeurope centralus southafricanorth centralindia eastasia japaneast koreacentral canadacentral francecentral germanywestcentral norwayeast brazilsouth &
echo " Replicating the images to supported regions in the background, it may take around 30 minutes to complete. Please check the replication status from Azure portal."

# Delete the VM resource group
az group delete -y --name masocp-bootnode-vm-rg-${UNIQSTR} --no-wait
az group wait --name masocp-bootnode-vm-rg-${UNIQSTR} --deleted

echo "========================================="
echo "Bootnode image creation step-1 completed."
echo "VM resource group: masocp-bootnode-vm-rg-${UNIQSTR}"
echo "Image resource group: masocp-bootnode-image-rg-${UNIQSTR}"
echo "Update the Dev ARM template with below values to test the new image:"
echo " \"seller_compute_gallery_name\": \"masbyolimagegallery${UNIQSTR}\""
echo " \"seller_image_definition\": \"masocp-image-def-${UNIQSTR}\""
