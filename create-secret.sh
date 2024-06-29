#!/bin/bash
#
# This script creates the secret in the appropriate Cloud service based on the Cloud type
# Currently supported Clodro are
#  AWS - Secrets Manager
#  Azure - Key Vault
#

# Read input params
SECRET_TYPE=$1
if [[ -z $SECRET_TYPE ]]; then
  SECRET_TYPE=masocp
fi
log "Secret type to create is $SECRET_TYPE"

cd /tmp
SECRETFILE="masocp-secrets.json"
rm -rf $SECRETFILE

# Create script scoped variables
OPENSHIFT_CLUSTER_CONSOLE_URL_NEW=$(echo $OPENSHIFT_CLUSTER_CONSOLE_URL | tr -d '/')
OPENSHIFT_CLUSTER_API_URL_NEW=$(echo $OPENSHIFT_CLUSTER_API_URL | tr -d '/')
MAS_URL_INIT_SETUP_NEW=$(echo $MAS_URL_INIT_SETUP | tr -d '/')
MAS_URL_ADMIN_NEW=$(echo $MAS_URL_ADMIN | tr -d '/')
MAS_URL_WORKSPACE_NEW=$(echo $MAS_URL_WORKSPACE | tr -d '/')

# Create a secrets file
if [[ $SECRET_TYPE == "masocp" ]]; then
  get_mas_creds $RANDOM_STR
  cat <<EOT >> $SECRETFILE
uniquestring=$RANDOM_STR
ocpclusterurl=$OPENSHIFT_CLUSTER_CONSOLE_URL_NEW
ocpapiurl=$OPENSHIFT_CLUSTER_API_URL_NEW
ocpusername=$OCP_USERNAME
ocppassword=$OCP_PASSWORD
masinitialsetupurl=$MAS_URL_INIT_SETUP_NEW
masadminurl=$MAS_URL_ADMIN_NEW
masworkspaceurl=$MAS_URL_WORKSPACE_NEW
masusername=$MAS_USER
maspassword=$MAS_PASSWORD
EOT
elif [[ $SECRET_TYPE == "ocp" ]]; then
  cat <<EOT >> $SECRETFILE
uniquestring=$RANDOM_STR
ocpclusterurl=$OPENSHIFT_CLUSTER_CONSOLE_URL_NEW
ocpapiurl=$OPENSHIFT_CLUSTER_API_URL_NEW
ocpusername=$OCP_USERNAME
ocppassword=$OCP_PASSWORD
EOT
elif [[ $SECRET_TYPE == "mas" ]]; then
  get_mas_creds $RANDOM_STR
  cat <<EOT >> $SECRETFILE
uniquestring=$RANDOM_STR
masinitialsetupurl=$MAS_URL_INIT_SETUP_NEW
masadminurl=$MAS_URL_ADMIN_NEW
masworkspaceurl=$MAS_URL_WORKSPACE_NEW
masusername=$MAS_USER
maspassword=$MAS_PASSWORD
EOT
else
  log "Unsupported parameter passed"
  exit 1
fi
if [[ $CLUSTER_TYPE == "aws" ]]; then
  aws secretsmanager create-secret --name "maximo-$SECRET_TYPE-secret-$RANDOM_STR" --region $DEPLOY_REGION --secret-string "file://$SECRETFILE"
  log "Secret for $SECRET_TYPE created in AWS Secrets Manager"
elif [[ $CLUSTER_TYPE == "azure" ]]; then
  # Check if key vault already exists
  vaultname=maximo-vault-$RANDOM_STR
  vault=$(az keyvault list --resource-group spedgedep2 | jq --arg vaultname $vaultname '.[] | select(.name == $vaultname).id' | tr -d '"')
  if [[ -z $vault ]]; then
    az keyvault create --no-self-perms --name $vaultname --resource-group "$RG_NAME" --location "$DEPLOY_REGION"
  else
    echo "Vault with name $vaultname already exists"
  fi
  output=$(az keyvault secret set --name maximo-$SECRET_TYPE-secret --vault-name $vaultname --file $SECRETFILE 2>&1)
  if [[ $? -ne 0 ]]; then
    log "Unable to create secret, need to update the Vault's access policy"
    oid=$(echo $output | awk {'split($0,a,";"); print a[2]'} | cut -d '=' -f 2)
    log "OID = $oid"
    az keyvault set-policy --name $vaultname --object-id "$oid" --secret-permissions all --key-permissions all --certificate-permissions all
    sleep 5
    az keyvault secret set --name maximo-$SECRET_TYPE-secret --vault-name $vaultname --file $SECRETFILE 2>&1
  fi
  # az keyvault secret show --name maximo-$SECRET_TYPE-secret --vault-name $vaultname
  log "Secret created in Azure Key Vault"
elif [[ $CLUSTER_TYPE == "gcp" ]]; then
  gcloud secrets create "maximo-$SECRET_TYPE-secret-$RANDOM_STR" --data-file=$SECRETFILE
  log "Secret created in GCP Secret Manager"
fi
# Delete the secrets file
rm -rf $SECRETFILE