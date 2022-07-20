#Starting the script 
log "==== Install prerequisites ===="
sudo yum install -y jq
python3 -m pip install dotmap
python3 -m pip install yq 
#Exporting all the env vaiables required 
#Download and install openshift-install
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.8.11/openshift-install-linux-4.8.11.tar.gz
tar xzvf openshift-install-linux-4.8.11.tar.gz
mv openshift-install /usr/local/bin/
rm -rf ./openshift-install-linux-4.8.11.tar.gz
#these params can be passed from ARM templates to the script 
log "===== Setting Environment Variables ====="

export azureRegion=${DEPLOY_REGION}
export pullSecret=${OCP_PULL_SECRET}
export sshKey=${SSH_KEY_NAME}
export CLUSTER_NAME="masocp-${RANDOM_STR}"
export AZURE_REGION=${DEPLOY_REGION}
export BASE_DOMAIN_RESOURCE_GROUP=${BASE_DOMAIN_RG_NAME}
export BASE_DOMAIN=${BASE_DOMAIN}
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