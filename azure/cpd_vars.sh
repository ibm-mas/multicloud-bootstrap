#===============================================================================
# Cloud Pak for Data installation variables
#===============================================================================

# ------------------------------------------------------------------------------
# Client workstation
# ------------------------------------------------------------------------------

# export CPD_CLI_MANAGE_WORKSPACE=<enter a fully qualified directory>
# export OLM_UTILS_LAUNCH_ARGS=<enter launch arguments>


# ------------------------------------------------------------------------------
# Cluster
# ------------------------------------------------------------------------------

export OCP_URL=$OCP_SERVER
export OPENSHIFT_TYPE=self-managed
export IMAGE_ARCH=amd64
export OCP_USERNAME=$OCP_USERNAME
export OCP_PASSWORD=$OCP_PASSWORD
#export OCP_TOKEN=sha256~0jqWJdtt1XVxeeGH7AZ8cUf9l30ZmlcvaqabNaRbNUg


# ------------------------------------------------------------------------------
# Projects
# ------------------------------------------------------------------------------

export PROJECT_CPFS_OPS=ibm-common-services
export PROJECT_CPD_OPS=ibm-cpd-operators-${RANDOM_STR}
export PROJECT_CATSRC=openshift-marketplace
export PROJECT_CPD_INSTANCE=ibm-cpd-${RANDOM_STR}
# export PROJECT_TETHERED=<enter the tethered project>


# ------------------------------------------------------------------------------
# Storage
# ------------------------------------------------------------------------------

export STG_CLASS_BLOCK=managed-premium
export STG_CLASS_FILE=azurefiles-premium

# ------------------------------------------------------------------------------
# IBM Entitled Registry
# ------------------------------------------------------------------------------

export IBM_ENTITLEMENT_KEY=$SLS_ENTITLEMENT_KEY

# ------------------------------------------------------------------------------
# Private container registry
# ------------------------------------------------------------------------------
# Set the following variables if you mirror images to a private container registry.
#
# To export these variables, you must uncomment each command in this section.

# export PRIVATE_REGISTRY_LOCATION=<enter the location of your private container registry>
# export PRIVATE_REGISTRY_PUSH_USER=<enter the username of a user that can push to the registry>
# export PRIVATE_REGISTRY_PUSH_PASSWORD=<enter the password of the user that can push to the registry>
# export PRIVATE_REGISTRY_PULL_USER=<enter the username of a user that can pull from the registry>
# export PRIVATE_REGISTRY_PULL_PASSWORD=<enter the password of the user that can pull from the registry>


# ------------------------------------------------------------------------------
# Cloud Pak for Data version
# ------------------------------------------------------------------------------

export VERSION=$CPD_PRODUCT_VERSION


# ------------------------------------------------------------------------------
# Components
# ------------------------------------------------------------------------------
# Set the following variable if you want to install or upgrade multiple components at the same time.
#
# To export the variable, you must uncomment the command.

# export COMPONENTS=cpfs,scheduler,cpd_platform,<component-ID>


cpd-cli manage login-to-ocp --username=${OCP_USERNAME}  --password=${OCP_PASSWORD} --server=${OCP_URL}
cpd-cli manage apply-olm --release=${VERSION} --cpd_operator_ns=${PROJECT_CPD_OPS} --components=db2wh
cpd-cli manage apply-cr --components=db2wh --release=${VERSION} --cpd_instance_ns=${PROJECT_CPD_INSTANCE} --license_acceptance=true
cpd-cli manage get-cr-status --cpd_instance_ns=${PROJECT_CPD_INSTANCE} --components=db2wh