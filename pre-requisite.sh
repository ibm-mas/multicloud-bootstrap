. ./script-functions.bash
. helper.sh
export -f log

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

arr=(ocs-operator cpd-platform-operator ibm-cert-manager-operator user-data-services-operator ibm-sls)
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

getSBOVersion
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

getVersion MongoDBCommunity
retcode=$?
if [[ $retcode -eq 29 ]]; then
	return $retcode
fi

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


export CPD_INSTANCE_NAMESPACE=$(oc get ibmcpd --all-namespaces -o json | jq .items[0].metadata.namespace -r)


log " Debug: Namespaces where pre-requisite operators are installed."
##log " KAFKA_NAMESPACE: $KAFKA_NAMESPACE"
log " CPD_OPERATORS_NAMESPACE: $CPD_OPERATORS_NAMESPACE"
log " CPD_INSTANCE_NAMESPACE=$CPD_INSTANCE_NAMESPACE"
log " SLS_NAMESPACE: $SLS_NAMESPACE"
log " MONGODB_NAMESPACE: $MONGODB_NAMESPACE"

export SLS_MONGODB_CFG_FILE="${MAS_CONFIG_DIR}/mongo-${MONGODB_NAMESPACE}.yml"
log " SLS_MONGODB_CFG_FILE: $SLS_MONGODB_CFG_FILE"

export SLS_INSTANCE_NAME=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].metadata.name -r)
export SLS_REGISTRATION_KEY=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.registrationKey -r)
export SLS_LICENSE_ID=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.licenseId -r)

log " Debug: Existing SLS Details."
log " SLS_REGISTRATION_KEY: $SLS_REGISTRATION_KEY"
log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
log " SLS_LICENSE_ID=$SLS_LICENSE_ID"
