#!/bin/bash
log "DEPLOY_REGION=$DEPLOY_REGION VPC_ID=$VPC_ID"
CIDR_BLOCKS=`aws ec2 describe-subnets --region $DEPLOY_REGION \
    --filter Name=vpc-id,Values=$VPC_ID "Name=default-for-az,Values=false" "Name=map-public-ip-on-launch,Values=false"  \
    --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text`
if [[ -z $CIDR_BLOCKS ]]; then
    log "SUBNETS with default-for-az=false (non-default) not found, check for default"
    CIDR_BLOCKS=`aws ec2 describe-subnets --region $DEPLOY_REGION \
        --filter Name=vpc-id,Values=$VPC_ID \
        --query "Subnets[*].{CIDR_BLOCKS:CidrBlock}" --output=text`
fi

if [[ -n $CIDR_BLOCKS ]]; then
    length=0
    for CIDR_BLOCK in $CIDR_BLOCKS; do
        length=$((length+1))
    done
    if [ "$length" -ge 3 ]; then
        log "There are atleast 3 subnets"
        length=0
        for EACH_CIDR_BLOCK in $CIDR_BLOCKS; do
            array[$length]="$EACH_CIDR_BLOCK"
            length=$((length+1))
        done
        export CIDR_BLOCKS_0=${array[0]}
        export CIDR_BLOCKS_1=${array[1]}
        export CIDR_BLOCKS_2=${array[2]} 
        log "CIDR_BLOCKS_0=$CIDR_BLOCKS_0 CIDR_BLOCKS_1=$CIDR_BLOCKS_1 CIDR_BLOCKS_2=$CIDR_BLOCKS_2"        
    else
        log "Atleast 3 subnets required, VPC ID $VPC_ID has less than 3 subnets"
        SCRIPT_STATUS=44
        exit $SCRIPT_STATUS
    fi
else
    log "Subnets not found for the given VPC ID $VPC_ID"
    SCRIPT_STATUS=44
    exit $SCRIPT_STATUS
fi

VPC_CIDR_BLOCK=`aws ec2 describe-vpcs  --vpc-ids $VPC_ID --query "Vpcs[*].{VPC_CIDR_BLOCK:CidrBlock}" --output=text`
log "VPC_CIDR_BLOCK=${VPC_CIDR_BLOCK}"	