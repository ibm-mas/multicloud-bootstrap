#!/bin/bash
	export VPC_1=$REQUESTER_VPC_ID
    export VPC_2=$ACCEPTER_VPC_ID
	export ACCEPTER_REGION=$DEPLOY_REGION

    log "db-create-vpc-peer.sh .......... starts"
    log "db-create-vpc-peer.sh : REQUESTER_VPC_ID : $REQUESTER_VPC_ID" #BOOTNODE_VPC_ID or VPC_ID
    log "db-create-vpc-peer.sh : ACCEPTER_VPC_ID : $ACCEPTER_VPC_ID" #db_VPC_ID
	log "db-create-vpc-peer.sh : ACCEPTER_REGION : $ACCEPTER_REGION"
    if [[ "${VPC_1}" != "${VPC_2}" ]]; then

        log "db-create-vpc-peer.sh : Invoke db-create-iam-user.sh"

		sh $GIT_REPO_HOME/aws/db/db-create-iam-user.sh
		if [ $? -ne 0 ]; then
			SCRIPT_STATUS=36
			exit $SCRIPT_STATUS
		fi

 		export _VPC_1=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$VPC_1" --region $ACCEPTER_REGION --query=Vpcs[*].VpcId --output=text`
		export _VPC_2=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$VPC_2" --region $ACCEPTER_REGION --query=Vpcs[*].VpcId --output=text`
		log "_VPC_1=$_VPC_1"
		log "_VPC_2=$_VPC_2"

		if [[ -z "$_VPC_2" ]]; then
			SCRIPT_STATUS="45"
			log "db-create-vpc-peer.sh : User entered $_VPC_2 is not found in region $ACCEPTER_REGION, exiting..."
			exit $SCRIPT_STATUS
		fi

		#This edge case will not occur as BOOTNODE_VPC_ID or VPC_ID will be there.
		if [[ -z "$_VPC_1" ]]; then
			SCRIPT_STATUS="40"
			log "db-create-vpc-peer.sh : $_VPC_1 is not found in region $ACCEPTER_REGION, exiting..."
			exit $SCRIPT_STATUS
		fi

		export VPC_1_CIDR=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$VPC_1" --region $ACCEPTER_REGION --query=Vpcs[*].CidrBlock --output=text`
		export VPC_2_CIDR=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$VPC_2" --region $ACCEPTER_REGION --query=Vpcs[*].CidrBlock --output=text`
		log "VPC_1_CIDR=$VPC_1_CIDR"
		log "VPC_2_CIDR=$VPC_2_CIDR"

		if [[ -z "$VPC_1_CIDR" || -z "$VPC_2_CIDR" ]]; then
			SCRIPT_STATUS=35
			log "db-create-vpc-peer.sh : VPC_1_CIDR or VPC_2_CIDR is empty, exiting..."
			exit $SCRIPT_STATUS
		fi

        log "db-create-vpc-peer.sh : Invoke create-vpc-peering-connection"
        export VPC_PEERING_CONNECTION_ID=`aws ec2 create-vpc-peering-connection --vpc-id ${VPC_1} --peer-vpc-id ${VPC_2} --query="VpcPeeringConnection.VpcPeeringConnectionId" --output text`
        sleep 30
        log "db-create-vpc-peer.sh : VPC_PEERING_CONNECTION_ID=$VPC_PEERING_CONNECTION_ID"
        if [[ -z "$VPC_PEERING_CONNECTION_ID" ]]; then
            SCRIPT_STATUS=35
            log "db-create-vpc-peer.sh : VPC_PEERING_CONNECTION_ID is empty, exiting..."
			exit $SCRIPT_STATUS
        fi
        if [[ -n "$VPC_PEERING_CONNECTION_ID" ]]; then
            log "db-create-vpc-peer.sh : aws ec2 accept-vpc-peering-connection"

			counter=0
			found="false"
			while [[ $found == "false" ]] && [[ $counter < 20 ]]; do
				counter=counter+1
				aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id ${VPC_PEERING_CONNECTION_ID} --query="VpcPeeringConnection.Status.Code"
				if [[ $? -ne 0 ]]; then
					SCRIPT_STATUS=35
					log "db-create-vpc-peer.sh : ACCEPT_VPC_PEERING_CONNECTION failed, exiting..."
					exit $SCRIPT_STATUS
				else
					log "db-create-vpc-peer.sh : ACCEPT_VPC_PEERING_CONNECTION accepted, waiting for provisioning and status change to active..."
					sleep 60
					export ACCEPT_VPC_PEERING_CONNECTION=`aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id ${VPC_PEERING_CONNECTION_ID} --query="VpcPeeringConnection.Status.Code"`
					log "db-create-vpc-peer.sh : ACCEPT_VPC_PEERING_CONNECTION==$ACCEPT_VPC_PEERING_CONNECTION"
					if [[ "${ACCEPT_VPC_PEERING_CONNECTION}" == *"active"* ]] ;then
						found="true"
					fi
				fi
			done

			log "db-create-vpc-peer.sh : ACCEPT_VPC_PEERING_CONNECTION=$ACCEPT_VPC_PEERING_CONNECTION"
			if [[ -z "$ACCEPT_VPC_PEERING_CONNECTION"  ]]; then
				SCRIPT_STATUS=35
				log "db-create-vpc-peer.sh : ACCEPT_VPC_PEERING_CONNECTION is empty, exiting..."
				exit $SCRIPT_STATUS
			fi

			# Creating Routes for vpc peering at cluster and mirror machines
			log "db-create-vpc-peer.sh : create routes started"

			# Get main Route table id for each vpc id
			if [[ -n "$VPC_PEERING_CONNECTION_ID" && "${ACCEPT_VPC_PEERING_CONNECTION}" == *"active"* ]] ;then
				# routing tables
				log "---------------------------------------------"
				log "Checking for routing tables for VPC $VPC_1"
				RTS=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values=$VPC_1 --region $DEPLOY_REGION | jq ".RouteTables[].RouteTableId" | tr -d '"')
				log "RTS = $RTS"
				if [[ -n $RTS ]]; then
					log "Found routing tables for this AWS stack"
					for VPC_1_ROUTE_TABLE_ID in $RTS; do

						#check if the route with blackhole status exist
						EXISTING_ROUTE_TABLE_ID_WITH_BLACKHOLE_STATUS=`aws ec2 describe-route-tables --filters  \
						--region $ACCEPTER_REGION \
						"Name=route-table-id,Values=$VPC_1_ROUTE_TABLE_ID"  \
						"Name=route.destination-cidr-block,Values=$VPC_2_CIDR" \
						"Name=route.state,Values=blackhole" \
						--query RouteTables[].RouteTableId  --output=text`

						if [[ -n $EXISTING_ROUTE_TABLE_ID_WITH_BLACKHOLE_STATUS ]]; then
							log "db-create-vpc-peer.sh : aws ec2 delete-route route-table-id $VPC_1_ROUTE_TABLE_ID destination-cidr-block $VPC_2_CIDR started"
							aws ec2 delete-route --route-table-id $VPC_1_ROUTE_TABLE_ID --destination-cidr-block $VPC_2_CIDR --region $ACCEPTER_REGION
						fi

						#check if the route exist already
						EXISTING_ROUTE_TABLE_ID=`aws ec2 describe-route-tables --filters  \
						--region $ACCEPTER_REGION \
						"Name=route-table-id,Values=$VPC_1_ROUTE_TABLE_ID"  \
						"Name=route.vpc-peering-connection-id,Values=$VPC_PEERING_CONNECTION_ID" \
						"Name=route.destination-cidr-block,Values=$VPC_2_CIDR" \
						"Name=route.state,Values=active" \
						--query RouteTables[].RouteTableId  --output=text`
						log "db-create-vpc-peer.sh : EXISTING_ROUTE_TABLE_ID=$EXISTING_ROUTE_TABLE_ID"
						if [[ -z $EXISTING_ROUTE_TABLE_ID ]]; then
							log "db-create-vpc-peer.sh : aws ec2 create-route $VPC_1_ROUTE_TABLE_ID $VPC_2_CIDR $VPC_PEERING_CONNECTION_ID started"
							export CREATE_ROUTE_1=`aws ec2 create-route --route-table-id $VPC_1_ROUTE_TABLE_ID --destination-cidr-block $VPC_2_CIDR --vpc-peering-connection-id $VPC_PEERING_CONNECTION_ID --output=text`
							sleep 10
							log "db-create-vpc-peer.sh : CREATE_ROUTE_1=$CREATE_ROUTE_1"
							if [[ ("${CREATE_ROUTE_1}" != "True") ]]; then
								#An error occurred (RouteAlreadyExists) when calling the CreateRoute operation: The route identified by 172.31.0.0/16 already exists.
								SCRIPT_STATUS=37
								log "db-create-vpc-peer.sh : aws ec2 create-route CREATE_ROUTE_1 creation failed, exiting..."
								exit $SCRIPT_STATUS
							fi
						fi
					done
				else
					log "No routing tables found for this AWS stack"
				fi
				log "---------------------------------------------"

				# routing tables
				log "Checking for routing tables for VPC $VPC_2"
				RTS=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values=$VPC_2 --region $DEPLOY_REGION | jq ".RouteTables[].RouteTableId" | tr -d '"')
				log "RTS = $RTS"
				if [[ -n $RTS ]]; then
					log "Found routing tables for this AWS stack"
					for VPC_2_ROUTE_TABLE_ID in $RTS; do
						#check if the route with blackhole status exist
						EXISTING_ROUTE_TABLE_ID_WITH_BLACKHOLE_STATUS=`aws ec2 describe-route-tables --filters  \
						--region $ACCEPTER_REGION \
						"Name=route-table-id,Values=$VPC_2_ROUTE_TABLE_ID"  \
						"Name=route.destination-cidr-block,Values=$VPC_1_CIDR" \
						"Name=route.state,Values=blackhole" \
						--query RouteTables[].RouteTableId  --output=text`

						if [[ -n $EXISTING_ROUTE_TABLE_ID_WITH_BLACKHOLE_STATUS ]]; then
							log "db-create-vpc-peer.sh : aws ec2 delete-route route-table-id $VPC_2_ROUTE_TABLE_ID destination-cidr-block $VPC_1_CIDR started"
							aws ec2 delete-route --route-table-id $VPC_2_ROUTE_TABLE_ID --destination-cidr-block $VPC_1_CIDR --region $ACCEPTER_REGION
						fi

						#check if the route exist already for same peer and dest vpc
						EXISTING_ROUTE_TABLE_ID=`aws ec2 describe-route-tables --filters  \
						--region $ACCEPTER_REGION \
						"Name=route-table-id,Values=$VPC_2_ROUTE_TABLE_ID"  \
						"Name=route.vpc-peering-connection-id,Values=$VPC_PEERING_CONNECTION_ID" \
						"Name=route.destination-cidr-block,Values=$VPC_1_CIDR" \
						"Name=route.state,Values=active" \
						--query RouteTables[].RouteTableId  --output=text`

						log "db-create-vpc-peer.sh : EXISTING_ROUTE_TABLE_ID_2=$EXISTING_ROUTE_TABLE_ID"
						if [[ -z $EXISTING_ROUTE_TABLE_ID ]]; then
							log "db-create-vpc-peer.sh : aws ec2 create-route $VPC_2_ROUTE_TABLE_ID $VPC_1_CIDR $VPC_PEERING_CONNECTION_ID started"
							export CREATE_ROUTE_2=`aws ec2 create-route --route-table-id $VPC_2_ROUTE_TABLE_ID --destination-cidr-block $VPC_1_CIDR --vpc-peering-connection-id $VPC_PEERING_CONNECTION_ID --output=text`
							sleep 10
							log "db-create-vpc-peer.sh : CREATE_ROUTE_2=$CREATE_ROUTE_2"
							if [[ ("${CREATE_ROUTE_2}" != "True") ]]; then
								SCRIPT_STATUS=37
								log "db-create-vpc-peer.sh : aws ec2 create-route CREATE_ROUTE_2 creation failed, exiting..."
								exit $SCRIPT_STATUS
							fi
						fi

					done
				else
					log "No routing tables found for this AWS stack"
				fi
				log "---------------------------------------------"

			else
				SCRIPT_STATUS=37
				log "db-create-vpc-peer.sh : route not created, VPC_PEERING_CONNECTION_ID=$VPC_PEERING_CONNECTION_ID : ACCEPT_VPC_PEERING_CONNECTION=$ACCEPT_VPC_PEERING_CONNECTION"
				exit $SCRIPT_STATUS
			fi
			log "db-create-vpc-peer.sh : create routes completed"
        fi
    fi
log "db-create-vpc-peer.sh .......... ends : SCRIPT_STATUS=$SCRIPT_STATUS"

