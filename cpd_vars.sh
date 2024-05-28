#===============================================================================
# Cloud Pak for Data installation variables
#===============================================================================

# ------------------------------------------------------------------------------
# Cluster
# ------------------------------------------------------------------------------

export OCP_URL=https:\/\/api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
export OPENSHIFT_TYPE=self-managed
export IMAGE_ARCH=amd64
export OCP_USERNAME=$OCP_USERNAME
export OCP_PASSWORD=$OCP_PASSWORD
export SERVER_ARGUMENTS="--server=${OCP_URL}"
export LOGIN_ARGUMENTS="--username=${OCP_USERNAME} --password=${OCP_PASSWORD}"
# export LOGIN_ARGUMENTS="--token=${OCP_TOKEN}"
export CPDM_OC_LOGIN="cpd-cli manage login-to-ocp ${SERVER_ARGUMENTS} ${LOGIN_ARGUMENTS}"
export OC_LOGIN="oc login ${OCP_URL} ${LOGIN_ARGUMENTS}"
# ------------------------------------------------------------------------------
# Projects
# ------------------------------------------------------------------------------

export PROJECT_CPFS_OPS=ibm-common-services
export PROJECT_CPD_OPS=ibm-cpd-operators-${RANDOM_STR}
export PROJECT_CATSRC=openshift-marketplace
export PROJECT_CPD_INSTANCE=ibm-cpd-${RANDOM_STR}
export PROJECT_CPD_INST_OPERATORS=${PROJECT_CPD_OPS}
export PROJECT_CPD_INST_OPERANDS=${PROJECT_CPD_INSTANCE}
# export PROJECT_TETHERED=<enter the tethered project>



# ------------------------------------------------------------------------------
# IBM Entitled Registry
# ------------------------------------------------------------------------------

export IBM_ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY

# ------------------------------------------------------------------------------
# Cloud Pak for Data version
# ------------------------------------------------------------------------------

export VERSION=$CPD_PRODUCT_VERSION
# ------------------------------------------------------------------------------
# Private container registry
# ------------------------------------------------------------------------------
# Set the following variables if you mirror images to a private container registry.
#
# To export these variables, you must uncomment each command in this section.

export PRIVATE_REGISTRY_LOCATION=cp.icr.io/cp
export PRIVATE_REGISTRY_PUSH_USER=cp
export PRIVATE_REGISTRY_PUSH_PASSWORD=$IBM_ENTITLEMENT_KEY
export PRIVATE_REGISTRY_PULL_USER=cp
export PRIVATE_REGISTRY_PULL_PASSWORD=$IBM_ENTITLEMENT_KEY
# ------------------------------------------------------------------------------
# Components
# ------------------------------------------------------------------------------
# Set the following variable if you want to install or upgrade multiple components at the same time.
#
# To export the variable, you must uncomment the command.

# export COMPONENTS=cpfs,scheduler,cpd_platform,<component-ID>
log "Below are parameters used for cp4d-db2wh service install specific deployment parameters,"
log " OCP_URL: $OCP_URL"
log " OPENSHIFT_TYPE: $OPENSHIFT_TYPE"
log " OCP_USERNAME: $OCP_USERNAME"
log " CP4D operator instance : $PROJECT_CPFS_OPS"
log " CP4D instance: $PROJECT_CPD_INSTANCE"
log " CP4D Version : $VERSION"

echo $OCP_URL
echo $OPENSHIFT_TYPE
echo $IMAGE_ARCH
echo $OCP_USERNAME
echo $PROJECT_CPFS_OPS
echo $PROJECT_CPD_OPS
echo $PROJECT_CATSRC
echo $PROJECT_CPD_INSTANCE
echo $VERSION

if [[ -n $OCP_URL && -n $$OCP_USERNAME && -n $OCP_PASSWORD && -n $VERSION ]]; then
  log "Logging into the cluster,"
  cpd-cli manage login-to-ocp --username=${OCP_USERNAME}  --password=${OCP_PASSWORD} --server=${OCP_URL}
   log "Creating  the OLM objects for Db2 Warehouse,"
  cpd-cli manage apply-olm --release=${VERSION} --cpd_operator_ns=${PROJECT_CPD_OPS} --components=db2wh
   log "custom resource for Db2 Warehouse & Installing the service,"
  cpd-cli manage apply-cr --components=db2wh --release=${VERSION} --cpd_instance_ns=${PROJECT_CPD_INSTANCE} --license_acceptance=true
    log "Validating the installation"
  cpd-cli manage get-cr-status --cpd_instance_ns=${PROJECT_CPD_INSTANCE} --components=db2wh
fi