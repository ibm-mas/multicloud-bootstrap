. ./script-functions.bash
. helper.sh
export -f log

checkROSA
retcode=$?
if [[ $retcode -eq 30 || $retcode -eq 29  ]]; then
	return $retcode
fi

if [[ $ROSA = ""  ]]; then
	getOCPVersion
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
	return $retcode
	fi
fi

if [[ $ROSA == "true" ]]; then
	log " Checking for EFS Storage"
	getEFS
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
	return $retcode
	fi
fi

getWorkerNodeDetails
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

if [[ ($DEPLOY_CP4D == "true") && ($ROSA != "true") ]]; then
	if [[ $CLUSTER_TYPE == "aws" ]]; then
		getOCS ocs-operator
	elif [[ $CLUSTER_TYPE == "azure" ]]; then
	     #log "In prereq - EXISTING_CLUSTER is $EXISTING_CLUSTER"
        if [[ -z $EXISTING_CLUSTER  ]]; then
		        getazurefile
		    fi
	fi

	retcode=$?
	if [[ $retcode -eq 29 ]]; then
		return $retcode
	fi

	getOPNamespace cpd-platform-operator
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
	return $retcode
	fi
#commenting this as we dont use db2u cluster ,instead we are using cp4d db2wh
	#getVersion Db2uCluster
	#retcode=$?
	#if [[ $retcode -eq 29 ]]; then
	#return $retcode
	#fi
fi


getVersion MongoDBCommunity
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

# Skip SLS check in case of paid offering
if [[ $PRODUCT_TYPE != "privatepublic" ]]; then
	# Skip SLS check in case of external SLS details are provided
	if [[ (-z $SLS_URL) || (-z $SLS_REGISTRATION_KEY) || (-z $SLS_PUB_CERT_URL) ]]; then
		getOPNamespace ibm-sls
		retcode=$?
		if [[ $retcode -eq 29 ]]; then
			return $retcode
		fi
	else
  		log "=== Using External SLS Deployment ==="
	fi
fi

export SLS_MONGODB_CFG_FILE="${MAS_CONFIG_DIR}/mongo-${MONGODB_NAMESPACE}.yml"
log " SLS_MONGODB_CFG_FILE: $SLS_MONGODB_CFG_FILE"

# Skip DRO check in case of external DRO details are provided
if [[ (-z $DRO_API_KEY) || (-z $DRO_ENDPOINT_URL) || (-z $DRO_PUB_CERT_URL) ]]; then
	getOPNamespace user-data-services-operator
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
    	return $retcode
	fi
else
  log "=== Using External DRO Deployment ==="
fi

arr=(ibm-cert-manager-operator)
i=0

while [ $i -lt ${#arr[@]} ]
do
	getOPNamespace ${arr[$i]}
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
    	return $retcode
	fi
	i=`expr $i + 1`
done

# # getSBOVersion
# # retcode=$?
# # if [[ $retcode -eq 29 ]]; then
# # 	return $retcode
# # fi

getKafkaVersion
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

log " KAFKA_NAMESPACE: $KAFKA_NAMESPACE"
log " CPD_OPERATORS_NAMESPACE: $CPD_OPERATORS_NAMESPACE"
log " CPD_INSTANCE_NAMESPACE: $CPD_INSTANCE_NAMESPACE"
log " SLS_NAMESPACE: $SLS_NAMESPACE"
log " MONGODB_NAMESPACE: $MONGODB_NAMESPACE"
