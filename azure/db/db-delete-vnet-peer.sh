#!/bin/bash
	  export VnetId_1=$VPC_Name #ocp
    export VnetPeeringName=$PeeringName
    export VnetId_1_RG=`az network vnet list --query "[?name=='${VnetId_1}'].{RG:resourceGroup}" -o tsv`
     echo "VnetId_1_RG ....."$VnetId_1_RG "
#confirm VNet peering exists
     export VnetPeeringNameConfirm=`az network vnet peering list --resource-group  $VnetId_1_RG --vnet-name $VPC_Name --query "[?name=='${VnetPeeringName}'].{Name:name}" -o tsv`
#echo "VnetPeeringNameConfirm ..... $VnetPeeringNameConfirm"

       if [[ -n $VnetPeeringNameConfirm ]]; then
          export deletionstatus=`az network vnet peering delete --resource-group $VnetId_1_RG --name $VnetPeeringNameConfirm --vnet-name $VnetId_1`
          #echo "deletionstatus ....."$deletionstatus"
        else
           log "ERROR: VNet peering Invalid"
           SCRIPT_STATUS=35
        fiz