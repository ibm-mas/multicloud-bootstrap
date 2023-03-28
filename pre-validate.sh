#!/bin/bash
SCRIPT_STATUS=0

# Check if region is supported
if [[ $CLUSTER_TYPE == "aws" ]]; then
    SUPPORTED_REGIONS="us-east-1;us-east-2;us-west-2;ca-central-1;eu-north-1;eu-west-1;eu-west-2;eu-west-3;eu-central-1;ap-northeast-1;ap-northeast-2;ap-northeast-3;ap-south-1;ap-southeast-1;ap-southeast-2;sa-east-1;ap-east-1;ap-southeast-3;eu-south-1;me-south-1;me-central-1;af-south-1"
elif [[ $CLUSTER_TYPE == "azure" ]]; then
    # az account list-locations --query "[].{Name:name}" -o table|grep -Ev '^(Name|-)'|tr '\n' ';'
    SUPPORTED_REGIONS="eastus;eastus2;southcentralus;westus2;westus3;australiaeast;southeastasia;northeurope;swedencentral;uksouth;westeurope;centralus;southafricanorth;centralindia;eastasia;japaneast;koreacentral;canadacentral;francecentral;germanywestcentral;norwayeast;brazilsouth"
elif [[ $CLUSTER_TYPE == "gcp" ]]; then
    SUPPORTED_REGIONS="asia-east1;asia-east2;asia-northeast1;asia-northeast2;asia-northeast3;asia-south1;asia-south2;asia-southeast1;asia-southeast2;australia-southeast12;europe-central2;europe-north1;europe-southwest1;europe-west1;europe-west2;europe-west3;europe-west4;europe-west6;europe-west8;europe-west9;northamerica-northeast1;northamerica-northeast2;southamerica-east1;southamerica-west1;us-central1;us-east1;us-east4;us-east5;us-south1;us-west1;us-west2;us-west3;us-west4"
else
    SUPPORTED_REGIONS=$DEPLOY_REGION
