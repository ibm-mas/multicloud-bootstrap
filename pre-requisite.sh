. ./script-functions.bash
. helper.sh
export -f log

getOCPVersion
echo "--------------"
getSBOVersion
echo "--------------"
getVersion MongoDBCommunity
echo "--------------"
getVersion Db2uCluster
echo "--------------"
getKafkaVersion

arr=(ocs-operator cpd-platform-operator ibm-cert-manager-operator user-data-services-operator ibm-sls)
i=0

while [ $i -lt ${#arr[@]} ]
do
	echo "--------------"
	getOPNamespace ${arr[$i]}
	i=`expr $i + 1`
done


echo "---------------"
log " KAFKA_NAMESPACE: $KAFKA_NAMESPACE"
log " CPD_OPERATORS_NAMESPACE: $CPD_OPERATORS_NAMESPACE"
log " SLS_NAMESPACE: $SLS_NAMESPACE"
log " MONGODB_NAMESPACE: $MONGODB_NAMESPACE"
