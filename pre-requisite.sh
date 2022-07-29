. ./script-functions.bash
. helper.sh
export -f log

checkROSA
retcode=$?
if [[ $retcode -eq 30 || $retcode -eq 29  ]]; then
	return $retcode
fi

getOCPVersion
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

getWorkerNodeDetails
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

getOCS ocs-operator
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

getVersion MongoDBCommunity
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

arr=(cpd-platform-operator ibm-sls ibm-cert-manager-operator user-data-services-operator)
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

# getSBOVersion
# retcode=$?
# if [[ $retcode -eq 29 ]]; then
# 	return $retcode
# fi

getVersion Db2uCluster
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

# getKafkaVersion
# retcode=$?
# if [[ $retcode -eq 29 ]]; then
# 	return $retcode
# fi

##log " KAFKA_NAMESPACE: $KAFKA_NAMESPACE"
log " CPD_OPERATORS_NAMESPACE: $CPD_OPERATORS_NAMESPACE"
log " CPD_INSTANCE_NAMESPACE=$CPD_INSTANCE_NAMESPACE"
log " SLS_NAMESPACE: $SLS_NAMESPACE"
log " MONGODB_NAMESPACE: $MONGODB_NAMESPACE"

