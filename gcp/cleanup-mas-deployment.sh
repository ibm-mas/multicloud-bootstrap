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
  echo " PROJECT_ID - Project ID where OpenShift cluster is created."
  echo " UNIQUE_STR - Unique string using which the OpenShift resource group to be deleted."
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -p mas-project -u dgt67h"
  exit 1
}

# Read arguments
if [[ $# -eq 0 ]]; then
  echo "No arguments provided with $0. Exiting.."
  usage
else
  while getopts 'p:u:?h' c; do
    case $c in
    p)
      PROJECT_ID=$OPTARG
      ;;
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
echo " Project ID = $PROJECT_ID"
echo " Unique string = $UNIQUE_STR"

# Check for supported region
if [[ (-z $PROJECT_ID) || (-z $UNIQUE_STR) ]]; then
  echo "ERROR: Missing parameters"
  usage
fi

echo "==== Execution started at `date` ===="
echo "---------------------------------------------"

## Delete virtual machines instances
echo "Checking for virtual machines"
# Get virtual machine list
INSTANCES=$(gcloud compute instances list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "INSTANCES = $INSTANCES"
if [[ -n $INSTANCES ]]; then
  echo "Virtual instances found for this MAS instance"
  for inst in $INSTANCES; do
    # Get the zone details
    ZONE=$(gcloud compute instances list --format=json --filter="name=$inst" | jq ".[].zone" | tr -d '"' | cut -d '/' -f 9)
    echo "VM name: $inst Zone:$ZONE"
    gcloud compute instances delete $inst --delete-disks=all --project=$PROJECT_ID --zone=$ZONE --quiet &
  done
  # Wait until all the VMs are deleted
  while [ "$INSTANCES" != "" ]; do
    sleep 60
    INSTANCES=$(gcloud compute instances list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
    if [[ -n "$INSTANCES" ]]; then
      echo "Virtual instances still exist: $INSTANCES"
      continue
    else
      echo "All virtual instances deleted"
      break
    fi
  done
fi

# Delete forwarding rules
echo "Checking for forwarding rules"
# Get forwarding rule list
FRS=$(gcloud compute forwarding-rules list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "FRS = $FRS"
if [[ -n $FRS ]]; then
  echo "Forwarding rules found for this MAS instance"
  for inst in $FRS; do
    # Get the forwarding rule details
    REG=$(gcloud compute forwarding-rules list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
    echo "Forwarding rule name: $inst Region:$REG"
    gcloud compute forwarding-rules delete $inst --region=$REG --quiet
  done
fi

# Delete internal load balancers
echo "Checking for internal load balancers"
# Get internal load balancer list
LBS=$(gcloud compute backend-services list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "LBS = $LBS"
if [[ -n $LBS ]]; then
  echo "Internal load balancers found for this MAS instance"
  for inst in $LBS; do
    # Get the internal load balancer details
    REG=$(gcloud compute backend-services list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
    echo "Internal LB name: $inst Region:$REG"
    gcloud compute backend-services delete $inst --region=$REG --quiet
  done
fi

# Delete target pools
echo "Checking for target pools"
# Get target pool list
TPS=$(gcloud compute target-pools list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "TPS = $TPS"
if [[ -n $TPS ]]; then
  echo "Target pools found for this MAS instance"
  for inst in $TPS; do
    # Get the target pools details
    REG=$(gcloud compute target-pools list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
    echo "Target pool name: $inst Region:$REG"
    gcloud compute target-pools delete $inst --region=$REG --quiet
  done
fi

# Delete instance groups
echo "Checking for instance groups"
# Get instance group list
IGS=$(gcloud compute instance-groups list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "IGS = $IGS"
if [[ -n $IGS ]]; then
  echo "Internal instance groups found for this MAS instance"
  for inst in $IGS; do
    # Get the instance group details
    ZONE=$(gcloud compute instance-groups list --format=json --filter="name=$inst" | jq ".[].zone" | tr -d '"' | cut -d '/' -f 9)
    echo "Instance group: $inst Zone:$ZONE"
    gcloud compute instance-groups unmanaged delete $inst --zone=$ZONE --quiet
  done
fi

# Delete cloud storage buckets
echo "Checking for cloud storage buckets"
# Get cloud storage bucket list
CSBTS=$(gcloud storage buckets list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "CSBTS = $CSBTS"
if [[ -n $CSBTS ]]; then
  echo "Cloud storage buckets found for this MAS instance"
  for inst in $CSBTS; do
    echo "Cloud storage bucket: $inst"
    gcloud storage rm --recursive gs://$inst --quiet
  done
fi

# Delete IP addresses
echo "Checking for IP addresses"
# Get IP address list
IPS=$(gcloud compute addresses list --format=json --filter="name~$UNIQUE_STR" | jq ".[].name" | tr -d '"')
echo "IPS = $IPS"
if [[ -n $IPS ]]; then
  echo "IP addresses found for this MAS instance"
  for inst in $IPS; do
    # Get the IP address details
    REG=$(gcloud compute addresses list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
    echo "IP address name: $inst Region:$REG"
    gcloud compute addresses delete $inst --region=$REG --quiet
  done
fi

# Delete virtual network
echo "Checking for virtual network"
NWS=$(gcloud compute networks list --format=json | jq ".[] | select(.name | contains(\"$UNIQUE_STR\")).name" | tr -d '"')
echo "NWS = $NWS"
if [[ -n $NWS ]]; then
  echo "Virtual networks found for this MAS instance"

  # Delete firewall rules
  echo "Checking for firewall rules for this VPC"
  # Get firewall rule list
  FRS=$(gcloud compute firewall-rules list --format=json --filter="network=https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/global/networks/$NWS" | jq ".[].name" | tr -d '"')
  echo "FRS = $FRS"
  if [[ -n $FRS ]]; then
    echo "Firewall rules found for this MAS instance"
    for inst in $FRS; do
      echo "Firewall rule: $inst"
      gcloud compute firewall-rules delete $inst --quiet
    done
  fi

  # Delete routers
  echo "Checking for routers for this VPC"
  # Get router list
  RTRS=$(gcloud compute routers list --format=json --filter="network=https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/global/networks/$NWS" | jq ".[].name" | tr -d '"')
  echo "RTRS = $RTRS"
  if [[ -n $RTRS ]]; then
    echo "Routers found for this MAS instance"
    for inst in $RTRS; do
      # Get the router details
      REG=$(gcloud compute routers list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
      echo "Router: $inst Region:$REG"
      gcloud compute routers delete $inst --region=$REG --quiet
    done
  fi

  # Delete subnets
  echo "Checking for subnets for this VPC"
  # Get subnet list
  SBNTS=$(gcloud compute networks subnets list --format=json --filter="network=https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/global/networks/$NWS" | jq ".[].name" | tr -d '"')
  echo "SBNTS = $SBNTS"
  if [[ -n $SBNTS ]]; then
    echo "Subnets found for this MAS instance"
    for inst in $SBNTS; do
      # Get the subnet details
      REG=$(gcloud compute networks subnets list --format=json --filter="name=$inst" | jq ".[].region" | tr -d '"' | cut -d '/' -f 9)
      echo "Subnet: $inst Region: $REG"
      gcloud compute networks subnets delete $inst --region=$REG --quiet
    done
  fi

  # Delete VPC
  gcloud compute networks delete $NWS --quiet
fi
echo "==== Execution completed at `date` ===="
