#!/bin/bash
# Helper functions
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Retrieve MAS CA certificate
retrieve_mas_ca_cert() {
  uniqstr=$1
  filepath=$2
  # Wait until the secret is available
  found="false"
  counter=0
  while [[ $found == "false" ]] && [[ $counter < 20 ]]; do
    oc get secret ${uniqstr}-cert-public-ca -n ibm-common-services
    if [[ $? -eq 1 ]]; then
      log "OCP secret ${uniqstr}-cert-public-ca not found ($counter), waiting ..."
      sleep 30
      counter=$((counter + 1))
      continue
    else
      log "OCP secret ${uniqstr}-cert-public-ca found"
      found="true"
    fi
    oc get secret ${uniqstr}-cert-public-ca -n ibm-common-services -o yaml | grep ca.crt | cut -d ':' -f 2 | tr -d " ,\"" | base64 -d >$filepath
  done
}

# Get credentials for MAS
get_mas_creds() {
  uniqstr=$1
  # Wait until the secret is available
  found="false"
  counter=0
  while [[ $found == "false" ]] && [[ $counter < 20 ]]; do
    oc get secret ${uniqstr}-credentials-superuser -n mas-${uniqstr}-core
    if [[ $? -eq 1 ]]; then
      log "OCP secret ${uniqstr}-credentials-superuser not found ($counter), waiting ..."
      sleep 30
      counter=$((counter + 1))
      continue
    else
      log "OCP secret ${uniqstr}-credentials-superuser found"
      found="true"
    fi
    sleep 6
    username=$(oc get secret ${uniqstr}-credentials-superuser -n mas-${uniqstr}-core -o json | grep "\"username\"" | cut -d ':' -f 2 | tr -d " ,\"" | base64 -d)
    password=$(oc get secret ${uniqstr}-credentials-superuser -n mas-${uniqstr}-core -o json | grep "\"password\"" | cut -d ':' -f 2 | tr -d " ,\"" | base64 -d)
  done

  if [[ $found == "false" ]]; then
    export MAS_USER=null
    export MAS_PASSWORD=null
    log "MAS username and password not found"
  else
    export MAS_USER=$username
    export MAS_PASSWORD=$password
    log "MAS username and password found"
  fi
}

get_sls_endpoint_url() {
  uniqstr=$1
  export CALL_SLS_URL="https:\/\/$(oc get route ${SLS_INSTANCE_NAME} -n ibm-sls-${uniqstr} | grep "sls" | awk {'print $2'})"
}

get_sls_registration_key() {
  uniqstr=$1

}

get_uds_endpoint_url() {
  uniqstr=$1
  export CALL_UDS_URL="https:\/\/$(oc get route uds-endpoint -n ibm-common-services | grep "uds" | awk {'print $2'})"
}

get_uds_api_key() {
  uniqstr=$1

}

# Mark provisioning failed
mark_provisioning_failed() {
  retcode=$1
  log "Deployment failed"
  log "===== PROVISIONING FAILED ====="
  RESP_CODE=1
  export STATUS=FAILURE
  export STATUS_MSG=NA
  if [[ $retcode -eq 2 ]]; then
    export STATUS_MSG="Failed in the Ansible playbook execution."
  elif [[ $retcode -eq 11 ]]; then
    export STATUS_MSG="This region is not supported for MAS deployment."
  elif [[ $retcode -eq 12 ]]; then
    export STATUS_MSG="The provided ER key is not valid. It does not have access to download the MAS images."
  elif [[ $retcode -eq 13 ]]; then
    export STATUS_MSG="The provided Hosted zone is not a public hosted zone. Please provide a public hosted zone."
  elif [[ $retcode -eq 14 ]]; then
    export STATUS_MSG="The JDBC details for MAS Manage are missing or invalid."
  elif [[ $retcode -eq 15 ]]; then
    export STATUS_MSG="Please provide all the inputs to use existing SLS."
  elif [[ $retcode -eq 16 ]]; then
    export STATUS_MSG="Please provide all the inputs to use existing UDS."
  elif [[ $retcode -eq 17 ]]; then
    export STATUS_MSG="Please provide OCP pull secret."
  elif [[ $retcode -eq 18 ]]; then
    export STATUS_MSG="Please provide a valid MAS license URL."
  elif [[ $retcode -eq 19 ]]; then
    export STATUS_MSG="Please provide all the inputs to use existing OCP."
  elif [[ $retcode -eq 21 || $retcode -eq 1 ]]; then
    export STATUS_MSG="Failure in creating OCP cluster."
  elif [[ $retcode -eq 22 ]]; then
    export STATUS_MSG="Failure in creating Bastion host."
  elif [[ $retcode -eq 23 ]]; then
    export STATUS_MSG="Failed in uploading deployment context to S3."
  elif [[ $retcode -eq 24 ]]; then
    export STATUS_MSG="Failure in configuring OCP cluster."
  elif [[ $retcode -eq 25 ]]; then
    export STATUS_MSG="CNAME or A records already exist."
  elif [[ $retcode -eq 26 ]]; then
    export STATUS_MSG="Missing required parameters when email notification is set to true."
  elif [[ $retcode -eq 27 ]]; then
    export STATUS_MSG="Failure in creating azurefiles storage class."
  elif [[ $retcode -eq 28 ]]; then
    export STATUS_MSG="Missing or Invalid Product Code."
  elif [[ $retcode -eq 29 ]]; then
    export STATUS_MSG="User provided existing OpenShift cluster did not pass the pre-requisites check. The deployment failed due to $2. Please select option to create a new cluster in a new deployment. (Check provisioning logs for more details)"
  elif [[ $retcode -eq 30 ]]; then
    export STATUS_MSG="MAS+CP4D offering is not supported on ROSA cluster. Please select option to create a new cluster in a new deployment or provide a self-managed cluster."
  elif [[ $retcode -eq 31 ]]; then
  export STATUS_MSG="Please provide a valid DB certificate URL.."
  fi
  export MESSAGE_TEXT=NA
  export OPENSHIFT_CLUSTER_CONSOLE_URL=NA
  export OPENSHIFT_CLUSTER_API_URL=NA
  export MAS_URL_INIT_SETUP=NA
  export MAS_URL_ADMIN=NA
  export MAS_URL_WORKSPACE=NA
}

