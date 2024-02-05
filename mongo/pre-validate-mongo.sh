#!/bin/bash
if [[ $CLUSTER_TYPE == "aws" ]]; then
    SCRIPT_STATUS=0


    log " MONGO_USE_EXISTING_INSTANCE=${MONGO_USE_EXISTING_INSTANCE}"
    log " MONGO_FLAVOR=${MONGO_FLAVOR}"
    log " MONGO_ADMIN_USERNAME=${MONGO_ADMIN_USERNAME}"
    #log " MONGO_ADMIN_PASSWORD=${MONGO_ADMIN_PASSWORD}"
    log " MONGO_HOSTS=${MONGO_HOSTS}"
    log " MONGO_CA_PEM_FILE=${MONGO_CA_PEM_FILE}"

    if [[ $MONGO_FLAVOR == "MongoDB" ]]; then
        export RETRY_WRITES="true";
        export MONGODB_PROVIDER="enterprise";
    elif [[ $MONGO_FLAVOR == "Amazon DocumentDB" ]]; then
        export RETRY_WRITES="false";
        export MONGODB_PROVIDER="aws";
    fi
    log "MONGODB RETRY_WRITES=${RETRY_WRITES}"
    log "MONGODB DB_PROVIDER=${MONGODB_PROVIDER}"

    log "==== BOOTNODE_VPC_ID = ${BOOTNODE_VPC_ID}"
    log "==== EXISTING_NETWORK = ${EXISTING_NETWORK}"
    log "==== Existing DocumentDB DOCUMENTDB_VPC_ID = ${DOCUMENTDB_VPC_ID}"

    # Mongo CFT inputs validation and connection test
    if [[ $MONGO_USE_EXISTING_INSTANCE == "true" ]]; then

        if [ -z "$MONGO_ADMIN_USERNAME" ]; then
            log "ERROR: Mongo Admin username is not specified"
            SCRIPT_STATUS=33
            exit $SCRIPT_STATUS
        elif [ -z "$MONGO_ADMIN_PASSWORD" ]; then
            log "ERROR: Mongo Admin password is not specified"
            SCRIPT_STATUS=33
            exit $SCRIPT_STATUS
        elif [ -z "$MONGO_HOSTS" ]; then
            log "ERROR: Mongo Hosts is not specified"
            SCRIPT_STATUS=33
            exit $SCRIPT_STATUS
        elif [ -z "$MONGO_CA_PEM_FILE" ]; then
            log "ERROR: Mongo CA PEM file is not specified"
            SCRIPT_STATUS=33
            exit $SCRIPT_STATUS
        fi

        log "Downloading Mongo CA PEM certificate"
        if [[ ${MONGO_CA_PEM_FILE,,} =~ ^s3 ]]; then
            log "Copy S3 Mongo CA PEM certificate"
            # https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingRouting.html#Redirects
            aws s3 cp "$MONGO_CA_PEM_FILE" $GIT_REPO_HOME/mongo/mongo-ca.pem --region $DEPLOY_REGION
            if [ $? -ne 0 ]; then
                log "s3: Invalid Mongo CA PEM certificate URL"
                SCRIPT_STATUS=34
                exit $SCRIPT_STATUS
            fi
        elif [[ ${MONGO_CA_PEM_FILE,,} =~ ^https? ]]; then
            log "wget Mongo CA PEM certificate"
            wget "$MONGO_CA_PEM_FILE" -O $GIT_REPO_HOME/mongo/mongo-ca.pem
            if [ $? -ne 0 ]; then
                log "wget: Invalid Mongo CA PEM certificate URL"
                SCRIPT_STATUS=34
                exit $SCRIPT_STATUS
            fi
        fi
        # creating the vpc peer only if flavor is Amazon DocDB + existing instance
        if [[ $MONGO_FLAVOR == "Amazon DocumentDB" ]]; then
            if [ -z "$DOCUMENTDB_VPC_ID" ]; then
                log "Prevalidate Mongo : ERROR: Document DB VPC id is not specified"
                SCRIPT_STATUS=33
                exit $SCRIPT_STATUS
            fi

            export ACCEPTER_VPC_ID=${DOCUMENTDB_VPC_ID}
            if [[ -n $BOOTNODE_VPC_ID ]]; then
                log "Prevalidate Mongo : BOOTNODE_VPC_ID=${BOOTNODE_VPC_ID}"
                export REQUESTER_VPC_ID=${BOOTNODE_VPC_ID}
            elif [[ -n $EXISTING_NETWORK ]]; then
                log "Prevalidate Mongo : EXISTING_NETWORK=${EXISTING_NETWORK}"
                export REQUESTER_VPC_ID=${EXISTING_NETWORK}
            else
                log "Prevalidate Mongo : ERROR: BootNode VPC id is not specified"
                SCRIPT_STATUS=43
                exit $SCRIPT_STATUS
            fi
            sh $GIT_REPO_HOME/mongo/docdb/docdb-create-vpc-peer.sh
            SCRIPT_STATUS=$?
            if [ $SCRIPT_STATUS -ne 0 ]; then
                log "Prevalidate Mongo : ERROR: docdb-create-vpc-peer FAILED, exiting"
                exit $SCRIPT_STATUS
            fi
        fi

        log "Prevalidate Mongo : Connecting to the Mongo Database"
        python $GIT_REPO_HOME/mongo/mongo-prevalidate.py
        SCRIPT_STATUS=$?
        if [ $SCRIPT_STATUS -ne 0 ]; then
            log "Prevalidate Mongo : ERROR: Mongo DB URL Validation = FAIL, exiting"
        fi
        exit $SCRIPT_STATUS
    fi

    if [[ $MONGO_FLAVOR == "Amazon DocumentDB" && $MONGO_USE_EXISTING_INSTANCE == "false" ]]; then
        # check if the deploy region supports Amazon DocumentDB
        DOCDB_SUPPORTED_REGIONS="ap-northeast-1;ap-northeast-2;ap-south-1;ap-southeast-1;ap-southeast-2;ca-central-1;eu-central-1;eu-south-1;eu-west-1;eu-west-2;eu-west-3;sa-east-1;us-east-1;us-east-2;us-gov-west-1;us-west-2"
        if [[ ${DOCDB_SUPPORTED_REGIONS} =~ $DEPLOY_REGION ]]; then
            log "Amazon DocumentDB is supported in current deploy region $DEPLOY_REGION "
        else
            log "ERROR: Amazon DocumentDB is not supported in current deploy region $DEPLOY_REGION"
            SCRIPT_STATUS=43
            exit $SCRIPT_STATUS
        fi
    fi
fi