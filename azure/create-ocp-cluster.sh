#!/bin/bash

# Export required env variables
export ARM_SUBSCRIPTION_ID=$AZURE_SUBSC_ID
export ARM_CLIENT_ID=$AZURE_SP_CLIENT_ID
export ARM_CLIENT_SECRET=$AZURE_SP_CLIENT_PWD
cd $GIT_REPO_HOME/azure/ocp-terraform/azure_infra
rm -rf terraform.tfvars
# Create tfvars file
cat <<EOT >> terraform.tfvars
azure-client-id="$AZURE_SP_CLIENT_ID"
azure-client-secret="$AZURE_SP_CLIENT_PWD"
azure-subscription-id="$AZURE_SUBSC_ID"
azure-tenant-id="$TENANT_ID"
resource-group          = "$RG_NAME"
existing-resource-group = "yes"
single-or-multi-zone    = "multi"
cluster-name            = "masocp-$RANDOM_STR"
region                  = "$DEPLOY_REGION"
ssh-public-key          = "$SSH_KEY_NAME"
dnszone                 = "$BASE_DOMAIN"
dnszone-resource-group  = "$BASE_DOMAIN_RG_NAME"
pull-secret-file-path   = "$OPENSHIFT_PULL_SECRET_FILE_PATH"
openshift-username      = "$OCP_USERNAME"
openshift-password      = "$OCP_PASSWORD"
master-node-count       = "$MASTER_NODE_COUNT"
worker-node-count       = "$WORKER_NODE_COUNT"
virtual-network-name    = "$EXISTING_NETWORK"
new-or-existing         = "$new_or_existing_vpc_subnet"
existing-vnet-resource-group = "$EXISTING_NETWORK_RG"
private-or-public-cluster = "$private_or_public_cluster"
virtual-network-cidr    = "$virtual_network_cidr"
master-subnet-cidr      =  "$master_subnet_cidr"
worker-subnet-cidr      =  "$worker_subnet_cidr"
bastion_cidr            =  "$bastion_cidr"
EOT
if [[ -f terraform.tfvars ]]; then
    chmod 600 terraform.tfvars
fi
log "==== OCP cluster creation started ===="
terraform init -input=false
terraform plan -input=false -out=tfplan
terraform apply -input=false -auto-approve
if [[ -f terraform.tfstate ]]; then
    chmod 600 terraform.tfstate
fi
retcode=$?
if [[ $retcode -ne 0 ]]; then
    log "OCP cluster creation failed in Terraform step"
    exit 21
fi
log "==== OCP cluster creation completed ===="