#!/bin/bash
#set -e
. helper.sh
export -f log

SCRIPT_STATUS=0
declare -A op_versions
op_versions['MongoDBCommunity']='^4\.([2-4]?)?(\.[0-9]+.*)*$'
op_versions['Db2uCluster']='^11.(5)(.[0-9]+.*)*$'
op_versions['kafkas.kafka.strimzi.io']='^2\.([4-7]?)?(\.[0-9]+.*)*$'
op_versions['ocpVersion']='^4\.([8-9]|([1-9][0-9])?)?(\.[0-9]+.*)*$'
op_versions['cpd-platform-operator']='^[2]\.[0]\.[8-9]$'
op_versions['user-data-services-operator']='^[2]\.[0]\.[8-9]$'
op_versions['ibm-cert-manager-operator']='^[3]\.[2][1]\.[0-9]$'
op_versions['ibm-sls']='^[3]\.[3]\.[0-9]$'
op_versions['service-binding-operator']='^[1]\.[1]\.[1]$'

declare -A op_namespaces
op_namespaces['cpd-platform-operator']='CPD_OPERATORS_NAMESPACE'
op_namespaces['ibm-sls']='SLS_NAMESPACE'
op_namespaces['MongoDBCommunity']='MONGODB_NAMESPACE'
op_namespaces['kafkas.kafka.strimzi.io']='KAFKA_NAMESPACE'

function getOPNamespace() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	if [[ $check_for_csv_success = "Succeeded" ]]; then
		op_namespace=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $1}')
		op_version=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $2}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
		echo $1 version is "$op_version"
		if [[ $op_version =~ ${op_versions[${1}]} ]]; then
			#echo "$op_namespace"
			echo "Supported Version"
			if [[  ${op_namespaces[${1}]} ]]; then
				export ${op_namespaces[${1}]}=$op_namespace
			fi
		else
			echo "Unsupported ${1} version $op_version."
			SCRIPT_STATUS=29
			exit $SCRIPT_STATUS
		fi
	else
		SCRIPT_STATUS=29
		exit $SCRIPT_STATUS
    fi    
	
}

function getVersion() {
	namespace=$(oc get $1  --all-namespaces | awk  'NR==2 {print $1 }')
	currentVersion=$(oc get $1 -n ${namespace}  -o json | jq .items[0].spec.version -r)
	echo $1 version is "$currentVersion"
	if [[ $currentVersion =~ ${op_versions[${1}]} ]]; then
		echo "Supported Version"
		if [[  ${op_namespaces[${1}]} ]]; then
			export ${op_namespaces[${1}]}=$namespace
		fi
  	else
    	echo "Unsupported ${1} version $currentVersion."
		SCRIPT_STATUS=29
		exit $SCRIPT_STATUS
  	fi
}

function getKafkaVersion() {
	namespace=$(oc get kafkas.kafka.strimzi.io  --all-namespaces | awk  'NR==2 {print $1 }')
	currentVersion=$(oc get kafkas.kafka.strimzi.io -n ${namespace}  -o json | jq .items[0].spec.kafka.version -r)
	echo Kafka version is "$currentVersion"
	if [[ $currentVersion =~ ${op_versions[kafkas.kafka.strimzi.io]} ]]; then
		#echo $namespace
    	echo "Supported Version"
		if [[  ${op_namespaces[kafkas.kafka.strimzi.io]} ]]; then
			export ${op_namespaces[kafkas.kafka.strimzi.io]}=$namespace
		fi
  	else
    	echo "Unsupported Kafka version $currentVersion."
		SCRIPT_STATUS=29
		exit $SCRIPT_STATUS
  fi
}

function getSBOVersion() {
	currentVersion=$(oc get csv -n default | grep service-binding-operator | awk -F' ' '{print $1}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching)
	echo service-binding-operator version is "$currentVersion"
	if [[ $currentVersion =~ ${op_versions[service-binding-operator]} ]]; then
		echo "Supported Version"
  	else
    	echo "Unsupported service-binding-operator version $currentVersion."
		SCRIPT_STATUS=29
		exit $SCRIPT_STATUS
  	fi
}

function getOCPVersion() {
	#ocpVersion="^4\\.([8-9]|([1-9][0-9])?)?(\\.[0-9]+.*)*$"
	currentOpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
	echo OCP version is "$currentOpenshiftVersion"
	if [[ $currentOpenshiftVersion =~ ${op_versions[ocpVersion]} ]]; then
    	echo "Supported Version"
  	else
    	echo "Unsupportedd Openshift version $currentOpenshiftVersion.Supported OpenShift versions are 4.8 to 4.10."
		SCRIPT_STATUS=29
		exit $SCRIPT_STATUS
  fi
}
