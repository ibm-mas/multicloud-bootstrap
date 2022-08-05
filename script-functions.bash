#!/bin/bash

. helper.sh
export -f log

SCRIPT_STATUS=0
declare -A op_versions
op_versions['MongoDBCommunity']='^4\.([2-4]?)?(\.[0-9]+.*)*$'
op_versions['Db2uCluster']='^11.(5)(.[0-9]+.*)*$'
op_versions['kafkas.kafka.strimzi.io']='^2\.([4-7]?)?(\.[0-9]+.*)*$'
op_versions['ocpVersion']='^4\.([8-9]|([1-9][0-9])?)?(\.[0-9]+.*)*$'
op_versions['rosaVersion']='^4\.([1][0])?(\.[0-9]+.*)*$'
op_versions['cpd-platform-operator']='^[2]\.[0]\.[8-9]$'
op_versions['user-data-services-operator']='^[2]\.[0]\.[8-9]$'
op_versions['ibm-cert-manager-operator']='^[3]\.[2][1]\.[0-9]$'
op_versions['ibm-sls']='^[3]\.[4]\.[0-9]$'
op_versions['service-binding-operator']='^[1]\.[1]\.[1]$'

declare -A op_namespaces
op_namespaces['cpd-platform-operator']='CPD_OPERATORS_NAMESPACE'
op_namespaces['ibm-sls']='SLS_NAMESPACE'
op_namespaces['MongoDBCommunity']='MONGODB_NAMESPACE'
op_namespaces['kafkas.kafka.strimzi.io']='KAFKA_NAMESPACE'


function getOCS() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	sc_name=$(oc get sc | grep ocs-storagecluster-cephfs | awk -F' ' '{print $1}')
	log " OCS StorageClass : $sc_name"
	if [[ $check_for_csv_success != "Succeeded" && $sc_name = ""  ]]; then
		log " OCS StorageClass is not available"
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
	else
		log " OCS StorageClass is available"
    fi    
	
}

function getOPNamespace() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	if [[ $check_for_csv_success = "Succeeded" ]]; then
		op_namespace=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $1}')
		op_version=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $2}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
		log " $1 version is $op_version"
		if [[ $op_version =~ ${op_versions[${1}]} ]]; then
			#log " $op_namespace"
			log " Supported Version"
			if [[  ${op_namespaces[${1}]} ]]; then
				export ${op_namespaces[${1}]}=$op_namespace
			fi
			if [[  $1 = "ibm-sls" ]]; then
				export SLS_INSTANCE_NAME=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].metadata.name -r)
				export SLS_REGISTRATION_KEY=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.registrationKey -r)
				export SLS_LICENSE_ID=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.licenseId -r)

				log " Debug: Existing SLS Details."
				log " SLS_REGISTRATION_KEY: $SLS_REGISTRATION_KEY"
				log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
				log " SLS_LICENSE_ID=$SLS_LICENSE_ID"
			elif  [[  $1 = "cpd-platform-operator" ]]; then
				export CPD_INSTANCE_NAMESPACE=$(oc get ibmcpd --all-namespaces -o json | jq .items[0].metadata.namespace -r)	
			fi

		else
			log " Unsupported ${1} version $op_version."
			SCRIPT_STATUS=29
			return $SCRIPT_STATUS
		fi
    else
		log " $1 will be installed."
	fi
}

function getVersion() {
	namespace=$(oc get $1  --all-namespaces | awk  'NR==2 {print $1 }')
	if [[ $namespace = "" ]]; then
		log " $1 will be installed."
		return
	fi
	currentVersion=$(oc get $1 -n ${namespace}  -o json | jq .items[0].spec.version -r)
	log " $1 version is $currentVersion"
	if [[ $currentVersion =~ ${op_versions[${1}]} ]]; then
		log " Supported Version"
		if [[  ${op_namespaces[${1}]} ]]; then
			export ${op_namespaces[${1}]}=$namespace
		fi
  	else
    	log " Unsupported ${1} version $currentVersion."
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
  	fi
}

