#Starting the script 
log "==== Install prerequisites ===="
sudo yum install -y jq
python3 -m pip install dotmap
python3 -m pip install yq 
#Exporting all the env vaiables required 
#Download and install openshift-install
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.8.46/openshift-install-linux-4.8.46.tar.gz
tar xzvf openshift-install-linux-4.8.46.tar.gz
mv openshift-install /usr/local/bin/
rm -rf ./openshift-install-linux-4.8.46.tar.gz
#these params can be passed from ARM templates to the script 
log "===== Setting Environment Variables ====="

export azureRegion=${DEPLOY_REGION}
export pullSecret=${OCP_PULL_SECRET}
export sshKey=${SSH_KEY_NAME}
export AZURE_REGION=${DEPLOY_REGION}
export BASE_DOMAIN_RESOURCE_GROUP=${BASE_DOMAIN_RG_NAME}
#Important Parameters 
export RESOURCE_GROUP=${EXISTING_NETWORK_RG}

export vnetName=${EXISTING_NETWORK}
export INFRA_ID=($(echo $vnetName | tr '-' "\n"))

export clientID=${AZURE_SP_CLIENT_ID}
export clientSecret=${AZURE_SP_CLIENT_PWD}
export tenantId=${TENANT_ID}
export SA_NAME="masocp${RANDOM_STR}sa"
#Login to the azure  account
az login --service-principal -u ${clientID} -p ${clientSecret} --tenant ${tenantId}
# az login --identity
if [ $? -ne 0 ]; then
    log "ERROR: Unable to login to Azure account"
    exit 1
fi
export subscriptionId=`az account list | jq -r '.[].id'`
export vnetCIDR=`az network vnet show -g ${RESOURCE_GROUP} -n ${vnetName} --query "addressSpace.addressPrefixes[0]"`
#create Azure service principal json from  template 
log "===== Creation osServicePrincipal.json Started ====="
envsubst < osServicePrincipal-template.json | tee /root/.azure/osServicePrincipal.json
log "===== Creation of osServicePrincipal.json Completed ====="

#create install config from  template 
log "===== Creation of Install-Config.yaml Started ====="
envsubst < install-config-template.yaml | tee install-config.yaml
log "===== Creation of Install-Config.yaml Completed ====="

#Set worker node count to 0 
python3 -c '
import yaml;
path = "install-config.yaml";
data = yaml.full_load(open(path));
data["compute"][0]["replicas"] = 0;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

#create manifest file (This will consume the install-config.yaml file created above )
log "===== Creating manifests files ====="
openshift-install create manifests
if [ $? -ne 0 ]; then
    log "ERROR: Unable to create manifests "
    exit 1
fi
log "===== Manifests files created successfully  ====="

#Removing unwanted files 
rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f openshift/99_openshift-cluster-api_worker-machineset-*.yaml

python3 -c '
import yaml;
path = "manifests/cluster-scheduler-02-config.yml";
data = yaml.full_load(open(path));
data["spec"]["mastersSchedulable"] = False;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

python3 -c '
import yaml;
path = "manifests/cluster-dns-02-config.yml";
data = yaml.full_load(open(path));
del data["spec"]["publicZone"];
del data["spec"]["privateZone"];
open(path, "w").write(yaml.dump(data, default_flow_style=False))'

#Setup manifest files as per the Infra id and Resource group name 
log "===== Setting Resource group and Infra id values in all the manifests file ====="
python3 setup-manifests.py $RESOURCE_GROUP $INFRA_ID

#Create Ignition config files (This step will consume all the manifests files)
log "===== Creating Ignition config files ====="
openshift-install create ignition-configs
if [ $? -ne 0 ]; then
    log "ERROR: Unable to create ignition configs "
    exit 1
fi
log "===== Ignition config files created successfully ====="

#create managed Identity for the 
log "===== Creating managed identity  ====="
az identity create -g $RESOURCE_GROUP -n ${INFRA_ID}-identity
if [ $? -ne 0 ]; then
    log "ERROR: Unable to create Managed identity .. Please check the permissions"
    exit 1
fi
log "===== Managed identity created successfully ====="

#Create storage account and start copying vhd file
log "===== Creating Storage account and starting VHD file copying started  ====="
az storage account create -g $RESOURCE_GROUP --location $AZURE_REGION --name $SA_NAME --kind Storage --sku Standard_LRS
if [ $? -ne 0 ]; then
    log "ERROR: Unable to Storage account"
    exit 1
fi
export ACCOUNT_KEY=`az storage account keys list -g $RESOURCE_GROUP --account-name $SA_NAME --query "[0].value" -o tsv`

az storage container create --name vhd --account-name $SA_NAME
export VHD_URL=$(openshift-install coreos print-stream-json | jq -r '.architectures.x86_64."rhel-coreos-extensions"."azure-disk".url')
az storage blob copy start --account-name $SA_NAME --account-key $ACCOUNT_KEY --destination-blob "rhcos.vhd" --destination-container vhd --source-uri "$VHD_URL"
if [ $? -ne 0 ]; then
    log "ERROR: Unable to start VHD copy operation "
    exit 1
