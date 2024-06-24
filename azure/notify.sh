#!/bin/bash

# This script will send email notification using SMTP details
cd $GIT_REPO_HOME/${CLUSTER_TYPE}
SCRIPT_FILE="notify.py"

if [[ $STATUS == "SUCCESS" ]]; then
  # Login to OCP cluster
  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
  # Collect email details
  certfile="${CLUSTER_NAME}-ca.crt"
  retrieve_mas_ca_cert $RANDOM_STR $certfile
  certcontents=$(cat $certfile | tr '\n' "," | sed "s/,/\\\\\\\n/g")
  certcontents=$(echo $certcontents | sed 's/\//\\\//g')
  log "$certcontents"
  if [[ -z $SLS_URL ]]; then
    get_sls_endpoint_url $RANDOM_STR
    log " CALL_SLS_URL=$CALL_SLS_URL"
  fi
  if [[ -z $DRO_ENDPOINT_URL ]]; then
    get_dro_endpoint_url $RANDOM_STR
    log " CALL_DRO_URL=$CALL_DRO_URL"
  fi
  get_mas_creds $RANDOM_STR
  log " MAS_USER=$MAS_USER"
  #log " MAS_PASSWORD=$MAS_PASSWORD"
else
  certfile="status"
  echo "Deployment failed - $STATUS_MSG" > $certfile
fi

# Process recepient list
if [[ -n $RECEPIENT ]]; then
	for i in $(echo "$RECEPIENT" | tr "," "\n")
	do
	  echo $i
	  if [[ $emaillist == "" ]]; then
		emaillist="'$i'"
	  else
		emaillist="${emaillist},'$i'"
	  fi
	done
fi
echo "Email list = $emaillist"

sed -i "s/\[SMTP-HOST\]/$SMTP_HOST/g" $SCRIPT_FILE
sed -i "s/\[SMTP-PORT\]/$SMTP_PORT/g" $SCRIPT_FILE
sed -i "s/\[SMTP-USERNAME\]/$SMTP_USERNAME/g" $SCRIPT_FILE
sed -i "s/\[SMTP-PASSWORD\]/$SMTP_PASSWORD/g" $SCRIPT_FILE
sed -i "s/\[CERT-FILE\]/$certfile/g" $SCRIPT_FILE
sed -i "s/\[RECEPIENT\]/$emaillist/g" $SCRIPT_FILE
sed -i "s/\[MESSAGE-TEXT\]/$MESSAGE_TEXT/g" $SCRIPT_FILE
sed -i "s/\[STATUS\]/$STATUS/g" $SCRIPT_FILE
sed -i "s/\[STATUS-MESSAGE\]/$STATUS_MSG/g" $SCRIPT_FILE
sed -i "s/\[REGION\]/$DEPLOY_REGION/g" $SCRIPT_FILE
sed -i "s/\[UNIQ-STR\]/$RANDOM_STR/g" $SCRIPT_FILE
sed -i "s/\[OPENSHIFT-CLUSTER-CONSOLE-URL\]/$OPENSHIFT_CLUSTER_CONSOLE_URL/g" $SCRIPT_FILE
sed -i "s/\[OPENSHIFT-CLUSTER-API-URL\]/$OPENSHIFT_CLUSTER_API_URL/g" $SCRIPT_FILE
sed -i "s/\[OCP-USER\]/$OCP_USERNAME/g" $SCRIPT_FILE
sed -i "s/\[MAS-URL-INIT-SETUP\]/$MAS_URL_INIT_SETUP/g" $SCRIPT_FILE
sed -i "s/\[MAS-URL-ADMIN\]/$MAS_URL_ADMIN/g" $SCRIPT_FILE
sed -i "s/\[MAS-URL-WORKSPACE\]/$MAS_URL_WORKSPACE/g" $SCRIPT_FILE
sed -i "s/\[MAS-USER\]/$MAS_USER/g" $SCRIPT_FILE
sed -i "s/\[SLS-ENDPOINT-URL\]/$CALL_SLS_URL/g" $SCRIPT_FILE
sed -i "s/\[OCP-PASSWORD\]/$OCP_PASSWORD/g" $SCRIPT_FILE
sed -i "s/\[MAS-PASSWORD\]/$MAS_PASSWORD/g" $SCRIPT_FILE

chmod +x $SCRIPT_FILE
echo "SCRIPT_FILE=$SCRIPT_FILE"
./$SCRIPT_FILE $STATUS
