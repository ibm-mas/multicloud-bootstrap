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


getWorkerNodeDetails
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

if [[ $DEPLOY_CP4D == "true" ]]; then

	if [[ $CLUSTER_TYPE == "aws" ]]; then
		getOCS ocs-operator
	elif [[ $CLUSTER_TYPE == "azure" ]]; then
		getazurefile
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

	getVersion Db2uCluster
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
	return $retcode
	fi
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

# Skip UDS check in case of external UDS details are provided
if [[ (-z $UDS_API_KEY) || (-z $UDS_ENDPOINT_URL) || (-z $UDS_PUB_CERT_URL) ]]; then
	getOPNamespace user-data-services-operator
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
    	return $retcode
	fi
else
  log "=== Using External UDS Deployment ==="
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