function getKafkaVersion() {
	namespace=$(oc get kafkas.kafka.strimzi.io  --all-namespaces | awk  'NR==2 {print $1 }')
	if [[ $namespace = "" ]]; then
		log " $1 will be installed."
		return
	fi
	currentVersion=$(oc get kafkas.kafka.strimzi.io -n ${namespace}  -o json | jq .items[0].spec.kafka.version -r)
	log " Kafka version is $currentVersion"
	if [[ $currentVersion =~ ${op_versions[kafkas.kafka.strimzi.io]} ]]; then
    	log " Supported Version"
		if [[  ${op_namespaces[kafkas.kafka.strimzi.io]} ]]; then
			export ${op_namespaces[kafkas.kafka.strimzi.io]}=$namespace
		fi
  	else
    	log " Unsupported Kafka version $currentVersion."
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
  fi
}

# function getSBOVersion() {
# 	currentVersion=$(oc get csv -n default | grep service-binding-operator | awk -F' ' '{print $1}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching)
# 	log " service-binding-operator version is $currentVersion"
# 	if [[ $currentVersion =~ ${op_versions[service-binding-operator]} ]]; then
# 		log " Supported Version"
#   	else
#     	log " Unsupported service-binding-operator version $currentVersion."
# 		SCRIPT_STATUS=29
# 		return $SCRIPT_STATUS
#   	fi
# }

function getOCPVersion() {
	#ocpVersion="^4\\.([8-9]|([1-9][0-9])?)?(\\.[0-9]+.*)*$"
	currentOpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
	log " OCP version is $currentOpenshiftVersion"
	if [[ $currentOpenshiftVersion =~ ${op_versions[ocpVersion]} ]]; then
    	log " Supported Version"
  	else
    	log " Unsupportedd Openshift version $currentOpenshiftVersion.Supported OpenShift versions are 4.8 to 4.10."
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
 	fi
}

function getWorkerNodeDetails(){
	x=($(oc get nodes | awk -e '$3 ~ /^worker/ {print $1}'));

	nodes=${#x[@]}

	if [ $nodes -ge 3 ]; then
		log " Minimum Worker Node requirement satisfied : $nodes worker nodes"
	else
		log " Minimum Worker Node requirement not satisfied"
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
	fi

	for i in "${x[@]}"
	do
		cpu=$(oc get -o template nodes "$i" --template={{.status.allocatable.cpu}})
		memory=$(oc get -o template nodes "$i" --template={{.status.allocatable.memory}})

		requiredCPU='^([0]?[0-9]|1[0-4])$'
		requiredCPU1='^([0]?[0-9]|1[0-4][0-9]{0,3}m)$'

		log " Worker Node : ${i}"
		log " CPU : ${cpu}"
		log " Memory : ${memory}"
		
		if [[ (${cpu} =~ ${requiredCPU} || ${cpu} =~ ${requiredCPU1}) ||  (${memory::-2} -lt 62000000) ]]; then
			log " Minimum CPU/Memory requirements not satisfied"
			SCRIPT_STATUS=29
			return $SCRIPT_STATUS
		fi		

	done;
	log " Minimum CPU requirement satisfied"
	log " Minimum Memory requirement satisfied"
}

checkROSA(){
	rosa_cm=$(oc get cm rosa-brand-logo -n openshift-config | awk  'NR==2 {print $2 }')
	if [[ $rosa_cm -eq 1 ]]; then
		log " ROSA Cluster "
		currentOpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
		log " OCP version is $currentOpenshiftVersion"
		if [[ $currentOpenshiftVersion =~ ${op_versions[rosaVersion]} ]]; then
    		log " Supported Version"
  		else
    		log " Unsupportedd ROSA version $currentOpenshiftVersion.Supported ROSA version is 4.10."
			SCRIPT_STATUS=29
			return $SCRIPT_STATUS
 		fi
		log " DEPLOY_CP4D: $DEPLOY_CP4D"
		export ROSA="true"
		if [[ $DEPLOY_CP4D == "true" ]]; then
			SCRIPT_STATUS=30
			return $SCRIPT_STATUS
		fi
	fi

}
