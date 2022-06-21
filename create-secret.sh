#!/bin/bash
#
# This script creates the secret in the appropriate Cloud service based on the Cloud type
# Currently supported Clouds are
#  AWS - Secrets Manager
#  Azure - Key Vault
#

cd /tmp
# Create a secrets file
SECRETFILE="masocp-secrets.json"
rm -rf $SECRETFILE
get_mas_creds $RANDOM_STR
cat <<EOT >> $SECRETFILE
{
  "ocpusername": "$OCP_USERNAME",
  "ocppassword": "$OCP_PASSWORD",
  "masusername" "$MAS_USER",
  "maspassword" "$MAS_PASSWORD"
}
EOT
if [[ $CLUSTER_TYPE == "aws" ]]; then
  aws secretsmanager create-secret --name "masocp-secret-$RANDOM_STR" --secret-string "file://$SECRETFILE"
  log "Secret created in AWS Secret Manager"
elif [[ $CLUSTER_TYPE == "azure" ]]; then
  az keyvault create --enable-rbac-authorization --no-self-perms --name "masocp-secret-$RANDOM_STR" --resource-group "$RG_NAME" --location "$DEPLOY_REGION"
  az keyvault secret set --name ocp-secret --vault-name "masocp-secret-$RANDOM_STR" --file $SECRETFILE
  # az keyvault secret show --name ocp-secret --vault-name "masocp-secret-$RANDOM_STR"
  log "Secret created in Azure Key Vault"
fi
# Delete the secrets file
rm -rf $SECRETFILE