fi
found=false
sentence=${SUPPORTED_REGIONS//;/$'\n'}
for reg in $sentence
do
  if [[ $DEPLOY_REGION == $reg ]]; then
    found=true
	break
  fi
done
log "Region found: $found"
if [[ $found == true ]]; then
    log "Supported region = PASS"
else
    log "ERROR: Supported region = FAIL"
    SCRIPT_STATUS=11
fi

# Check if ER key is valid
log "ER key verification = $SLS_ENTITLEMENT_KEY"
skopeo inspect --creds "cp:$SLS_ENTITLEMENT_KEY" docker://$MAS_IMAGE_TEST_DOWNLOAD >/dev/null
if [ $? -eq 0 ]; then
    log "ER key verification = PASS"
else
    log "ERROR: ER key verification = FAIL"
    SCRIPT_STATUS=12
fi

# Check if provided hosted zone is public
if [[ ($CLUSTER_TYPE == "aws") && (-n $BASE_DOMAIN) ]]; then

    if [[ $PRIVATE_CLUSTER == "false" ]]; then
        aws route53 list-hosted-zones --output text --query 'HostedZones[*].[Config.PrivateZone,Name,Id]' --output text | grep $BASE_DOMAIN | grep False
    else
        aws route53 list-hosted-zones --output text --query 'HostedZones[*].[Config.PrivateZone,Name,Id]' --output text | grep $BASE_DOMAIN | grep True
    fi
    #elif [[ $CLUSTER_TYPE == "azure" ]]; then
    #az network dns zone list | jq -r --arg BASE_DOMAIN "$BASE_DOMAIN" '.[]|select (.name==$BASE_DOMAIN)|.zoneType' | grep -iE 'public'
else
    true
fi
# Check if provided hosted zone is public /private for azure
if [[ ($CLUSTER_TYPE == "azure") && (-n $BASE_DOMAIN) ]]; then
    if [[ $PRIVATE_CLUSTER == "false" ]]; then
       PUBLIC_DNS_VALIDATION=`az network dns zone list  |grep -w $BASE_DOMAIN| tr -d '"'`
          [[ ! -z "$PUBLIC_DNS_VALIDATION" ]] && log "Valid PUBLIC DNS selection" || log "Invalid PUBLIC DNS SELECTION"
        else
         PRIVATE_DNS_VALIDATION=`az network private-dns zone list |grep -w $BASE_DOMAIN| tr -d '"'`
           [[ ! -z "$PRIVATE_DNS_VALIDATION" ]] && log "Valid PRIVATE DNS selection" || log "Invalid PRIVATE DNS SELECTION"
    fi
fi

if [ $? -eq 0 ]; then
    log "MAS public domain verification = PASS"
else
    log "ERROR: MAS public domain verification = FAIL"
    SCRIPT_STATUS=13
fi

# check if CNAME and A records already exist for the given MAS instance being deployed
# A) Check if the DNS zone A records already exists wtih $UNIQ_STR
#A_RECS=$(az network dns record-set a list -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN | jq ".[] | select(.name == \"*.apps.masocp-$UNIQ_STR\").name" | tr -d '"')

#if [[ -n $A_RECS ]]; then
#    log "ERROR: Record set with $UNIQ_STR already exists as $A_RECS"
#    SCRIPT_STATUS=25
#fi

# B) Check if the DNS zone CNAME records already exists wtih $UNIQ_STR
#CNAME_RECS=$(az network dns record-set cname list -g $BASE_DOMAIN_RG_NAME -z $BASE_DOMAIN | jq ".[] | select(.name == \"api.masocp-$UNIQ_STR\").name" | tr -d '"')
#if [[ -n $CNAME_RECS ]]; then
#    log "ERROR: Record set with $UNIQ_STR already exists as $CNAME_REC"
#    SCRIPT_STATUS=25
#fi

# JDBC CFT inputs validation and connection test
if [[ $DEPLOY_MANAGE == "true" ]]; then
    if [[ (-z $MAS_JDBC_USER) && (-z $MAS_JDBC_PASSWORD) && (-z $MAS_JDBC_URL) && (-z $MAS_JDBC_CERT_URL) ]]; then
        log "=== New internal DB2 database will be provisioned for MAS Manage deployment ==="
    else
        if [ -z "$MAS_JDBC_USER" ]; then
            log "ERROR: Database username is not specified"
            SCRIPT_STATUS=14
        elif [ -z "$MAS_JDBC_PASSWORD" ]; then
            log "ERROR: Database password is not specified"
            SCRIPT_STATUS=14
        elif [ -z "$MAS_JDBC_URL" ]; then
            log "ERROR: Database connection url is not specified"
            SCRIPT_STATUS=14
        else
            log "Downloading DB certificate"
            cd $GIT_REPO_HOME
            if [[ $CLUSTER_TYPE == "aws" ]]; then
                if [[ ${MAS_JDBC_CERT_URL,,} =~ ^s3 ]]; then
                    aws s3 cp "$MAS_JDBC_CERT_URL" db.crt --region us-east-1
                    ret=$?
        		if [ $ret -ne 0 ]; then
        			aws s3 cp "$MAS_JDBC_CERT_URL" db.crt --region $DEPLOY_REGION
        			ret=$?
        		if [ $ret -ne 0 ]; then
            		log "Invalid DB certificate URL"
            		SCRIPT_STATUS=31
        		fi
        		fi
                elif [[ ${MAS_JDBC_CERT_URL,,} =~ ^https? ]]; then
                    wget "$MAS_JDBC_CERT_URL" -O db.crt
                fi
            elif [[ $CLUSTER_TYPE == "azure" ]]; then
                # https://myaccount.blob.core.windows.net/mycontainer/myblob regex
                if [[ ${MAS_JDBC_CERT_URL,,} =~ ^https://.+blob\.core\.windows\.net.+ ]]; then
                    azcopy copy "$MAS_JDBC_CERT_URL" db.crt
                elif [[ ${MAS_JDBC_CERT_URL,,} =~ ^https? ]]; then
                    wget "$MAS_JDBC_CERT_URL" -O db.crt
                fi
            elif [[ $CLUSTER_TYPE == "gcp" ]]; then
                wget "$MAS_JDBC_CERT_URL" -O db.crt
            fi
            export MAS_DB2_JAR_LOCAL_PATH=$GIT_REPO_HOME/lib/db2jcc4.jar
            if [[ ${MAS_JDBC_URL,, } =~ ^jdbc:db2? ]]; then
                log "Connecting to DB2 Database"
                if python jdbc-prevalidateDB2.py; then
                    log "Db2 JDBC URL Validation = PASS"
                else
                    log "ERROR: Db2 JDBC URL Validation = FAIL"
                    SCRIPT_STATUS=14
                fi
            elif [[ ${MAS_JDBC_URL,, } =~ ^jdbc:oracle? ]]; then
                export MAS_ORACLE_JAR_LOCAL_PATH=$GIT_REPO_HOME/lib/ojdbc8.jar
                log "Connecting to Oracle Database"
                if python jdbc-prevalidateOracle.py; then
                    log "Oracle JDBC URL Validation = PASS"
				else
                    log "ERROR: Oracle JDBC URL Validation = FAIL"
                    SCRIPT_STATUS=14
                fi
            else
                log "Skipping JDBC URL validation, supported only for DB2 and Oracle".
            fi
        fi
    fi
fi

#mongo pre-validation only for AWS currently. 
if [[ $CLUSTER_TYPE == "aws" ]]; then
    log "=== pre-validate-mongo.sh started ==="
    sh $GIT_REPO_HOME/mongo/pre-validate-mongo.sh
    SCRIPT_STATUS=$?
    if [ $SCRIPT_STATUS -ne 0 ]; then
        log "ERROR: MongoDB URL Validation FAILED in pre-validate-mongo.sh, exiting"
        exit $SCRIPT_STATUS
    fi
    log "=== pre-validate-mongo.sh completed ==="
fi

# Check if all the existing SLS inputs are provided
if [[ (-z $SLS_URL) && (-z $SLS_REGISTRATION_KEY) && (-z $SLS_PUB_CERT_URL) ]]; then
    log "=== New SLS Will be deployed ==="
else
    if [ -z "$SLS_URL" ]; then
        log "ERROR: SLS Endpoint URL is not specified"
        SCRIPT_STATUS=15
    elif [ -z "$SLS_REGISTRATION_KEY" ]; then
        log "ERROR: SLS Registration Key is not specified"
        SCRIPT_STATUS=15
    elif [ -z "$SLS_PUB_CERT_URL" ]; then
        log "ERROR: SLS Public Cerificate URL is not specified"
        SCRIPT_STATUS=15
    else
        log "=== Using existing SLS deployment inputs ==="
    fi
fi

# Check if all the existing UDS inputs are provided
if [[ (-z $UDS_API_KEY) && (-z $UDS_ENDPOINT_URL) && (-z $UDS_PUB_CERT_URL) ]]; then
    log "=== New UDS Will be deployed ==="
else
    if [ -z "$UDS_API_KEY" ]; then
        log "ERROR: UDS API Key is not specified"
        SCRIPT_STATUS=16
    elif [ -z "$UDS_ENDPOINT_URL" ]; then
        log "ERROR: UDS Endpoint URL is not specified"
        SCRIPT_STATUS=16
    elif [ -z "$UDS_PUB_CERT_URL" ]; then
        log "ERROR: UDS Public Cerificate URL is not specified"
        SCRIPT_STATUS=16
    else
        log "=== Using existing UDS deployment inputs ==="
    fi
fi

# Check if all the existing OpenShift inputs are provided
if [[ (-z $EXS_OCP_URL) && (-z $EXS_OCP_USER) && (-z $EXS_OCP_PWD) ]]; then
    log "=== New OCP Cluster and associated user and password will be deployed ==="
    if [[ -z $OCP_PULL_SECRET ]]; then
        log "ERROR: OpenShift pull secret is required for OCP cluster deployment"
        SCRIPT_STATUS=17
    fi
else
    if [ -z "$EXS_OCP_URL" ]; then
        log "ERROR: Existing OCP Cluster URL is not specified"
        SCRIPT_STATUS=19
    elif [ -z "$EXS_OCP_USER" ]; then
        log "ERROR: Existing OCP Cluster user is not specified"
        SCRIPT_STATUS=19
    elif [ -z "$EXS_OCP_PWD" ]; then
        log "ERROR: Existing OCP Cluster password is not specified"
        SCRIPT_STATUS=19
    else
        log "=== Using existing OCP deployment inputs ==="
    fi
fi

## Evalute custom annotations to set with reference from aws-product-codes.config
## Evaluate PRODUCT_NAME environment variable to create configmap in SLS namespace.
## MAS_ANNOTATIONS environment variable is used in suit-install role of MAS Installtion

if [[ $CLUSTER_TYPE == "aws" ]]; then
    # Validating product type for helper.sh
    validate_prouduct_type
fi
# Check if MAS license is provided
if [[ -z $MAS_LICENSE_URL ]]; then
    if [[ $PRODUCT_TYPE == "byol" ]]; then
        log "ERROR: Valid MAS license is reqiuired for MAS deployment"
        SCRIPT_STATUS=18
    fi
else
    # Download MAS license
    log "==== Downloading MAS license ===="
    cd $GIT_REPO_HOME
    if [[ ${MAS_LICENSE_URL,,} =~ ^https? ]]; then
        mas_license=$(wget --server-response "$MAS_LICENSE_URL" -O entitlement.lic 2>&1 | awk '/^  HTTP/{print $2}')
        # Removed leading #
        sed -i '/^#/d' entitlement.lic

        if [ $mas_license -ne 200 ]; then
            log "Invalid MAS License URL"
            SCRIPT_STATUS=18
        fi
    elif [[ ${MAS_LICENSE_URL,,} =~ ^s3 ]]; then
        mas_license=$(aws s3 cp "$MAS_LICENSE_URL" entitlement.lic --region us-east-1 2>/dev/null)
        # Removed leading #
        sed -i '/^#/d' entitlement.lic

        ret=$?
        if [ $ret -ne 0 ]; then
        mas_license=$(aws s3 cp "$MAS_LICENSE_URL" entitlement.lic --region $DEPLOY_REGION 2>/dev/null)
        # Removed leading #
        sed -i '/^#/d' entitlement.lic

        ret=$?
        if [ $ret -ne 0 ]; then
            log "Invalid MAS License URL"
            SCRIPT_STATUS=18
        fi
        fi
    else
        log "ERROR: Valid MAS license is reqiuired for MAS deployment"
        SCRIPT_STATUS=18
    fi
    if [[ -f entitlement.lic ]]; then
        chmod 600 entitlement.lic
    fi
fi

if [[ $CLUSTER_TYPE == "azure" ]]; then
    if [[ $EMAIL_NOTIFICATION == "true" ]]; then
        if [[ (-z $SMTP_HOST) || (-z $SMTP_PORT) || (-z $SMTP_USERNAME) || (-z $SMTP_PASSWORD) || (-z $RECEPIENT) ]]; then
            log "ERROR: Missing required parameters when email notification is set to true."
            SCRIPT_STATUS=26
        fi
    fi
fi

# Check if all the subnet values are provided for existing VPC Id
if [[ -n $ExistingVPCId ]]; then
    if [[ (-n $ExistingPrivateSubnet1Id) && (-n $ExistingPrivateSubnet2Id) && (-n $ExistingPrivateSubnet3Id) && (-n $ExistingPublicSubnet1Id) && (-n $ExistingPublicSubnet2Id) && (-n $ExistingPublicSubnet3Id) ]]; then
        log "=== OCP cluster will be deployed with existing VPCs ==="
    else
        log "ERROR: Subnets missing for the VPC"
        SCRIPT_STATUS=27
    fi
fi

exit $SCRIPT_STATUS
