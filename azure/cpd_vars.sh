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

export OCP_URL=https://api.masocp-igycll.masblrdomain.com:6443
export OPENSHIFT_TYPE=self-managed
export IMAGE_ARCH=amd64
export OCP_USERNAME=masocpuser
export OCP_PASSWORD=mascll104032igy
export OCP_TOKEN=sha256~0jqWJdtt1XVxeeGH7AZ8cUf9l30ZmlcvaqabNaRbNUg


# ------------------------------------------------------------------------------
# Projects
# ------------------------------------------------------------------------------

export PROJECT_CPFS_OPS=ibm-common-services
export PROJECT_CPD_OPS=ibm-cpd-operators-igycll
export PROJECT_CATSRC=openshift-marketplace
export PROJECT_CPD_INSTANCE=ibm-cpd-igycll
# export PROJECT_TETHERED=<enter the tethered project>


# ------------------------------------------------------------------------------
# Storage
# ------------------------------------------------------------------------------

export STG_CLASS_BLOCK=managed-premium
export STG_CLASS_FILE=azurefiles-premium

# ------------------------------------------------------------------------------
# IBM Entitled Registry
# ------------------------------------------------------------------------------

export IBM_ENTITLEMENT_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJJQk0gTWFya2V0cGxhY2UiLCJpYXQiOjE2NDQ0MDk0MjIsImp0aSI6IjYwNzc2MzQzOGJhODQxMmNiZGRhNzVmNWM2MGEwNjIxIn0.A-9DGN1PAmw7x0opnrJnUpwhvfnsf2f-HAUByEWaLWY


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

export VERSION=4.6.3


# ------------------------------------------------------------------------------
# Components
# ------------------------------------------------------------------------------
# Set the following variable if you want to install or upgrade multiple components at the same time.
#
# To export the variable, you must uncomment the command.

# export COMPONENTS=cpfs,scheduler,cpd_platform,<component-ID>