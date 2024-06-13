#!/bin/bash
# azurefiles-premium storage class created as per : https://github.com/Azure/maximo#azure-files-csi-drivers

#set variables for deployment
export deployRegion=${DEPLOY_REGION}
export resourceGroupName="$(oc get machineset -n openshift-machine-api -o json|jq -r '.items[0].spec.template.spec.providerSpec.value.networkResourceGroup')"
export tenantId=${TENANT_ID}
export subscriptionId=${AZURE_SUBSC_ID}
export clientId=${AZURE_SP_CLIENT_ID}
export clientSecret=${AZURE_SP_CLIENT_PWD}
echo  $deployRegion $resourceGroupName $tenantId $subscriptionId $clientId $clientSecret
# get the Cluster name
export CLUSTER_NAME=$(az resource list --name  $resourceGroupName --query "[].{id:id}"|grep OpenShiftClusters|cut -d "/" -f 9|tr -d '"')
echo "CLUSTER_NAME" $CLUSTER_NAME
log "CLUSTER_NAME" $CLUSTER_NAME
export AZURE_STORAGE_ACCOUNT_NAME=stg${resourceGroupName,,}
export AZURE_STORAGE_BLOCK_ACCOUNT_NAME=stgblk${resourceGroupName,,}
echo "AZURE_STORAGE_ACCOUNT_NAME" $AZURE_STORAGE_ACCOUNT_NAME
export AZURE_FILES_RESOURCE_GROUP=$resourceGroupName
echo "AZURE_FILES_RESOURCE_GROUP" $AZURE_FILES_RESOURCE_GROUP

echo "Register the providers .."
az account set --subscription  $subscriptionId
az provider register -n Microsoft.RedHatOpenShift --wait
az provider register -n Microsoft.Compute --wait
az provider register -n Microsoft.Storage --wait
az provider register -n Microsoft.Authorization --wait
export checkstoragename=$(az storage account check-name --name $AZURE_STORAGE_ACCOUNT_NAME --query nameAvailable)
echo "Check if the storage name is available : $checkstoragename"
log "Check if the storage name is available : $checkstoragename"
#zcheck if the storage name exists
if [[ $checkstoragename == "true" ]]; then
   echo "no storage class"
    #create a storage
    az storage account create \
      --name $AZURE_STORAGE_ACCOUNT_NAME \
      --resource-group $AZURE_FILES_RESOURCE_GROUP \
      --kind FileStorage \
      --sku Premium_LRS \
      --allow-shared-key-access true \
      --min-tls-version TLS1_2 \
      --location $deployRegion \
      --allow-blob-public-access false \
      --https-only false \
      --bypass AzureServices \
      --default-action Deny
fi
ARO_SERVICE_PRINCIPAL_ID=$(az aro show -g $AZURE_FILES_RESOURCE_GROUP -n $CLUSTER_NAME --query servicePrincipalProfile.clientId -o tsv)
ARO_API_SERVER=$(az aro list --query "[?contains(name,'$CLUSTER_NAME')].[apiserverProfile.url]" -o tsv)
echo "ARO_API_SERVER"  $ARO_API_SERVER
log "ARO_API_SERVER"  $ARO_API_SERVER
SECRET_NAME=secret-$AZURE_STORAGE_ACCOUNT_NAME

# Assign contributor role to the ARO SP on SA resource group
az role assignment create --role Contributor --scope /subscriptions/$subscriptionId/resourceGroups/$AZURE_FILES_RESOURCE_GROUP --assignee $ARO_SERVICE_PRINCIPAL_ID

## login to the ARO Cluster
oc login -u kubeadmin -p $(az aro list-credentials -g $AZURE_FILES_RESOURCE_GROUP -n $CLUSTER_NAME --query=kubeadminPassword -o tsv) $ARO_API_SERVER
## Create a cluster role for the secret reader
oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets
oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder

#Assign networks to the storage #https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security?tabs=azure-cli

az storage account update --resource-group $AZURE_FILES_RESOURCE_GROUP --name  $AZURE_STORAGE_ACCOUNT_NAME --default-action Deny
export VNET=$(oc get machineset -n openshift-machine-api -o json|jq -r '.items[0].spec.template.spec.providerSpec.value.vnet')
#export subnets=$(az network vnet subnet list -g  $AZURE_FILES_RESOURCE_GROUP --vnet-name $VNET|jq -r '.[].name')

export subnets=(worker-subnet master-subnet)
for subnet in "${subnets[@]}"
  do
  echo "{subnet}"
  az network vnet subnet update --resource-group  $AZURE_FILES_RESOURCE_GROUP --vnet-name $VNET --name $subnet --service-endpoints "Microsoft.Storage.Global"
  subnetid=$(az network vnet subnet show --resource-group $AZURE_FILES_RESOURCE_GROUP --vnet-name $VNET --name $subnet --query id --output tsv)
done
#delete the azurepremium and create a new premium
log "Delete the azurepremium and create a new azurepremium for ARO"
oc delete sc/azurefiles-premium

#Deploy premium Storage Class for aro
cat << EOF >> azure-storageclass-azure-file.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azurefiles-premium
provisioner: file.csi.azure.com
parameters:
  location: $deployRegion
  resourceGroup: $AZURE_FILES_RESOURCE_GROUP
  secretNamespace: kube-system
  skuName: Premium_LRS
  storageAccount: $AZURE_STORAGE_ACCOUNT_NAME
reclaimPolicy: Delete
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
  - noperm
volumeBindingMode: Immediate
EOF
oc create -f azure-storageclass-azure-file.yaml