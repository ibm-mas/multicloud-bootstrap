#!/bin/bash

. helper.sh
export -f log

SCRIPT_STATUS=0
declare -A op_versions
op_versions['MongoDBCommunity']=4.1.9
op_versions['Db2uCluster']=11.4
op_versions['kafkas.kafka.strimzi.io']=2.4.9
op_versions['ocpVersion48']='^4\.([8])(\.[0-9]+.*)*$'
op_versions['ocpVersion410']='^4\.([1][0])?(\.[0-9][0-9]+.*)*$'
op_versions['ocpVersion411']='^4\.([1][1])?(\.[0-9][0-9]+.*)*$'
op_versions['rosaVersion']='^4\.([1][0])?(\.[0-9]+.*)*$'
op_versions['cpd-platform-operator']=2.0.7
op_versions['user-data-services-operator']=2.0.6
op_versions['ibm-cert-manager-operator']=3.19.9
op_versions['ibm-sls']=3.3.9
op_versions['service-binding-operator']=1.0.9

declare -A op_namespaces=~
op_namespaces['cpd-platform-operator']='CPD_OPERATORS_NAMESPACE'
op_namespaces['ibm-sls']='SLS_NAMESPACE'
op_namespaces['MongoDBCommunity']='MONGODB_NAMESPACE'
op_namespaces['kafkas.kafka.strimzi.io']='KAFKA_NAMESPACE'

declare -A instance_names=~
instance_names['cpd-platform-operator']='ibmcpd'
instance_names['user-data-services-operator']='analyticsproxy'
instance_names['MongoDBCommunity']='mas-mongo-ce'
instance_names['kafkas.kafka.strimzi.io']='maskafka'
instance_names['Db2uCluster']='db2wh-db01'
instance_names['ibm-cert-manager-operator']='default'

checkROSA(){
	rosa_cm=$(oc get cm rosa-brand-logo -n openshift-config | awk  'NR==2 {print $2 }')
	if [[ $rosa_cm -eq 1 ]]; then
		log " ROSA Cluster "
		currentOpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
		log " OCP version is $currentOpenshiftVersion"
		if [[ $currentOpenshiftVersion =~ ${op_versions[rosaVersion]} ]]; then
    		log " ROSA Cluster Supported Version"
  		else
    		log " Unsupported ROSA version $currentOpenshiftVersion. Supported ROSA version is 4.10.x"
			export SERVICE_NAME=" Unsupported ROSA version $currentOpenshiftVersion. Supported ROSA version is 4.10.x"
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

function getOCPVersion() {
	currentOpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
	log " OCP version is $currentOpenshiftVersion"
	if [[ ${currentOpenshiftVersion} =~ ${op_versions[ocpVersion410]} ]]; then
    	log " OCP Supported Version"
	elif [[ ${currentOpenshiftVersion} =~ ${op_versions[ocpVersion411]} ]]; then
		log " OCP Version Not Supported"
		#log " DEPLOY_CP4D: $DEPLOY_CP4D"
		#if [[ $DEPLOY_CP4D == "true" ]]; then
			SCRIPT_STATUS=29
			export SERVICE_NAME=" MAS+CP4D offering is not supported on OCP 4.11.x"
			return $SCRIPT_STATUS
		#fi

  	else
    	log " Unsupported Openshift version $currentOpenshiftVersion. Supported OpenShift versions are 4.8.x and 4.10.x"
		export SERVICE_NAME=" Unsupported Openshift version $currentOpenshiftVersion. Supported OpenShift versions are 4.8.x and 4.10.x"
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
		export SERVICE_NAME=" Minimum Worker Node requirement not satisfied"
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
	fi

	for i in "${x[@]}"
	do
		cpu=$(oc get -o template nodes "$i" --template={{.status.allocatable.cpu}})
		memory=$(oc get -o template nodes "$i" --template={{.status.allocatable.memory}})

		requiredCPU='^([0]?[0-7])$'
		requiredCPU1='^([0]?[0-6][0-9]{0,3}m)$'

		log " Worker Node : ${i}"
		log " CPU : ${cpu}"
		log " Memory : ${memory}"

		if [[ $ROSA == "true" ]]; then
			memory=${memory::-1}
		else
			memory=${memory::-2}
		fi
		
		if [[ (${cpu} =~ ${requiredCPU} || ${cpu} =~ ${requiredCPU1}) ||  (${memory} -lt 31000000) ]]; then
			log " Minimum CPU/Memory requirements not satisfied"
			export SERVICE_NAME=" Minimum CPU/Memory requirements not satisfied"
			SCRIPT_STATUS=29
			return $SCRIPT_STATUS
		fi		

	done;
	log " Minimum CPU requirement satisfied"
	log " Minimum Memory requirement satisfied"
}


function getOCS() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	sc_name=$(oc get sc | grep ocs-storagecluster-cephfs | awk -F' ' '{print $1}')
	log " OCS StorageClass : $sc_name"
	if [[ $check_for_csv_success != "Succeeded" && $sc_name = ""  ]]; then
		log " OCS StorageClass is not available"
		export SERVICE_NAME=" OCS Storage is not available"
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
	else
		log " OCS StorageClass is available"
    fi    
	
}

