#!/bin/bash
# Script to delete S3 buckets on AWS.
# This script will delete S3 buckets which got created as part of MAS deployment from all the regions configured in `DELETE_S3_REGIONS` variable.
# The script will fetch S3 buckets which are atleast 24 hours old. This is to prevent deleting S3 buckets which has an associated MAS deployment currently in-progress

# Configured regions from where S3 buckets will be deleted
DELETE_S3_REGIONS=("us-east-1" "us-east-2" "us-west-2" "ap-east-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "eu-central-1" "ap-south-1" "ap-northeast-2" "ap-northeast-3" "ca-central-1" "eu-south-1" "eu-west-1" "eu-west-2" "eu-west-3" "eu-north-1" "af-south-1" "me-south-1" "sa-east-1")
echo "======================================================"
echo "DELETE_S3_REGIONS=${DELETE_S3_REGIONS[@]}"
echo "======================================================" 
date=$(date -d "24 hours ago" '+%Y-%m-%d')
echo "Fetch S3 buckets till $date date (current_day - 1 day)"
echo "======================================================"
S3BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `masocp-`) == `true` && ( CreationDate<=`'"$date"'` )].[Name]' --output text)
echo "S3BUCKETS which contains 'masocp-' = $S3BUCKETS"
echo "======================================================"
for S3BUCKET in $S3BUCKETS; do
    REGION=$(aws s3api get-bucket-location --bucket $S3BUCKET | jq -r '.LocationConstraint' )
    if [[ " ${DELETE_S3_REGIONS[@]} " =~ " ${REGION} " ]]; then
        echo "S3BUCKET TO BE DELETED $S3BUCKET AND ITS REGION=${REGION}  "
        aws s3 rb s3://$S3BUCKET --force --region $REGION
    elif [[ -z "$REGION" || "$REGION" == 'null' ]]; then
        echo "S3BUCKET TO BE DELETED $S3BUCKET AND ITS REGION=${REGION}  "
        aws s3 rb s3://$S3BUCKET --force  
    fi
done
echo "======================================================"
S3BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `cf-templates-`) == `true` && ( CreationDate<=`'"$date"'` )].[Name]' --output text)
echo "S3BUCKETS which contains 'cf-templates-' = $S3BUCKETS"
echo "======================================================"
for S3BUCKET in $S3BUCKETS; do
    REGION=$(aws s3api get-bucket-location --bucket $S3BUCKET | jq -r '.LocationConstraint' )
    if [[ " ${DELETE_S3_REGIONS[@]} " =~ " ${REGION} " ]]; then
        echo "S3BUCKET TO BE DELETED $S3BUCKET AND ITS REGION=${REGION}  "
        aws s3 rb s3://$S3BUCKET --force --region $REGION
    elif [[ -z "$REGION" || "$REGION" == 'null' ]]; then
        echo "S3BUCKET TO BE DELETED $S3BUCKET AND ITS REGION=${REGION}  "
        aws s3 rb s3://$S3BUCKET --force  
    fi
done
echo "======================================================"