#!/bin/bash
SCRIPT_STATUS=0
if [[ -f "/tmp/iam-user-created" ]]; then
    log "mongo/docdb/docdb-create-iam-user.sh : /tmp/iam-user-created exists; docdb-create-iam-user.sh skipped ..."
else 
    log "mongo/docdb/docdb-create-iam-user.sh : /tmp/iam-user-created not exists"
    log "mongo/docdb/docdb-create-iam-user.sh: .......... starts"
    # IAM variables
    IAM_POLICY_NAME="masocp-policy-${RANDOM_STR}"
    IAM_USER_NAME="masocp-user-${RANDOM_STR}"
    ## IAM # Create IAM policy
    cd $GIT_REPO_HOME/aws
    policyarn=$(aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://${GIT_REPO_HOME}/aws/iam/policy.json | jq '.Policy.Arn' | tr -d "\"")
    # Create IAM user
    aws iam create-user --user-name ${IAM_USER_NAME}
    aws iam attach-user-policy --user-name ${IAM_USER_NAME} --policy-arn $policyarn
    
    if [ $? -ne 0 ]; then
        SCRIPT_STATUS=36
    fi
    accessdetails=$(aws iam create-access-key --user-name ${IAM_USER_NAME})
    export AWS_ACCESS_KEY_ID=$(echo $accessdetails | jq '.AccessKey.AccessKeyId' | tr -d "\"")
    export AWS_SECRET_ACCESS_KEY=$(echo $accessdetails | jq '.AccessKey.SecretAccessKey' | tr -d "\"")

    aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
    aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    aws configure set default.region $DEPLOY_REGION

    if [ $? -ne 0 ]; then
        SCRIPT_STATUS=36
    fi
    log "mongo/docdb/docdb-create-iam-user.sh: .......... AWS_ACCESS_KEY_ID:DEPLOY_REGION : $DEPLOY_REGION"
    # on successful completion of docdb-create-iam-user.sh, create a file 
    echo "COMPLETE" > /tmp/iam-user-created
    chmod a+rw /tmp/iam-user-created
    # Put some delay for IAM permissions to be applied in the backend
    sleep 60
    log "mongo/docdb/docdb-create-iam-user.sh: .......... ends"

fi