function getazurefile() {
	sc_name=$(oc get sc | grep azurefiles-premium | awk -F' ' '{print $1}')
	log " azurefiles-premium StorageClass : $sc_name"
	if [[ $sc_name = ""  ]]; then
		log " azurefiles-premium StorageClass is not available"
		SCRIPT_STATUS=29
		export SERVICE_NAME=" azurefiles-premium Storage is not available"
		return $SCRIPT_STATUS
	else
		log " azurefiles-premium StorageClass is available"
    fi    
	
}

function getOPNamespace() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	no_of_csv=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  |  wc -l)
	
	if [ "$no_of_csv"  -gt 1 ]; then
		log " Multiple ${1} installed."
		export SERVICE_NAME=" Multiple ${1} installed"
		SCRIPT_STATUS=29
		return $SCRIPT_STATUS
	elif [[ $check_for_csv_success = "Succeeded" ]]; then
		op_namespace=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $1}')
		op_version=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $2}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
		log " $1 version is $op_version"
		if [[ $op_version > ${op_versions[${1}]} ]]; then
			#log " $op_namespace"
			log " $1 Supported Version"
			if [[  ${op_namespaces[${1}]} ]]; then
				export ${op_namespaces[${1}]}=$op_namespace
			fi
			if [[  $1 = "ibm-sls" ]]; then
				instance=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq -j '.items | length')
				if [[ $instance > 1 ]]; then
					log " $1 - Multiple Instances are available"
					SCRIPT_STATUS=29
					export SERVICE_NAME=" $1 - Multiple Instances are available"
					return $SCRIPT_STATUS
				fi
				SLS_INSTANCE=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].metadata.name -r)
				if [[  $SLS_INSTANCE != "null"  ]]; then
					log " SLS Instance Present"
					export SLS_INSTANCE_NAME=$SLS_INSTANCE
					export SLS_REGISTRATION_KEY=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.registrationKey -r)
					export SLS_LICENSE_ID=$(oc get LicenseService  -n $SLS_NAMESPACE -o json | jq .items[0].status.licenseId -r)

					log " Debug: Existing SLS Details."
					log " SLS_REGISTRATION_KEY: $SLS_REGISTRATION_KEY"
					log " SLS_INSTANCE_NAME=$SLS_INSTANCE_NAME"
					log " SLS_LICENSE_ID=$SLS_LICENSE_ID"
				fi
			elif  [[  $1 = "cpd-platform-operator" ]]; then
				instance=$(oc get ibmcpd --all-namespaces -o json | jq -j '.items | length')
				if [[ $instance > 1 ]]; then
					log " $1 - Multiple Instances are available"
					SCRIPT_STATUS=29
					export SERVICE_NAME=" $1 - Multiple Instances are available"
					return $SCRIPT_STATUS
				fi
				INSTANCE=$(oc get ibmcpd --all-namespaces -o json | jq .items[0].metadata.namespace -r)
				INSTANCE_NAME=$(oc get ibmcpd --all-namespaces -o json | jq .items[0].metadata.name -r)

				log " $1 Instance Name : $INSTANCE_NAME"
				if [[  $INSTANCE != "null" ]]; then
					if [[  ${instance_names[${1}]} && (${instance_names[${1}]} = "$INSTANCE_NAME") ]]; then
						log " CP4D Instance Present"
						export CPD_INSTANCE_NAMESPACE=$INSTANCE
					else
						log " Instance Name for ${1} is not matching."
						SCRIPT_STATUS=29
						export SERVICE_NAME=" Instance Name for ${1} is not matching"
						return $SCRIPT_STATUS
					fi
				else
					log " $1 New instance Will Be Created"	
				fi
			elif  [[  $1 = "user-data-services-operator" ]]; then
				instance=$(oc get analyticsproxies --all-namespaces -o json | jq -j '.items | length')
				if [[ $instance > 1 ]]; then
					log " $1 - Multiple Instances are available"
					SCRIPT_STATUS=29
					export SERVICE_NAME=" $1 - Multiple Instances are available"
					return $SCRIPT_STATUS
				fi

				INSTANCE_NAME=$(oc get analyticsproxies --all-namespaces -o json | jq .items[0].metadata.name -r)
				log " $1 Instance Name : $INSTANCE_NAME"
				if [[  $INSTANCE_NAME != "null" ]]; then
					if [[  ${instance_names[${1}]} && (${instance_names[${1}]} = "$INSTANCE_NAME") ]]; then
						log " UDS Instance Present"
					else
						log " Instance Name for ${1} is not matching."
						SCRIPT_STATUS=29
						export SERVICE_NAME=" Instance Name for ${1} is not matching"
						return $SCRIPT_STATUS
					fi
				else
					log " $1 New instance Will Be Created"
				fi	
			elif  [[  $1 = "ibm-cert-manager-operator" ]]; then
				instance=$(oc get CertManager --all-namespaces -o json | jq -j '.items | length')
				if [[ $instance > 1 ]]; then
					log " $1 - Multiple Instances are available"
					SCRIPT_STATUS=29
					export SERVICE_NAME=" $1 - Multiple Instances are available"
					return $SCRIPT_STATUS
				fi

				INSTANCE_NAME=$(oc get CertManager --all-namespaces -o json | jq .items[0].metadata.name -r)
				log " $1 Instance Name : $INSTANCE_NAME"
				if [[  $INSTANCE_NAME != "null" ]]; then
					if [[  ${instance_names[${1}]} && (${instance_names[${1}]} = "$INSTANCE_NAME") ]]; then
					log " CertManager Instance Present"
					else
						log " Instance Name for ${1} is not matching."
						SCRIPT_STATUS=29
						export SERVICE_NAME=" Instance Name for ${1} is not matching"
						return $SCRIPT_STATUS
					fi
				else
					log " $1 New instance Will Be Created"	
				fi
			fi
		else
			log " Unsupported ${1} version $op_version."
			SCRIPT_STATUS=29
			export SERVICE_NAME=" Unsupported ${1} version $op_version"
			return $SCRIPT_STATUS
		fi
    else
		log " $1 will be installed."
	fi
}

