#!/bin/bash
# Script to cleanup the MAS deployment on GCP.
# It will cleanup all the below resources that get created during the deployment.
#
# Parameters:
#   -u UNIQUE_STR: Unique string using which the OpenShift resource group to be deleted.
#     This is an required parameter.

# Fail the script if any of the steps fail
set -e

# Functions
usage() {
  echo "Usage: cleanup-mas-deployment.sh -u UNIQUE_STR"
  echo " "
  echo "Parameters"
  echo " UNIQUE_STR - Unique string using which the OpenShift resource group to be deleted."
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -u dgt67h"
  exit 1
}

# Read arguments
if [[ $# -eq 0 ]]; then
  echo "No arguments provided with $0. Exiting.."
  usage
else
  while getopts 'u:?h' c; do
    case $c in
    u)
      UNIQUE_STR=$OPTARG
      ;;
    h | *)
      usage
      ;;
    esac
  done
fi
echo "Script Inputs:"
echo " Unique string = $UNIQUE_STR"

# Check for supported region
if [[ -z $UNIQUE_STR ]]; then
  echo "ERROR: Parameter 'cluster-name' not provided"
  usage
fi

echo "==== Execution started at `date` ===="
echo "MAS instance unique string: $UNIQ_STR"
echo "---------------------------------------------"

## Delete virtual machines instances
echo "Checking for virtual machines"
# Get virtual machine list
INSTANCES=$(gcloud compute instances list --format=json | jq ".[] | select(.name | contains(\"sp-edge-ipi-1\")).name" | tr -d '"')
echo "INSTANCES = $INSTANCES"
if [[ -n $INSTANCES ]]; then
  echo "Virtual instances found for this MAS instance"
  VM_LIST=""
  for inst in $INSTANCES; do
    VM_LIST="$VM_LIST $inst"
  done
fi
echo "VM_LIST=$VM_LIST"

# Delete virtual network
echo "Checking for virtual network"
NWS=$(gcloud compute networks list --format=json | jq ".[] | select(.name | contains(\"sp-edge-ipi-1\")).name" | tr -d '"')
echo "NWS = $NWS"
if [[ -n $NWS ]]; then
  echo "Virtual networks found for this MAS instance"
fi

echo "==== Execution completed at `date` ===="