fi
#wait until the VHD file gets copied 
log "===== Wait untill VHD image is copied ====="
status="unknown"
while [ "$status" != "success" ]
do
  status=`az storage blob show --container-name vhd --name "rhcos.vhd" --account-name $SA_NAME --account-key $ACCOUNT_KEY -o tsv --query properties.copy.status`
  sleep 10
  echo $status
done
log "===== VHD image copied successfully ====="

#Upload ignition files to the storage account 
az storage container create --name files --account-name $SA_NAME
az storage blob upload --account-name $SA_NAME --account-key $ACCOUNT_KEY -c "files" -f "bootstrap.ign" -n "bootstrap.ign"

#Create private and public DNS zones 
log "===== Creating Private DNS zone ====="
az network private-dns zone create -g $RESOURCE_GROUP -n ${CLUSTER_NAME}.${BASE_DOMAIN}
if [ $? -ne 0 ]; then
    log "ERROR: Unable to create private dns zone"
    exit 1
fi
log "===== Private DNS zone creation completed  ====="

#Add roles to the managed identity 
log "===== Adding role assignment to Managed Identity  ====="
export PRINCIPAL_ID=`az identity show -g $RESOURCE_GROUP -n ${INFRA_ID}-identity --query principalId --out tsv`
export RESOURCE_GROUP_ID=`az group show -g $RESOURCE_GROUP --query id --out tsv`
az role assignment create --assignee "$PRINCIPAL_ID" --role 'Contributor' --scope "$RESOURCE_GROUP_ID"
if [ $? -ne 0 ]; then
    log "ERROR: Unable to create role assignment on managed identity"
    exit 1
fi
log "===== Role assignment added to Managed Identity  ====="

#Create private dns link with user provided Vnet
log "===== Creating private-link between DNS zone and Vnet  ====="
az network private-dns link vnet create -g $RESOURCE_GROUP -z ${CLUSTER_NAME}.${BASE_DOMAIN} -n ${INFRA_ID}-network-link -v "${INFRA_ID}-vnet" -e false
if [ $? -ne 0 ]; then
    log "ERROR: Failed to create private link between Vnet and DNS zone"
    exit 1
fi
log "===== Private-link between DNS zone and Vnet created successfully  ====="

#Create a storage deployment 
log "===== Creating storage deployment  ====="
export VHD_BLOB_URL=`az storage blob url --account-name $SA_NAME --account-key $ACCOUNT_KEY -c vhd -n "rhcos.vhd" -o tsv`

az deployment group create -g $RESOURCE_GROUP \
  --template-file "02_storage.json" \
  --parameters vhdBlobURL="$VHD_BLOB_URL" \
  --parameters baseName="$INFRA_ID"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to complete storage deployment"
    exit 1
fi
log "===== Storage deployment completed successfully ====="

#Create Loadbalancers
log "===== Creation of Load-balancers started  ====="
az deployment group create -g $RESOURCE_GROUP \
  --template-file "03_infra.json" \
  --parameters privateDNSZoneName="${CLUSTER_NAME}.${BASE_DOMAIN}" \
  --parameters baseName="$INFRA_ID"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to complete load balancer deployment"
    exit 1
fi
log "===== Load-balancers deployment completed successfully  ====="


#Add DNS records    
log "===== Adding DNS records to DNS zone  ====="
export PUBLIC_IP=`az network public-ip list -g $RESOURCE_GROUP --query "[?name=='${INFRA_ID}-master-pip'] | [0].ipAddress" -o tsv`
az network dns record-set a add-record -g $BASE_DOMAIN_RESOURCE_GROUP -z ${BASE_DOMAIN} -n api.${CLUSTER_NAME} -a $PUBLIC_IP --ttl 60
if [ $? -ne 0 ]; then
    log "ERROR: Unable to add dns records to DNS zones"
    exit 1
fi
log "===== DNS records added to DNS zone  ====="

#Create bootstrap node and start bootstraping process 
log "===== Creating bootstrap node and starting bootstrap process  ====="
bootstrap_url_expiry=`date -u -d "10 hours" '+%Y-%m-%dT%H:%MZ'`
export BOOTSTRAP_URL=`az storage blob generate-sas -c 'files' -n 'bootstrap.ign' --https-only --full-uri --permissions r --expiry $bootstrap_url_expiry --account-name $SA_NAME --account-key $ACCOUNT_KEY -o tsv`
export BOOTSTRAP_IGNITION=`jq -rcnM --arg v "3.1.0" --arg url $BOOTSTRAP_URL '{ignition:{version:$v,config:{replace:{source:$url}}}}' | base64 | tr -d '\n'`
az deployment group create -g $RESOURCE_GROUP \
  --template-file "04_bootstrap.json" \
  --parameters bootstrapIgnition="$BOOTSTRAP_IGNITION" \
  --parameters baseName="$INFRA_ID"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to complete bootstrap deployment"
    exit 1
