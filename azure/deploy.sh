#!/bin/bash
set -e

# This script will initiate the provisioning process of MAS. It will perform following steps,

## Variables
# Mongo variables
export MONGODB_STORAGE_CLASS=managed-premium
# Amqstreams variables
export KAFKA_STORAGE_CLASS=managed-premium
# Service principle variables
SP_NAME="http://${CLUSTER_NAME}-sp"
# SLS variables
export SLS_STORAGE_CLASS=managed-premium
# UDS variables
export UDS_STORAGE_CLASS=managed-premium
# CP4D variables
export CPD_METADATA_STORAGE_CLASS=managed-premium
export CPD_SERVICE_STORAGE_CLASS=azurefiles-premium

log "Below are Cloud specific deployment parameters,"
log " MONGODB_STORAGE_CLASS: $MONGODB_STORAGE_CLASS"
log " KAFKA_STORAGE_CLASS: $KAFKA_STORAGE_CLASS"
log " SP_NAME: $SP_NAME"
log " SLS_STORAGE_CLASS: $SLS_STORAGE_CLASS"
log " UDS_STORAGE_CLASS: $UDS_STORAGE_CLASS"
log " SSH_PUB_KEY: $SSH_PUB_KEY"
## Download files from S3 bucket
# Download MAS license
log "==== Downloading MAS license ===="
cd $GIT_REPO_HOME
if [[ ! -z ${MAS_LICENSE_URL} ]]; then
  azcopy copy "${MAS_LICENSE_URL}" "entitlement.lic"
  chmod 600 entitlement.lic
fi

# Download SLS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${SLS_PUB_CERT_URL} ]]; then
  azcopy copy "${SLS_PUB_CERT_URL}" "sls.crt"
  chmod 600 sls.crt
fi
# Download BAS certificate
cd $GIT_REPO_HOME
if [[ ! -z ${UDS_PUB_CERT_URL} ]]; then
  azcopy copy "${UDS_PUB_CERT_URL}" "uds.crt"
  chmod 600 uds.crt
fi

## Read License File & Retrive SLS hostname and host id
line=$(head -n 1 entitlement.lic)
set -- $line
hostid=$3
log " SLS_HOST_ID: $hostid"
# SLS Instance name
export SLS_LICENSE_ID="$hostid"
log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
log " SLS_LICENSE_ID=$SLS_LICENSE_ID"

