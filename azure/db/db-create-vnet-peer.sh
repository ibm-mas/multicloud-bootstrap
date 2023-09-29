#!/bin/bash
	  export VnetId_1=$REQUESTER_VPC_ID #ocp
    export VnetId_2=$ACCEPTER_VPC_ID   #db
	  export ACCEPTER_REGION=$DEPLOY_REGION
	  export DBOCP="Database-OCP"
    export OCPDB="DB-Database-Peering"

 if [[  (-n $VnetId_1) &&  (-n $VnetId_2) ]] ;then

    log "db-create-vnet-peer.sh .......... starts"
    log "db-create-vnet-peer.sh : REQUESTER_VPC_ID : $REQUESTER_VPC_ID" # VPC_ID of cluster
    log "db-create-vnet-peer.sh : ACCEPTER_VPC_ID : $ACCEPTER_VPC_ID" #db_VPC_ID
	  log "db-create-vnet-peer.sh : ACCEPTER_REGION : $ACCEPTER_REGION"
    if [[ "${VnetId_1}" != "${VnetId_2}" ]]; then

      az network vnet peering list --resource-group --vnet-name

       log "db-create-vnet-peer.sh : VnetId_1 : $VnetId_1" #db_VPC_ID
           log "db-create-vnet-peer.sh : VnetId_2 : $VnetId_2" #db_VPC_ID


      log "db-create-vnet-peer.sh :"
      #Resource group of ocp
      export VnetId_1_RG=`az network vnet list --query "[?name== '${VnetId_1}'].{RG:resourceGroup}" -o tsv`
      log "db-create-vnet-peer.sh :VnetId_1_RG=$VnetId_1_RG"
      #export VnetId_1_RG=`az network vnet list | jq --arg VNET_NAME $VnetId_1 '.[] | select(.name==$VnetId_1).resourceGroup' | tr -d '"'`
      #Vnet Id of OCP
      export vNet1Id=`az network vnet show --resource-group $VnetId_1_RG --name $VnetId_1 --query id --out tsv`
     log "db-create-vnet-peer.sh :vNet1Id=$vNet1Id"
      #Resource group of Database

      export VnetId_2_RG=`az network vnet list --query "[?name== '${VnetId_2}'].{RG:resourceGroup}" -o tsv`
      #export VnetId_2_RG=`az network vnet list | jq --arg VNET_NAME $VnetId_2 '.[] | select(.name==$VNET_NAME).resourceGroup' | tr -d '"'`
       #Vnet Id of Database
      export  vNet2Id=`az network vnet show --resource-group $VnetId_2_RG --name $VnetId_2 --query id --out tsv`
      log "db-create-vnet-peer.sh : Validate the CIDR ranges of 2 Vnets -- Start "
      export VPC_1_CIDR=`az network vnet show -n $VnetId_1 -g $VnetId_1_RG --query "addressSpace.addressPrefixes[0]" -o tsv`
    	export VPC_2_CIDR=`az network vnet show -n $VnetId_2 -g $VnetId_2_RG --query "addressSpace.addressPrefixes[0]" -o tsv`
    	log "VPC_1_CIDR=$VPC_1_CIDR"
    	log "VPC_2_CIDR=$VPC_2_CIDR"
      if [[ "${VPC_1_CIDR}" == "${VPC_2_CIDR}" ]] ;then
          SCRIPT_STATUS=35
          log "db-create-vnet-peer.sh : VPC_1_CIDR , VPC_2_CIDR should not have same CIDR values for Vnet Peering, exiting..."
          exit $SCRIPT_STATUS
      fi
      log "db-create-vnet-peer.sh : Validate the CIDR ranges of 2 Vnets -- Ends "

      log "Create a peering from $VnetId_1 to $VnetId_2 -- Starts"

      export VNet_PEERING_CONNECTION_ID_1=`az network vnet peering create --name $DBOCP --resource-group $VnetId_1_RG --vnet-name $VnetId_1  --remote-vnet $vNet2Id --allow-vnet-access --query peeringState`
      sleep 30
      log "db-create-vnet-peer.sh : VNet_PEERING_CONNECTION_ID=$VNet_PEERING_CONNECTION_ID_1"
      counter=0
       log "Create a peering -- Status 1 --$VNet_PEERING_CONNECTION_ID_1"
              	while [[ "${VNet_PEERING_CONNECTION_ID_1}" != "${InitialStatus}" ]] && [[ $counter < 20 ]]; do
              			counter=counter+1
              			log "Create a peering -- Status -- ${counter} --$VNet_PEERING_CONNECTION_ID_1"
                    export VNet_PEERING_CONNECTION_ID_1=`az network vnet peering show  --name $DBOCP --resource-group  $VnetId_1_RG  --vnet-name  $VnetId_1  --query peeringState`
                   log "Create a peering -- Status status-- --$VNet_PEERING_CONNECTION_ID_1_STATUS"
                    sleep 30

              	done
              	  log "Create a peering -- Status outside-- --$VNet_PEERING_CONNECTION_ID_1"

      if [[ $VNet_PEERING_CONNECTION_ID_1 != '"Initiated"' ]]; then
            SCRIPT_STATUS=35
           log "db-create-vnet-peer.sh : VNet_PEERING_CONNECTION_ID is not Initiated, exiting..."
			     exit $SCRIPT_STATUS
      fi
	log "Create a peering -- Status --2 --$VNet_PEERING_CONNECTION_ID_1"
      if [[  $VNet_PEERING_CONNECTION_ID_1 == '"Initiated"' ]]; then
          log "db-create-vnet-peer.sh : Azure vnet peering initialized "
          export VNet_PEERING_CONNECTION_ID_2=`az network vnet peering create --name $OCPDB --resource-group $VnetId_2_RG --vnet-name $VnetId_2 --remote-vnet $vNet1Id --allow-vnet-access --query peeringState`
        	   log "db-create-vnet-peer.sh :status - accepter  $VNet_PEERING_CONNECTION_ID_2 "
        	export VNet_PEERING_CONNECTION_STATUS=`az network vnet peering show  --name $OCPDB --resource-group  $VnetId_2_RG  --vnet-name  $VnetId_2  --query peeringState`
        	        	   log "db-create-vnet-peer.sh :status - accepter2  $VNet_PEERING_CONNECTION_STATUS "
        	counter1=0
         	while [[ $VNet_PEERING_CONNECTION_STATUS != '"Connected"' ]] && [[ $counter1 < 20 ]]; do
        			counter1=counter1+1
              export VNet_PEERING_CONNECTION_STATUS=`az network vnet peering show  --name $OCPDB --resource-group  $VnetId_2_RG  --vnet-name  $VnetId_2  --query peeringState`
              sleep 30
        	done
          if [[ $VNet_PEERING_CONNECTION_STATUS != '"Connected"' ]]; then
            	SCRIPT_STATUS=35
            	log "db-create-vnet-peer.sh : Peering failed , exiting..."
            	exit $SCRIPT_STATUS
          fi
      fi
    fi
    log "Peering Completed"
    else
          SCRIPT_STATUS=35
                log "db-create-vnet-peer.sh : Vnets are blank..."
                exit $SCRIPT_STATUS

    fi