function getVersion() {
	instance=$(oc get $1 --all-namespaces  --output json | jq -j '.items | length')
	if [[ $instance > 1 ]]; then
		log " $1 - Multiple Instances are available"
		SCRIPT_STATUS=29
		export SERVICE_NAME=" $1 - Multiple Instances are available"
		return $SCRIPT_STATUS
	fi

	namespace=$(oc get $1  --all-namespaces | awk  'NR==2 {print $1 }')
	if [[ $namespace = "" ]]; then
		log " $1 will be installed."
		return
	fi
	currentVersion=$(oc get $1 -n ${namespace}  -o json | jq .items[0].spec.version -r)
	log " $1 version is $currentVersion"
	if [[ $currentVersion > ${op_versions[${1}]} ]]; then
		log " $1 Supported Version"
		instance_name=$(oc get $1 -n ${namespace}  -o json | jq .items[0].metadata.name -r)
		log " $1 Instance Name : $instance_name"
		if [[  ${instance_names[${1}]} && ${instance_names[${1}]} = "$instance_name" ]]; then
			if [[  ${op_namespaces[${1}]} ]]; then
				export ${op_namespaces[${1}]}=$namespace
			fi
		else 
			log " Instance Name for ${1} is not matching."
			SCRIPT_STATUS=29
			export SERVICE_NAME=" Instance Name for ${1} is not matching"
			return $SCRIPT_STATUS
		fi
  	else
    	log " Unsupported ${1} version $currentVersion."
		SCRIPT_STATUS=29
		export SERVICE_NAME=" Unsupported ${1} version $currentVersion"
		return $SCRIPT_STATUS
  	fi
}

