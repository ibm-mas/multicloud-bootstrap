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
	getOPNamespace ibm-sls
	retcode=$?
	if [[ $retcode -eq 29 ]]; then
		return $retcode
	fi
fi

export SLS_MONGODB_CFG_FILE="${MAS_CONFIG_DIR}/mongo-${MONGODB_NAMESPACE}.yml"
log " SLS_MONGODB_CFG_FILE: $SLS_MONGODB_CFG_FILE"

arr=(ibm-cert-manager-operator user-data-services-operator)
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
