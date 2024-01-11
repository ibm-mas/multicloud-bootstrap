#!/bin/bash
# azurefiles-premium storage class created as per : https://github.com/Azure/maximo#azure-files-csi-drivers

#set variables for deployment
export deployRegion=${DEPLOY_REGION}
#export resourceGroupName="$(oc get machineset -n openshift-machine-api -o json | jq -r '.items[0].spec.template.spec.providerSpec.value.resourceGroup')"
export tenantId=${TENANT_ID}
export subscriptionId=${AZURE_SUBSC_ID}
export clientId=${AZURE_SP_CLIENT_ID}
export clientSecret=${AZURE_SP_CLIENT_PWD}
export cluster=${CLUSTER_NAME}
export resourceGroupName=${RG_NAME}
$SUB_ID
#Configure Azure Files Premium

export AZURE_STORAGE_ACCOUNT_NAME=aroazurefilessa
az storage account create --name $AZURE_STORAGE_ACCOUNT_NAME --resource-group $resourceGroupName --kind StorageV2 --sku Standard_LRS
ARO_SERVICE_PRINCIPAL_ID=$(az aro show -g $resourceGroupName -n $cluster --query servicePrincipalProfile.clientId -o tsv)
az role assignment create --role Contributor --scope /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName --assignee $ARO_SERVICE_PRINCIPAL_ID
echo $ARO_SERVICE_PRINCIPAL_ID
az role assignment list --all --assignee $ARO_SERVICE_PRINCIPAL_ID --output json | jq '.[] | {"principalName":.principalName, "roleDefinitionName":.roleDefinitionName, "scope":.scope}'

ARO_API_SERVER=$(az aro list --query "[?contains(name,'$cluster')].[apiserverProfile.url]" -o tsv)
SECRET_NAME=secret-$AZURE_STORAGE_ACCOUNT_NAME

## login to the ARO Cluster
oc login -u kubeadmin -p $(az aro list-credentials -g $resourceGroupName -n $cluster --query=kubeadminPassword -o tsv) $ARO_API_SERVER
## Create a cluster role for the secret reader
oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets
oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder

#Create the azure.json file and upload as secret
envsubst < azure.json | tee azure.json
oc create secret generic azure-cloud-provider --from-literal=cloud-config=$(cat azure.json | base64 | awk '{printf $0}'; echo) -n kube-system

#Grant access
oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:csi-azurefile-node-sa

#Install CSI Driver
oc create configmap azure-cred-file --from-literal=path="/etc/kubernetes/cloud.conf" -n kube-system

export driver_version=v1.12.0
echo "Driver version " $driver_version
./install-driver.sh $driver_version
oc patch storageclass managed-csi -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
#Deploy premium Storage Class
envsubst < azurefiles-premium.yaml | tee azurefiles-premium.yaml
oc apply -f azurefiles-premium.yaml
envsubst < managed-premium.yaml | tee managed-premium.yaml
oc apply -f managed-premium.yaml
oc apply -f persistent-volume-binder.yaml




#ARO Cluster permission
oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets
oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder
