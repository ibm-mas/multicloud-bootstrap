#!/bin/bash

#Create directory for install files
mkdir /tmp/OCPInstall
mkdir /tmp/OCPInstall/QuickCluster
#set variables for deployment
export deployRegion=${DEPLOY_REGION}
export resourceGroupName=`oc get machineset -n openshift-machine-api -o json | jq -r '.items[0].spec.template.spec.providerSpec.value.resourceGroup'`
export tenantId=${AZURE_TENANT_ID}
export subscriptionId=${AZURE_SUBSC_ID}
export clientId=${AZURE_SP_CLIENT_ID}
export clientSecret=${AZURE_SP_CLIENT_PWD}
#Configure Azure Files Premium

#Create the azure.json file and upload as secret
wget -nv https://raw.githubusercontent.com/Azure/maximo/main/src/storageclasses/azure.json -O /tmp/OCPInstall/azure.json
envsubst < /tmp/OCPInstall/azure.json > /tmp/OCPInstall/QuickCluster/azure.json
oc create secret generic azure-cloud-provider --from-literal=cloud-config=$(cat /tmp/OCPInstall/QuickCluster/azure.json | base64 | awk '{printf $0}'; echo) -n kube-system

#Grant access
oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:csi-azurefile-node-sa

#Install CSI Driver
oc create configmap azure-cred-file --from-literal=path="/etc/kubernetes/cloud.conf" -n kube-system

driver_version=v1.12.0
echo "Driver version " $driver_version
curl -skSL https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/$driver_version/deploy/install-driver.sh | bash -s $driver_version --

#Deploy premium Storage Class
wget -nv https://raw.githubusercontent.com/Azure/maximo/main/src/storageclasses/azurefiles-premium.yaml -O /tmp/OCPInstall/azurefiles-premium.yaml
envsubst < /tmp/OCPInstall/azurefiles-premium.yaml > /tmp/OCPInstall/QuickCluster/azurefiles-premium.yaml
oc apply -f /tmp/OCPInstall/QuickCluster/azurefiles-premium.yaml

oc apply -f https://raw.githubusercontent.com/Azure/maximo/main/src/storageclasses/persistent-volume-binder.yaml