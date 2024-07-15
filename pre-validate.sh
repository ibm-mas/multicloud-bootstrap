#!/bin/bash
SCRIPT_STATUS=0

# Check if region is supported
if [[ $CLUSTER_TYPE == "aws" ]]; then
    SUPPORTED_REGIONS="us-gov-west-1;us-gov-east-1"
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

else
    true
fi
if [ $? -eq 0 ]; then
    log "MAS public domain verification = PASS"
else
    log "ERROR: MAS public domain verification = FAIL"
    SCRIPT_STATUS=13
fi

# JDBC CFT inputs validation and connection test
if [[ $DEPLOY_MANAGE == "true" ]]; then
    if [[ (-z $MAS_JDBC_USER) && (-z $MAS_JDBC_PASSWORD) && (-z $MAS_JDBC_URL) && (-z $MAS_JDBC_CERT_URL) ]]; then
     log "=== ERROR :DB values are not entered  ==="
      SCRIPT_STATUS=14
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
    validate_product_type
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