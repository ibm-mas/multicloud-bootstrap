. ./script-functions.bash
. helper.sh
export -f log

# OCP
OpenshiftVersion=$(oc get clusterversion | awk  'NR==2 {print $2 }')
log " OCP version is $OpenshiftVersion"

# Cloud Pak foundation services
cpfs_version=$(oc get subscription ibm-common-service-operator -n ibm-common-services  -o json | jq .status.installedCSV -r |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
log " Foundational services version is $cpfs_version" 

# CP4D (if installed)
# Cert Manager
# SLS
# DRO
VersionsArray=( ibm-cert-manager-operator user-data-services-operator cpd-platform-operator ibm-sls )

 for val in ${VersionsArray[@]}; do
   if [[ $val == "cpd-platform-operator" ]]; then
     if [[ $DEPLOY_CP4D == "true" ]]; then
        getOPVersions $val
     fi
   else
     getOPVersions $val
   fi     
done

#log "MONGO_FLAVOR=$MONGO_FLAVOR and MONGO_USE_EXISTING_INSTANCE=$MONGO_USE_EXISTING_INSTANCE"

if [[ (-z $MONGO_USE_EXISTING_INSTANCE && -z $MONGO_FLAVOR) || ($MONGO_FLAVOR == "MongoDB" && $MONGO_USE_EXISTING_INSTANCE == "false" )  ]]; then
	# MongoDB new
	getMongoVersion MongoDBCommunity
elif [[ ($MONGO_FLAVOR == "MongoDB" && $MONGO_USE_EXISTING_INSTANCE == "true") ]]; then 
  # MongoDB existing
	log "MAS Provisioned with an existing MongoDB instance"
elif [[ ($MONGO_FLAVOR == "Amazon DocumentDB" && $MONGO_USE_EXISTING_INSTANCE == "false") ]]; then 
  # Docdb new
	log "MAS Provisioned with a new instance of Amazon DocumentDB"	
elif [[ ($MONGO_FLAVOR == "Amazon DocumentDB" && $MONGO_USE_EXISTING_INSTANCE == "true") ]]; then 
  # Docdb existing
	log "MAS Provisioned with an existing Amazon DocumentDB"
fi

# MAS
mas_version=$(oc get subscription ibm-mas-operator -n mas-$MAS_INSTANCE_ID-core  -o json | jq .status.installedCSV -r |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
log " MAS version is $mas_version" 

# Manage (if installed)
if [[ $DEPLOY_MANAGE == "true" ]]; then
  manage_version=$(oc get subscription ibm-mas-manage -n mas-$MAS_INSTANCE_ID-$MAS_APP_ID  -o json | jq .status.installedCSV -r |  grep --perl-regexp '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' --only-matching )
  log " Manage version is $manage_version"
fi