function getKafkaVersion() {
	instance=$(oc get kafkas.kafka.strimzi.io --all-namespaces  --output json | jq -j '.items | length')
	if [[ $instance > 1 ]]; then
		log " Multiple $1 Instances are available"
		SCRIPT_STATUS=29
		export SERVICE_NAME=" Multiple $1 Instances are available"
		return $SCRIPT_STATUS
	fi

	namespace=$(oc get kafkas.kafka.strimzi.io  --all-namespaces | awk  'NR==2 {print $1 }')
	if [[ $namespace = "" ]]; then
		log " Kafka will be installed."
		return
	fi
	currentVersion=$(oc get kafkas.kafka.strimzi.io -n ${namespace}  -o json | jq .items[0].spec.kafka.version -r)
	log " Kafka version is $currentVersion"
	if [[ $currentVersion > ${op_versions[kafkas.kafka.strimzi.io]} ]]; then
    	log " Kafka Supported Version"
		instance_name=$(oc get kafkas.kafka.strimzi.io -n ${namespace}  -o json | jq .items[0].metadata.name -r)
		log " $1 Instance Name : $instance_name"
		if [[  ${instance_names[kafkas.kafka.strimzi.io]} && ${instance_names[kafkas.kafka.strimzi.io]} = "$instance_name" ]]; then
			if [[  ${op_namespaces[kafkas.kafka.strimzi.io]} ]]; then
				export ${op_namespaces[kafkas.kafka.strimzi.io]}=$namespace
			fi
		else 
			log " Instance Name for Kafka is not matching."
			SCRIPT_STATUS=29
			export SERVICE_NAME=" Instance Name for Kafka is not matching"
			return $SCRIPT_STATUS	
		fi
  	else
    	log " Unsupported Kafka version $currentVersion."
		SCRIPT_STATUS=29
		export SERVICE_NAME=" Unsupported Kafka version $currentVersion"
		return $SCRIPT_STATUS
  fi
}

# function getSBOVersion() {
# 	currentVersion=$(oc get csv -n default | grep service-binding-operator | awk -F' ' '{print $1}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching)
# 	log " service-binding-operator version is $currentVersion"
# 	if [[ "$currentVersion" -ge ${op_versions[service-binding-operator]} ]]; then
# 		log " SBO Supported Version"
#   	else
#     	log " Unsupported service-binding-operator version $currentVersion."
# 		SCRIPT_STATUS=29
#		export SERVICE_NAME=" Unsupported service-binding-operator version $currentVersion"
# 		return $SCRIPT_STATUS
#   	fi
# }
function getOPVersions() {
	check_for_csv_success=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $NF}')
	if [[ $check_for_csv_success = "Succeeded" ]]; then
		op_namespace=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $1}')
		op_version=$(oc get csv  --all-namespaces | awk -v pattern="$1" '$2 ~ pattern  { print }'  | awk -F' ' '{print $2}' |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
		log " $1 version is $op_version"
	fi
}

function getMongoVersion() {
	namespace=$(oc get $1  --all-namespaces | awk  'NR==2 {print $1 }')
	currentVersion=$(oc get $1 -n ${namespace}  -o json | jq .items[0].spec.version -r)
	log " $1 version is $currentVersion"
}