# Split the CLUSTER_NAME and BASE_DOMAIN from provided Openshift API url
split_ocp_api_url() {
  apiurl=$1
  apiurl="${apiurl//\// }"
  COUNTER=0
  BASE_DOMAIN=""
  CLUSTER_NAME=""
  oldIFS="$IFS"
  IFS='.'
  for i in $apiurl; do
    # echo $i
    if [[ $COUNTER -eq 1 ]]; then
      CLUSTER_NAME=$i
    elif [[ $COUNTER -gt 1 ]]; then
      if [[ $COUNTER -eq 2 ]]; then
        BASE_DOMAIN=$i
      else
        BASE_DOMAIN=$BASE_DOMAIN"-"$i
      fi
    fi
    COUNTER=$((COUNTER + 1))
  done
  IFS="$oldIFS"
  # echo $CLUSTER_NAME
  BASE_DOMAIN=${BASE_DOMAIN//-/.}
  ## Remove any possible port number provided by user
  strindex() {
    x="${1%%$2*}"
    [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
  }
  colIndex=$(strindex $BASE_DOMAIN ":")
  if [[ $colIndex -ge 0 ]]; then
    port=${BASE_DOMAIN:$colIndex:6}
    BASE_DOMAIN="${BASE_DOMAIN/$port/}"
  fi

  export CLUSTER_NAME=$CLUSTER_NAME
  export BASE_DOMAIN=$BASE_DOMAIN
}
#creating a function to pre-validate
validate_prouduct_type() {
  product_code_metadata="$(curl http://169.254.169.254/latest/meta-data/product-codes)"
  # Hardcoding product_code_metadata for testing purpose until ami gets created for paid product.
  # product_code_metadata="1905n4jwbijcylk3xm02poizl"
  if [[ -n "$product_code_metadata" ]]; then
    log "Product Code: $product_code_metadata"
    if echo "$product_code_metadata" | grep -Ei '404\s+-\s+Not\s+Found' 1>/dev/null 2>&1; then
      log "MAS product code not found in metadata, skipping custom annotations for Suite CR"
    else
      aws_product_codes_config_file="$GIT_REPO_HOME/aws/aws-product-codes.config"
      log "Checking for product type corrosponding to $product_code_metadata from file $aws_product_codes_config_file"
      if grep -E "^$product_code_metadata:" $aws_product_codes_config_file 1>/dev/null 2>&1; then
        export PRODUCT_TYPE="$(grep -E "^$product_code_metadata:" $aws_product_codes_config_file | cut -f 3 -d ":")"
        export PRODUCT_NAME="$(grep -E "^$product_code_metadata:" $aws_product_codes_config_file | cut -f 4 -d ":")"
        log "PRODUCT_NAME: $PRODUCT_NAME"
        log "PRODUCT_TYPE: $PRODUCT_TYPE"
        if [[ $PRODUCT_TYPE == "byol" ]]; then
          export MAS_ANNOTATIONS="mas.ibm.com/hyperscalerProvider=aws,mas.ibm.com/hyperscalerFormat=byol,mas.ibm.com/hyperscalerChannel=ibm"
        elif [[ $PRODUCT_TYPE == "privatepublic" ]]; then
          export MAS_ANNOTATIONS="mas.ibm.com/hyperscalerProvider=aws,mas.ibm.com/hyperscalerFormat=privatepublic,mas.ibm.com/hyperscalerChannel=aws"
        else
          log "Invalid product type : $PRODUCT_TYPE"
          SCRIPT_STATUS=28
        fi
      else
        log "Product code not found in file $aws_product_codes_config_file"
        SCRIPT_STATUS=28
      fi
    fi
  else
    log "MAS product code not found, skipping custom annotations for Suite CR"
  fi
  log "CLUSTER_TYPE: $CLUSTER_TYPE"
  log "OPERATIONAL_MODE: $OPERATIONAL_MODE"
  log "hyperscaler in MAS_ANNOTATIONS: $MAS_ANNOTATIONS"
  if [[ $CLUSTER_TYPE == "azure" ]]; then
    export MAS_ANNOTATIONS="mas.ibm.com/hyperscalerProvider=azure,mas.ibm.com/hyperscalerChannel=azure"
  fi  
  log "hyperscaler in MAS_ANNOTATIONS: $MAS_ANNOTATIONS"  
  if [[ $OPERATIONAL_MODE == "Non-production"  ]]; then
    if [[ -n "$MAS_ANNOTATIONS" ]]; then
      export MAS_ANNOTATIONS="mas.ibm.com/operationalMode=nonproduction,${MAS_ANNOTATIONS}"
    else
      export MAS_ANNOTATIONS="mas.ibm.com/operationalMode=nonproduction"
    fi
  fi
  log "hyperscaler + operational mode MAS_ANNOTATIONS: $MAS_ANNOTATIONS"
}
