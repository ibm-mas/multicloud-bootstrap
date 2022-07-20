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