fi
log "===== Bootstrap resources creation completed  ====="

#Deploy master VMs 
log "===== Creating master nodes/vms  ====="
export MASTER_IGNITION=`cat master.ign | base64 | tr -d '\n'`
az deployment group create -g $RESOURCE_GROUP \
  --template-file "05_masters.json" \
  --parameters masterIgnition="$MASTER_IGNITION" \
  --parameters baseName="$INFRA_ID" \
  --parameters numberOfMasters="$MASTER_NODE_COUNT"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to complete master nodes deployment"
    exit 1
fi
log "===== Master nodes/vms created successfully  ====="

#wait for bootstraping to be completed 
log "===== Wait for bootstrap process to be completed  ====="
openshift-install wait-for bootstrap-complete --log-level=debug
if [ $? -ne 0 ]; then
    log "ERROR: Installation failed in bootstrap process"
    exit 1
fi
log "===== Bootstrap process completed  ====="

#Delete the bootstrap resources 
log "===== Remove all bootstrap resources  ====="
az network nsg rule delete -g $RESOURCE_GROUP --nsg-name ${INFRA_ID}-nsg --name bootstrap_ssh_in
az vm stop -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm deallocate -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap --yes
az disk delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap_OSDisk --no-wait --yes
az network nic delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-nic --no-wait
az storage blob delete --account-key $ACCOUNT_KEY --account-name $SA_NAME --container-name files --name bootstrap.ign
az network public-ip delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-ssh-pip
log "===== Removed all bootstrap resources  ====="

#Checking if nodes are visible
log "===== Get all available nodes (Master)  ====="
export KUBECONFIG="$PWD/auth/kubeconfig"
oc get nodes

#Deploy worker Vms 
log "===== Deploy worker ndoes/vms  ====="
export WORKER_IGNITION=`cat worker.ign | base64 | tr -d '\n'`

az deployment group create -g $RESOURCE_GROUP \
  --template-file "06_workers.json" \
  --parameters workerIgnition="$WORKER_IGNITION" \
  --parameters baseName="$INFRA_ID" \
  --parameters numberOfNodes="$WORKER_NODE_COUNT"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to complete worker deployment"
    exit 1
fi
log "===== Worker nodes/vms created successfully  ====="

#Approve all the pending CSR
log "===== Approve all CSR requests which are in Pending state  ====="
sleep 300
for i in `oc get csr --no-headers | grep -i pending |  awk '{ print $1 }'`; do oc adm certificate approve $i; done
sleep 120
for i in `oc get csr --no-headers | grep -i pending |  awk '{ print $1 }'`; do oc adm certificate approve $i; done
log "===== All CSR requests approved  ====="

#Add *apps record in DNS zones 
log "===== Adding DNS records to DNS zone  ====="
export PUBLIC_IP_ROUTER=`oc -n openshift-ingress get service router-default --no-headers | awk '{print $4}'`
az network dns record-set a add-record -g $BASE_DOMAIN_RESOURCE_GROUP -z ${BASE_DOMAIN} -n *.apps.${CLUSTER_NAME} -a $PUBLIC_IP_ROUTER --ttl 300
if [ $? -ne 0 ]; then
    log "ERROR: Unable to add dns records to public DNS zone"
    exit 1
fi
export PUBLIC_IP_ROUTER=`oc -n openshift-ingress get service router-default --no-headers | awk '{print $4}'`
az network private-dns record-set a create -g $RESOURCE_GROUP -z ${CLUSTER_NAME}.${BASE_DOMAIN} -n *.apps --ttl 300
az network private-dns record-set a add-record -g $RESOURCE_GROUP -z ${CLUSTER_NAME}.${BASE_DOMAIN} -n *.apps -a $PUBLIC_IP_ROUTER
if [ $? -ne 0 ]; then
    log "ERROR: Unable to add dns records to private DNS zone"
    exit 1
fi
log "===== DNS records added successfully  ====="

#Wait for cluster creation completion
log "===== Wait for cluster creation completion  ====="
openshift-install wait-for install-complete --log-level=debug
log "===== Cluster creation complted successfully  ====="

log "===== Add new Openshift Username and password  ====="
htpasswd -c -B -b /tmp/.htpasswd $OCP_USERNAME $OCP_PASSWORD
sleep 30
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/.htpasswd -n openshift-config --kubeconfig $PWD/auth/kubeconfig
oc apply -f $PWD/htpasswd.yaml --kubeconfig $PWD/auth/kubeconfig
oc adm policy add-cluster-role-to-user cluster-admin $OCP_USERNAME --kubeconfig $PWD/auth/kubeconfig
oc project kube-system --kubeconfig $PWD/auth/kubeconfig
result=$(oc wait machineconfigpool/worker --for condition=updated --timeout=15m --kubeconfig ./auth/kubeconfig)
echo $result
sleep 10m
oc login https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true

log "==== Openshift Username and Password : $OCP_USERNAME , $OCP_PASSWORD ===="