#====================
if [[ $CLUSTER_TYPE == "azure" ]]; then
  # Perform az login
  az login --service-principal -u ${AZURE_SP_CLIENT_ID} -p ${AZURE_SP_CLIENT_PWD} --tenant ${TENANT_ID}
  az resource list -n masocp-${RANDOM_STR}-bootnode-vm

  # Get subscription ID
 # export AZURE_SUBSC_ID=`az account list | jq -r '.[].id'`
 export AZURE_SUBSC_ID=`az account list --query "[?id == '$SELLER_SUBSCRIPTION_ID'].{Id:id}" -o tsv`
  log " AZURE_SUBSC_ID: $AZURE_SUBSC_ID"
  # Get Base domain RG name
  DNS_ZONE=$BASE_DOMAIN
  export BASE_DOMAIN_RG_NAME=`az network dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
  log " BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
  # Get VNet RG name for UPI based installation
  if [[ $INSTALLATION_MODE == "UPI" ]]; then
    # Domain name with private dns - only available for UPI
    if [[ $PRIVATE_CLUSTER == "true" ]]; then
        export private_or_public_cluster="private"
        export BASE_DOMAIN_RG_NAME=`az network private-dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
         log " UPI PRIVATE CLUSTER - BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
      else
         export private_or_public_cluster="public"
         export BASE_DOMAIN_RG_NAME=`az network dns zone list | jq --arg DNS_ZONE $DNS_ZONE '.[] | select(.name==$DNS_ZONE).resourceGroup' | tr -d '"'`
         log " UPI PUBLIC CLUSTER - BASE_DOMAIN_RG_NAME: $BASE_DOMAIN_RG_NAME"
      fi
       VNET_NAME=$EXISTING_NETWORK
       export EXISTING_NETWORK_RG=`az network vnet list | jq --arg VNET_NAME $VNET_NAME '.[] | select(.name==$VNET_NAME).resourceGroup' | tr -d '"'`
        #Assign the nsg name
      # export nsg_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name  $VNET_NAME|jq '.[0] | select(.name).networkSecurityGroup.id'|awk -F'/' '{print $9}'|tr -d '"'`
        #Assign the network subnet
       export  master_subnet_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME|jq '.[] | select(.name).name'|grep master|tr -d '"'`
       export  worker_subnet_name=`az network vnet subnet list --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME|jq '.[] | select(.name).name'|grep worker|tr -d '"'`
       export  virtual_network_cidr=`az network vnet show --resource-group $EXISTING_NETWORK_RG -n $VNET_NAME|jq -r '.addressSpace.addressPrefixes[0]'|tr -d '"'`
       export  master_subnet_cidr=`az network vnet subnet show --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME -n master-subnet|jq  -r '.addressPrefix'`
       export  worker_subnet_cidr=`az network vnet subnet show --resource-group $EXISTING_NETWORK_RG --vnet-name $VNET_NAME -n worker-subnet|jq  -r '.addressPrefix'`
       Ip_range=$worker_subnet_cidr
       #10.0.3.224/27
       export bastion_cidr=`echo $Ip_range|cut -d "." -f 1`.`echo $Ip_range|cut -d "." -f 2`.3.224/27
       export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
       export REQUESTER_VPC_ID=$EXISTING_NETWORK
  elif [[ $INSTALLATION_MODE == "IPI" ]]; then
    # Setting the cidr ranges for IPI mode
      export  master_subnet_name="master-subnet"
      export  worker_subnet_name="worker-subnet"
      export  virtual_network_cidr="10.0.0.0/16"
      export  master_subnet_cidr="10.0.1.0/24"
      export  worker_subnet_cidr="10.0.2.0/24"
      export bastion_cidr="10.0.3.224/27"
      export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
      export REQUESTER_VPC_ID=$EXISTING_NETWORK
   elif [[  (-n $ExocpProvisionedVPCId) ]]; then
    #exocp
     log "Existing instance of db @ VPC_ID=$DBProvisionedVPCId"
        export ACCEPTER_VPC_ID=${DBProvisionedVPCId}
        export REQUESTER_VPC_ID=$ExocpProvisionedVPCId
  fi
     log " MASTER SUBNET NAME: $master_subnet_name "
     log " WORKER SUBNET NAME: $worker_subnet_name"
     log " VNET CIDR RANGE: $virtual_network_cidr "
     log " MASTER SUBNET CIDR RANGE: $master_subnet_cidr "
     log " WORKER SUBNET CIDR RANGE : $worker_subnet_cidr"
     log " BASTION  CIDR RANGE : $bastion_cidr"
     log " cluster_network_cidr : $cluster_network_cidr"
        #  log " NSG NAME: $nsg_name"
     log " EXISTING_NETWORK_RG: $EXISTING_NETWORK_RG"
     log " Existing database VNet ID: $ACCEPTER_VPC_ID"
     log " Vnet Id of Cluster: $REQUESTER_VPC_ID"
fi
#====================

# Deploy OCP cluster and bastion host
if [[ $OPENSHIFT_USER_PROVIDE == "false" ]]; then
  cd $GIT_REPO_HOME

  ## Create OCP cluster
    cd $GIT_REPO_HOME/azure
    set +e
    ./create-ocp-cluster.sh
    retcode=$?

  if [[ $retcode -ne 0 ]]; then
      log "OCP cluster creation failed"
      exit 21
  else
    # Create a secret in the Cloud to keep OCP access credentials
    cd $GIT_REPO_HOME
    ./create-secret.sh ocp


  fi
  set -e

  oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 --insecure-skip-tls-verify=true
  log "==== Adding PID limits to worker nodes ===="
  oc create -f $GIT_REPO_HOME/templates/container-runtime-config.yml

  # Backup deployment context
  rm -rf /tmp/ansible-devops
  mkdir /tmp/ansible-devops
  cp -r * /tmp/ansible-devops
  cd /tmp
  zip -r $BACKUP_FILE_NAME ansible-devops/*
  rm -rf /tmp/ansible-devops
  set +e
  az storage blob upload --account-name ${STORAGE_ACNT_NAME} --container-name masocpcontainer --name ${DEPLOYMENT_CONTEXT_UPLOAD_PATH} --file ${BACKUP_FILE_NAME}
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "Failed while uploading deployment context to blob storage"
    exit 23
  fi
  set -e
  log "OCP cluster deployment context backed up at $DEPLOYMENT_CONTEXT_UPLOAD_PATH in file $CLUSTER_NAME.zip"

else
  log "==== Existing OCP cluster provided, skipping the cluster creation, Bastion host creation and S3 upload of deployment context ===="
fi

# Login to OCP cluster
log "==== Adding ER key details to OCP default pull-secret ===="
cd /tmp
export OCP_SERVER="$(echo https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443)"
oc login -u $OCP_USERNAME -p $OCP_PASSWORD --server=$OCP_SERVER --insecure-skip-tls-verify=true
export OCP_TOKEN="$(oc whoami --show-token)"
oc extract secret/pull-secret -n openshift-config --keys=.dockerconfigjson --to=. --confirm
export encodedEntitlementKey=$(echo cp:$SLS_ENTITLEMENT_KEY | tr -d '\n' | base64 -w0)
export emailAddress=$(cat .dockerconfigjson | jq -r '.auths["cloud.openshift.com"].email')
jq '.auths |= . + {"cp.icr.io": { "auth" : "$encodedEntitlementKey", "email" : "$emailAddress"}}' .dockerconfigjson >/tmp/dockerconfig.json

envsubst </tmp/dockerconfig.json >/tmp/.dockerconfigjson
oc set data secret/pull-secret -n openshift-config --from-file=/tmp/.dockerconfigjson

# Run ansible playbook to create azurefiles storage class
log "=== Creating azurefiles-premium Storage class , managed-premium Storage class on OCP cluster ==="
cd $GIT_REPO_HOME/azure/azurefiles
./azurefiles-premium.sh
retcode=$?
if [[ $retcode -ne 0 ]]; then
  log "Failed to create azurefiles-premium storageclass"
  exit 27
fi

## Configure OCP cluster
log "==== OCP cluster configuration (Cert Manager) started ===="
cd $GIT_REPO_HOME
set +e
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
if [[ $? -ne 0 ]]; then
  # One reason for this failure is catalog sources not having required state information, so recreate the catalog-operator pod
  # https://bugzilla.redhat.com/show_bug.cgi?id=1807128
  echo "Deleting catalog-operator pod"
  podname=$(oc get pods -n openshift-operator-lifecycle-manager | grep catalog-operator | awk {'print $1'})
  oc logs $podname -n openshift-operator-lifecycle-manager
  oc delete pod $podname -n openshift-operator-lifecycle-manager
  sleep 10
  # Retry the step
  export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role
  retcode=$?
  if [[ $retcode -ne 0 ]]; then
    log "Failed while configuring OCP cluster"
    exit 24
  fi
fi
log "==== OCP cluster configuration (Cert Manager) completed ===="

if [[ -n $DBProvisionedVPCId ]]; then
   log "==== Vnet peering between  cluster and Database starts  ===="

   cd $GIT_REPO_HOME
   sh $GIT_REPO_HOME/azure/db/db-create-vnet-peer.sh
   log "==== Vnet peering between  cluster and Database ends  ===="
fi
set -e
## Deploy MongoDB
log "==== MongoDB deployment started ===="
export ROLE_NAME=mongodb && ansible-playbook ibm.mas_devops.run_role
log "==== MongoDB deployment completed ===="

## Copying the entitlement.lic to MAS_CONFIG_DIR
cp $GIT_REPO_HOME/entitlement.lic $MAS_CONFIG_DIR

## Deploy Amqstreams
# log "==== Amq streams deployment started ===="
# ansible-playbook install-amqstream.yml
# log "==== Amq streams deployment completed ===="

# SLS Deployment
if [[ (-z $SLS_URL) || (-z $SLS_REGISTRATION_KEY) || (-z $SLS_PUB_CERT_URL) ]]; then
  ## Deploy SLS
  log "==== SLS deployment started ===="
  # sls and gencfg_sls are combined in common sls role
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "==== SLS deployment completed ===="

else
  log "=== Using Existing SLS Deployment ==="  #
  # works when SLS_URL is set, handled in same sls role
  export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated SLS Config YAML ==="
fi

# Deploy UDS
if [[ (-z $UDS_API_KEY) || (-z $UDS_ENDPOINT_URL) || (-z $UDS_PUB_CERT_URL) ]]; then
  # Deploy UDS
  log "==== UDS deployment started ===="
  # uds and gencfg_uds are combined in common uds role
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "==== UDS deployment completed ===="

else
  log "=== Using Existing UDS Deployment ==="
  # works when UDS_ENDPOINT_URL is set, handled in same uds role
  export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role
  log "=== Generated UDS Config YAML ==="
fi

# Deploy CP4D
if [[ $DEPLOY_CP4D == "true" ]]; then
  log "==== CP4D deployment started ===="
  export ROLE_NAME=cp4d && ansible-playbook ibm.mas_devops.run_role
  log "==== CP4D deployment completed ===="
fi

## Deploy Manage
if [[ $DEPLOY_MANAGE == "true" && (-z $MAS_JDBC_USER) && (-z $MAS_JDBC_PASSWORD) && (-z $MAS_JDBC_URL) && (-z $MAS_JDBC_CERT_URL) ]]; then

  log "==== Configure internal db2 for manage started ===="
  export ROLE_NAME=db2 && ansible-playbook ibm.mas_devops.run_role
  export ROLE_NAME=suite_db2_setup_for_manage && ansible-playbook ibm.mas_devops.run_role
  log "==== Configuration of internal db2 for manage completed ===="
fi

## Create MAS Workspace
log "==== MAS Workspace generation started ===="
export ROLE_NAME=gencfg_workspace && ansible-playbook ibm.mas_devops.run_role
log "==== MAS Workspace generation completed ===="

if [[ $DEPLOY_MANAGE == "true" && (-n $MAS_JDBC_USER) && (-n $MAS_JDBC_PASSWORD) && (-n $MAS_JDBC_URL) ]]; then
      export SSL_ENABLED=false
      #Setting the DB values
      if [[ -n $MANAGE_TABLESPACE ]]; then
        log " MANAGE_TABLESPACE: $MANAGE_TABLESPACE"
        export MAS_APP_SETTINGS_DB2_SCHEMA=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 1)
        export MAS_APP_SETTINGS_TABLESPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 2)
        export MAS_APP_SETTINGS_INDEXSPACE=$(echo $MANAGE_TABLESPACE | cut -d ':' -f 3)
      else
         if [[ ${MAS_JDBC_URL,, } =~ ^jdbc:db2? ]]; then
                       log "Setting to DB2 Values"
                        export MAS_APP_SETTINGS_DB2_SCHEMA="maximo"
                        export MAS_APP_SETTINGS_TABLESPACE="maxdata"
                        export MAS_APP_SETTINGS_INDEXSPACE="maxindex"
        elif [[ ${MAS_JDBC_URL,, } =~ ^jdbc:sql? ]]; then
                         log "Setting to MSSQL Values"
                          export MAS_APP_SETTINGS_DB2_SCHEMA="dto"
                          export MAS_APP_SETTINGS_TABLESPACE="PRIMARY"
                          export MAS_APP_SETTINGS_INDEXSPACE="PRIMARY"
        elif [[ ${MAS_JDBC_URL,, } =~ ^jdbc:oracle? ]]; then
                          log "Setting to ORACLE Values"
                          export MAS_APP_SETTINGS_DB2_SCHEMA="maximo"
                          export MAS_APP_SETTINGS_TABLESPACE="maxdata"
                          export MAS_APP_SETTINGS_INDEXSPACE="maxindex"
        fi
      fi
      log " MAS_APP_SETTINGS_DB2_SCHEMA: $MAS_APP_SETTINGS_DB2_SCHEMA"
      log " DEPLOY_MANAGEMAS_APP_SETTINGS_TABLESPACE: $MAS_APP_SETTINGS_TABLESPACE"
      log " MAS_APP_SETTINGS_INDEXSPACE: $MAS_APP_SETTINGS_INDEXSPACE"
  if [ -n "$MAS_JDBC_CERT_URL" ]; then
    log "MAS_JDBC_CERT_URL is not empty, setting SSL_ENABLED as true"
    export SSL_ENABLED=true
  fi
  log "==== Configure JDBC started for external DB2 ==== SSL_ENABLED = $SSL_ENABLED"
  export ROLE_NAME=gencfg_jdbc && ansible-playbook ibm.mas_devops.run_role
  log "==== Configure JDBC completed for external DB2 ===="
fi

## Deploy MAS
log "==== MAS deployment started ===="
export ROLE_NAME=suite_dns && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_install && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_config && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_verify && ansible-playbook ibm.mas_devops.run_role
log "==== MAS deployment completed ===="

## Deploy Manage
if [[ $DEPLOY_MANAGE == "true" ]]; then
  # Deploy Manage
  log "==== MAS Manage deployment started ===="
  export ROLE_NAME=suite_app_install && ansible-playbook ibm.mas_devops.run_role
  log "==== MAS Manage deployment completed ===="

  # Configure app to use the DB
  log "==== MAS Manage configure app started ===="
  export MAS_APPWS_BINDINGS_JDBC="workspace-application"
  export ROLE_NAME=suite_app_config && ansible-playbook ibm.mas_devops.run_role
  log "==== MAS Manage configure app completed ===="
fi