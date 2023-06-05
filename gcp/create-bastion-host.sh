#!/bin/bash

# Get the VPC and subnet names created for OCP cluster
ZONE=$(oc get machines -n openshift-machine-api -o jsonpath='{.items[0].spec.providerSpec.value.zone}')
VPC_NAME=$(oc get machines -n openshift-machine-api -o jsonpath='{.items[0].spec.providerSpec.value.networkInterfaces[0].network}')
SUBNET_NAME=$(oc get machines -n openshift-machine-api -o jsonpath='{.items[0].spec.providerSpec.value.networkInterfaces[0].subnetwork}')

log " VPC_NAME=$VPC_NAME"
log " SUBNET_NAME=$SUBNET_NAME"
log " ZONE=$ZONE"

#install terraform 
snap install terraform --classic

cd $GIT_REPO_HOME/gcp/ocp-bastion-host
rm -rf terraform.tfvars
# Create tfvars file
cat <<EOT >> terraform.tfvars
region                          = "$DEPLOY_REGION"
zone                   = "$ZONE"
gcp_project               = "$GOOGLE_PROJECTID"
vpc_name                          = "$VPC_NAME"
subnet_name                       = "$SUBNET_NAME"
bastion_vm_name                      = "masocp-$RANDOM_STR-bastionvm"
bastion_rule_name            = "masocp-$RANDOM_STR-bastion-rule"
EOT
log "==== Bastion host creation started ===="
terraform init -input=false
terraform plan -input=false -out=tfplan
terraform apply -input=false -auto-approve
log "==== Bastion host creation completed ===="