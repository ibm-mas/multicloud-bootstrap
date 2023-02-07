#!/bin/bash
# Script to cleanup the MAS deployment on AWS.
# It will cleanup all the below resources that get created during the deployment.
# - EC2 instances
# - EBS Volumes
# - NAT gateways
# - Elastic IPs
# - Load balancers
# - Network interfaces
# - Internet gateway
# - Subnets
# - Routing tables
# - Network ACLs
# - Security groups
# - VPC
# - S3 buckets
# - IAM users
# - IAM instance profiles
# - IAM policies
# - IAM roles
# - Private hosted zone
# - CloudWatch Log groups
# - CloudFormation stack
#

# Fail the script if any of the steps fail
set -e

# Functions
usage() {
  echo "Usage: cleanup-mas-deployment.sh -s stack-name -u unique-string -r region-code"
  echo "  Provide either 'stack-name' or 'unique-string' parameter."
  echo " "
  echo "  - If CloudFormation stack is present and it has the resource with 'Logical ID' named 'DeploymentRoleProfile',"
  echo "    you can delete the AWS stack by stack name. (Check the 'Resources' tab on CloudFormation stack)"
  echo "  - If you want to cleanup the resources based on the unique string, then provide the 'unique-string' parameter."
  echo "    In this case, the associated CloudFormation stack won't be deleted even if it exists. It should be deleted explicitly."
  echo " "
  echo "  Do not specify both 'stack-name' and 'unique-string' parameters at the same time."
  echo "  For example, "
  echo "   cleanup-mas-deployment.sh -s mas-stack-1 -r us-east-1"
  echo "   cleanup-mas-deployment.sh -u gf5thj -r us-east-1"
  exit 1
}

# Read arguments
if [[ $# -eq 0 ]]; then
  echo "No arguments provided with $0. Exiting.."
  usage
else
  while getopts 's:u:r:?h' c; do
    case $c in
    s)
      STACK_NAME=$OPTARG
      ;;
    u)
      UNIQUE_STR=$OPTARG
      ;;
    r)
      REGION=$OPTARG
      ;;
    h | *)
      usage
      ;;
    esac
  done
fi
echo "Script Inputs:"
echo " Stack name = $STACK_NAME"
echo " Unique string = $UNIQUE_STR"
echo " Region = $REGION"

# Check for supported region
if [[ -z $REGION ]]; then
  echo "ERROR: Parameter 'region-code' not provided"
  usage
fi
SUPPORTED_REGIONS="us-east-1;us-east-2;us-west-2;ap-east-1;ap-southeast-1;ap-southeast-2;ap-northeast-1;eu-central-1;ap-south-1;ap-northeast-2;ap-northeast-3;ca-central-1;eu-south-1;eu-west-1;eu-west-2;eu-west-3;eu-north-1;af-south-1;me-south-1;sa-east-1"
if [[ ${SUPPORTED_REGIONS} =~ $REGION ]]; then
  echo "Supported region provided"
else
  echo "ERROR: Empty or unsupported region provided"
  echo "Supported regions are $SUPPORTED_REGIONS"
  usage
fi

if [[ (-z $STACK_NAME) && (-z $UNIQUE_STR) ]]; then
  echo "ERROR: Both the parameters 'stack-name' and 'unique-string' are empty, one of these should have a value"
  usage
fi

# If resource group is provided, do not specify unique string
if [[ (-n $STACK_NAME) && (-n $UNIQUE_STR) ]]; then
  echoRed "ERROR: Do not specify both 'stack-name' and 'unique-string'. If 'stack-name' is specified, do not specify 'unique-string'."
  usage
fi

if [[ -n $STACK_NAME ]]; then
  # Get AWS stack unique string
  UNIQ_STR=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --region $REGION 2>/dev/null | jq ".StackResources[] | select(.LogicalResourceId == \"DeploymentRoleProfile\").PhysicalResourceId" | tr -d '"' | cut -d '-' -f 5)
  if [[ -z $UNIQ_STR ]]; then
    echo "ERROR: Could not retrieve the unique string from the stack. Make sure stack name and region parameters are correct."
    exit 1
  fi
  echo "Deleting by 'stack-name' $STACK_NAME"
elif [[ -n UNIQUE_STR ]]; then
  UNIQ_STR=$UNIQUE_STR
  echo "Deleting by 'unique-string' $UNIQ_STR"
fi

echo "==== Execution started at `date` ===="
echo "AWS stack unique string: $UNIQ_STR"
echo "---------------------------------------------"

## Delete EC2 instances
echo "Checking for EC2 instances"
# Get EC2 instance list
INSTANCES=$(aws ec2 describe-instances --filters Name=tag:Name,Values=masocp-${UNIQ_STR}* --region $REGION | jq ".Reservations[].Instances[] | select(.State.Name != \"terminated\").InstanceId" | tr -d '"')
echo "INSTANCES = $INSTANCES"
if [[ -n $INSTANCES ]]; then
  echo "EC2 instances found for this AWS stack"
  EC2_LIST=""
  for inst in $INSTANCES; do
    EC2_LIST="$EC2_LIST $inst"
  done
  EC2_LIST=$(echo $EC2_LIST | sed 's/^ *//g' | sed 's/ *$//g')
  echo "Deleting EC2 instances with Ids $EC2_LIST"
  # Delete instances
  aws ec2 terminate-instances --region $REGION --instance-ids $EC2_LIST > /dev/null
  echo "Terminate request submitted"
  # Wait for instance to go in 'Terminated' state
  echo "Waiting for instances to be terminated"
  aws ec2 wait instance-terminated --region $REGION --instance-ids $EC2_LIST
  echo "Deleted EC2 instances"
else
  echo "No EC2 instances found for this AWS stack"
fi
echo "---------------------------------------------"

## Delete volumes
echo "Checking for volumes"
VOLS=$(aws ec2 describe-volumes --filters Name=tag:Name,Values=masocp-${UNIQ_STR}* --region $REGION | jq ".Volumes[].VolumeId" | tr -d '"')
echo "VOLS=$VOLS"
if [[ -n $VOLS ]]; then
  echo "Found volumes for this AWS stack"
  for inst in $VOLS; do
    aws ec2 delete-volume --volume-id $inst --region $REGION
    echo "Deleted volume $inst"
  done
else
  echo "No volumess found for this AWS stack"
fi

## Delete NAT gateways and release EIPs
echo "Checking for VPC"
# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=masocp-${UNIQ_STR}-vpc --region $REGION | jq ".Vpcs[0].VpcId" | tr -d '"')
echo "VPC_ID = $VPC_ID"
if [[ $VPC_ID != "null" ]]; then
  echo "Found VPC with Id $VPC_ID for this AWS stack, it will be deleted at the end"
  echo "---------------------------------------------"
  echo "Checking for NAT gateways"
  # Get NAT gateways
  NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --region $REGION | jq ".NatGateways[] | select(.State != \"deleted\").NatGatewayId" | tr -d '"')
  echo "NAT_GATEWAYS = $NAT_GATEWAYS"
  if [[ -n $NAT_GATEWAYS ]]; then
    echo "Found NAT gateways for this AWS stack"
    # Get EIPs associated with NAT gateways
    NAT_GATEWAY_EIPS=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --region $REGION | jq ".NatGateways[].NatGatewayAddresses[0].PublicIp" | tr -d '"')
    echo "NAT_GATEWAY_EIPS = $NAT_GATEWAY_EIPS"
    # Delete NAT gateways
    for inst in $NAT_GATEWAYS; do
      aws ec2 delete-nat-gateway --nat-gateway-id $inst --region $REGION
      echo "Invoked deletion of NAT gateway $inst"
    done
    sleep 20

    for inst in $NAT_GATEWAYS; do
      echo "Checking deletion status of NAT gateway with id $inst ..."
      state="deleting"
      while [ $state != "deleted" ]; do
        state=$(aws ec2 describe-nat-gateways --filter Name=nat-gateway-id,Values=$inst --region $REGION | jq ".NatGateways[].State" | tr -d '"')
        echo " State of network gateway $inst is $state"
        sleep 5
      done
      echo "Deleted NAT gateway with id $inst"
    done
    sleep 10
    echo "---------------------------------------------"
    echo "Checking for EIPs"
    if [[ -n $NAT_GATEWAY_EIPS ]]; then
      echo "Found EIPs for this AWS stack"
      # Release EIPs
      for inst in $NAT_GATEWAY_EIPS; do
        allocaid=$(aws ec2 describe-addresses --region $REGION --public-ips $inst | jq ".Addresses[].AllocationId" | tr -d '"')
        if [[ -n $allocaid ]]; then
          aws ec2 release-address --region $REGION --allocation-id $allocaid
        else
          aws ec2 release-address --region $REGION --public-ip $inst
        fi
        echo "Released EIP $inst"
      done
    else
      echo "No EIPs found for this AWS stack"
    fi
  else
    echo "No NAT gateways found for this AWS stack"
  fi
  echo "---------------------------------------------"

  SLEEPTIME=2
  # Delete load balancers
  echo "Checking for load balancers"
  LOAD_BALANCERS=$(aws elb describe-load-balancers --region $REGION | jq ".LoadBalancerDescriptions[] | select(.VPCId == \"$VPC_ID\").LoadBalancerName" | tr -d '"')
  echo "LOAD_BALANCERS = $LOAD_BALANCERS"
  if [[ -n $LOAD_BALANCERS ]]; then
    SLEEPTIME=60
    echo "Found load balancers for this AWS stack"
    for inst in $LOAD_BALANCERS; do
      aws elb delete-load-balancer --region $REGION --load-balancer-name $inst
      echo "Deleted load balancer $inst"
    done
  else
    echo "No load balancers found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete v2 load balancers
  echo "Checking for v2 load balancers"
  LOAD_BALANCERS_V2=$(aws elbv2 describe-load-balancers --region $REGION | jq ".LoadBalancers[] | select(.VpcId == \"$VPC_ID\").LoadBalancerArn" | tr -d '"')
  echo "LOAD_BALANCERS_V2 = $LOAD_BALANCERS_V2"
  if [[ -n $LOAD_BALANCERS_V2 ]]; then
    SLEEPTIME=120
    echo "Found v2 load balancers for this AWS stack"
    for inst in $LOAD_BALANCERS_V2; do
      aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn "$inst"
      echo "Deleted v2 load balancer $inst"
    done
  else
    echo "No v2 load balancers found for this AWS stack"
  fi
  echo "Waiting for $SLEEPTIME seconds for network interfaces to be released"
  sleep $SLEEPTIME
  echo "---------------------------------------------"

  # Delete network interfaces
  echo "Checking for network interfaces"
  NW_IFS=$(aws ec2 describe-network-interfaces --region $REGION --filter Name=vpc-id,Values=$VPC_ID | jq ".NetworkInterfaces[] | select(.VpcId == \"$VPC_ID\").NetworkInterfaceId" | tr -d '"')
  echo "NW_IFS = $NW_IFS"
  if [[ -n $NW_IFS ]]; then
    echo "Found network interfaces for this AWS stack"
    for inst in $NW_IFS; do
      aws ec2 delete-network-interface --network-interface-id $inst --region $REGION
      echo "Deleted network interface $inst"
      sleep 5
    done
  else
    echo "No network interfaces found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete internet gateway
  echo "Checking for internet gateways"
  IGWID=$(aws ec2 describe-internet-gateways --region $REGION --filter Name=attachment.vpc-id,Values=$VPC_ID | jq ".InternetGateways[].InternetGatewayId" | tr -d '"')
  echo "IGWID = $IGWID"
  if [[ -n $IGWID ]]; then
    echo "Found internet gateway $IGWID for this AWS stack"
    # Detach internet gateway
    aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id $IGWID --vpc-id $VPC_ID
    echo "Detached internet gateway $IGWID from VPC $VPC_ID"
    # Delete internet gateway
    aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id $IGWID
    echo "Deleted internet gateway $IGWID"
  else
    echo "No internet gateways found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete subnets
  echo "Checking for subnets"
  SUBNETS=$(aws ec2 describe-subnets --region $REGION --filter Name=vpc-id,Values=$VPC_ID | jq ".Subnets[].SubnetId" | tr -d '"')
  echo "SUBNETS = $SUBNETS"
  if [[ -n $SUBNETS ]]; then
    echo "Found subnets for this AWS stack"
    for inst in $SUBNETS; do
      aws ec2 delete-subnet --subnet-id $inst --region $REGION
      echo "Deleted subnet $inst"
    done
  else
    echo "No subnets found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete routing tables
  echo "Checking for routing tables"
  RTS=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values=$VPC_ID --region $REGION | jq ".RouteTables[].RouteTableId" | tr -d '"')
  echo "RTS = $RTS"
  if [[ -n $RTS ]]; then
    echo "Found routing tables for this AWS stack"
    for inst in $RTS; do
      # Check if RT is 'Main' RT
      mainrt=$(aws ec2 describe-route-tables --filter Name=route-table-id,Values=$inst --region $REGION | jq ".RouteTables[].Associations[].Main")
      if [[ $mainrt == "true" ]]; then
        echo "Skip deletion of 'Main' RT $inst"
      else
        aws ec2 delete-route-table --route-table-id $inst --region $REGION
        echo "Deleted routing table $inst"
      fi
    done
  else
    echo "No routing tables found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete network ACLs
  echo "Checking for network ACLs"
  NACLS=$(aws ec2 describe-network-acls --filter Name=vpc-id,Values=$VPC_ID --region $REGION | jq ".NetworkAcls[].NetworkAclId" | tr -d '"')
  echo "NACLS = $NACLS"
  if [[ -n $NACLS ]]; then
    echo "Found network ACLs for this AWS stack"
    for inst in $NACLS; do
      # Check if network ACL is 'default' RT
      defacl=$(aws ec2 describe-network-acls --filter Name=vpc-id,Values=$VPC_ID --region $REGION | jq ".NetworkAcls[].IsDefault")
      if [[ $defacl == "true" ]]; then
        echo "Skip deletion of default network ACL $inst"
      else
        aws ec2 delete-network-acl --network-acl-id $inst --region $REGION
        echo "Deleted network ACL $inst"
      fi
    done
  else
    echo "No network ACLs found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete security groups
  echo "Checking for security groups"
  SGS=$(aws ec2 describe-security-groups --region $REGION | jq ".SecurityGroups[] | select(.VpcId == \"$VPC_ID\").GroupId" | tr -d '"')
  echo "SGS = $SGS"
  if [[ -n $SGS ]]; then
    echo "Found security groups for this AWS stack"
    # Delete the inbound and outbound rules
    for inst in $SGS; do
      # Check if security group is 'default'
      sgname=$(aws ec2 describe-security-groups --group-ids $inst --region $REGION | jq ".SecurityGroups[].GroupName" | tr -d '"')
      if [[ $sgname == "default" ]]; then
        echo "Skip default security group $inst"
      else
        # Delete all inbound and outbound rules
        json=`aws ec2 describe-security-groups --region $REGION --group-id $inst --query "SecurityGroups[0].IpPermissions" | tr -d '\r\n'`
        if [[ $json != "[]" ]]; then
          aws ec2 revoke-security-group-ingress --region $REGION --cli-input-json "{\"GroupId\": \"$inst\", \"IpPermissions\": $json}"
          echo "Deleted all inbound rules from SG $inst"
        fi
        json=`aws ec2 describe-security-groups --region $REGION --group-id $inst --query "SecurityGroups[0].IpPermissionsEgress" | tr -d '\r\n'`
        if [[ $json != "[]" ]]; then
          aws ec2 revoke-security-group-egress --region $REGION --cli-input-json "{\"GroupId\": \"$inst\", \"IpPermissions\": $json}"
          echo "Deleted all outbound rules from SG $inst"
        fi
      fi
    done
    # Delete security groups
    for inst in $SGS; do
      # Check if security group is 'default'
      sgname=$(aws ec2 describe-security-groups --group-ids $inst --region $REGION | jq ".SecurityGroups[].GroupName" | tr -d '"')
      if [[ $sgname == "default" ]]; then
        echo "Skip deletion of default security group $inst"
      else
        aws ec2 delete-security-group --group-id $inst --region $REGION
        echo "Deleted security group $inst"
      fi
    done
  else
    echo "No security groups found for this AWS stack"
  fi
  echo "---------------------------------------------"

  # Delete VPC
  aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID
else
  echo "No VPC found for this AWS stack"
fi
echo "---------------------------------------------"

# Delete S3 bucket
echo "Checking for S3 buckets"
S3BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `masocp-'"${UNIQ_STR}"'`) == `true`].[Name]' --output text)
echo "S3BUCKETS = $S3BUCKETS"
if [[ -n $S3BUCKETS ]]; then
  echo "Found S3 buckets for this AWS stack"
  for inst in $S3BUCKETS; do
    inst=$(echo $inst | tr -d '\r\n')
    aws s3 rb s3://$inst --force --region $REGION
    echo "Deleted bucket $inst"
  done
else
  echo "No S3 buckets for this AWS stack"
fi
echo "---------------------------------------------"

## Delete IAM users
echo "Checking for IAM users"
# Get all users having unique string in the name
USERS=$(aws iam list-users | jq ".Users[] | select(.UserName | contains(\"$UNIQ_STR\")).UserName" | tr -d '"')
echo "USERS = $USERS"
if [[ -n $USERS ]]; then
  echo "Found IAM users for this AWS stack"
  for inst in $USERS; do
    # Get and detach policies attached to user
    policies=$(aws iam list-attached-user-policies --user-name ${inst} | jq ".AttachedPolicies[].PolicyArn" | tr -d '"')
    if [[ -n $policies ]]; then
      for pol in $policies; do
        aws iam detach-user-policy --user-name ${inst} --policy-arn $pol
        echo "Detached policy $pol from user ${inst}"
      done
    fi
    # Get and delete inline policies attached to user
    policies=$(aws iam list-user-policies --user-name ${inst} | jq ".PolicyNames[]" | tr -d '"')
    if [[ -n $policies ]]; then
      for pol in $policies; do
        aws iam delete-user-policy --user-name ${inst} --policy-name $pol
        echo "Deleted inline policy $pol from user ${inst}"
      done
    fi
    # Get and delete access key associated with user
    accesskeyid=$(aws iam list-access-keys --user-name ${inst} | jq ".AccessKeyMetadata[].AccessKeyId" | tr -d '"')
    if [[ -n $accesskeyid ]]; then
      aws iam delete-access-key --user-name ${inst} --access-key-id $accesskeyid
      echo "Deleted access key $accesskeyid associated with user ${inst}"
    fi
    aws iam delete-user --user-name ${inst}
    echo "Deleted user ${inst}"
  done
else
  echo "No IAM users for this AWS stack"
fi
echo "---------------------------------------------"

## Delete IAM instance profiles
echo "Checking for IAM instance profiles"
INSTPROFS=$(aws iam list-instance-profiles | jq ".InstanceProfiles[] | select(.InstanceProfileName | contains(\"$UNIQ_STR\")).InstanceProfileName" | tr -d '"')
echo "INSTPROFS = $INSTPROFS"
if [[ -n $INSTPROFS ]]; then
  echo "Found IAM instance profiles for this AWS stack"
  for inst in $INSTPROFS; do
    # Get roles associated with instance profile
    ifroles=$(aws iam get-instance-profile --instance-profile-name $inst | jq ".InstanceProfile.Roles[].RoleName" | tr -d '"')
    if [[ -n $ifroles ]]; then
      for role in $ifroles; do
        # Detach role from instance profile
        aws iam remove-role-from-instance-profile --instance-profile-name $inst --role-name $role
        echo "Removed role $role from instance profile $inst"
      done
    fi
    # Delete instance profile
    aws iam delete-instance-profile --instance-profile-name $inst
    echo "Deleted IAM instance profile ${inst}"
  done
else
  echo "No IAM instance profiles for this AWS stack"
fi
echo "---------------------------------------------"

## Delete IAM policies
echo "Checking for IAM policies"
POLICIES=$(aws iam list-policies | jq ".Policies[] | select(.PolicyName | contains(\"$UNIQ_STR\")).Arn" | tr -d '"')
echo "POLICIES = $POLICIES"
if [[ -n $POLICIES ]]; then
  echo "Found IAM policies for this AWS stack"
  for inst in $POLICIES; do
    # Delete policy
    aws iam delete-policy --policy-arn $inst
    echo "Deleted IAM policy ${inst}"
  done
else
  echo "No IAM policies for this AWS stack"
fi
echo "---------------------------------------------"

## Delete IAM roles
echo "Checking for IAM roles"
ROLES=$(aws iam list-roles | jq ".Roles[] | select(.RoleName | contains(\"$UNIQ_STR\")).RoleName" | tr -d '"')
echo "ROLES = $ROLES"
if [[ -n $ROLES ]]; then
  echo "Found IAM roles for this AWS stack"
  for inst in $ROLES; do
    # Delete role policies
    rolepols=$(aws iam list-role-policies --role-name $inst | jq ".PolicyNames[]" | tr -d '"')
    for pol in $rolepols; do
      aws iam delete-role-policy --role-name $inst --policy-name $pol
      echo "Deleted policy $pol from role $inst"
    done
    # Delete role
    aws iam delete-role --role-name $inst
    echo "Deleted IAM role ${inst}"
  done
else
  echo "No IAM roles for this AWS stack"
fi
echo "---------------------------------------------"

## Delete private hosted zone
echo "Checking for private hosted zones"
PHZID=$(aws route53 list-hosted-zones --region $REGION --output text --query 'HostedZones[*].[Name,Id]' --output text | grep $UNIQ_STR | cut -f2 | cut -f3 -d '/' | tr -d '\r\n')
echo "PHZID = $PHZID"
if [[ -n $PHZID ]]; then
  echo "Found private hosted zone for this AWS stack"
  aws route53 list-resource-record-sets --hosted-zone-id $PHZID --region $REGION | jq -c '.ResourceRecordSets[]' |
  while read -r resourcerecordset; do
    read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
    if [ $type != "NS" -a $type != "SOA" ]; then
      aws route53 change-resource-record-sets  --region $REGION --hosted-zone-id $PHZID --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":'"$resourcerecordset"'}]}' --output text --query 'ChangeInfo.Id'
    fi
  done
  aws route53 delete-hosted-zone --id "$PHZID" --region $REGION
	echo "Deleted private hosted zone ${PHZID}"
else
  echo "No private hosted zone for this AWS stack"
fi
echo "---------------------------------------------"

## Delete CloudWatch log groups
echo "Checking for CloudWatch Log groups"
CWLG=$(aws logs describe-log-groups --region $REGION | jq ".logGroups[] | select(.logGroupName | contains(\"${STACK_NAME}-LambdaFunction\")).logGroupName" | tr -d '"')
echo "CWLG = $CWLG"
if [[ -n $CWLG ]]; then
  echo "Found OCP installer created CloudWatch Log groups for this AWS stack"
  for inst in $CWLG; do
    # Delete log group
    aws logs delete-log-group --log-group-name $inst --region $REGION
    echo "Deleted OCP installer created CloudWatch Log group $inst"
  done
else
  echo "No OCP installer created CloudWatch Log groups for this AWS stack"
fi
CWLG=$(aws logs describe-log-groups --region $REGION | jq ".logGroups[] | select(.logGroupName | contains(\"masocp-${UNIQ_STR}\")).logGroupName" | tr -d '"')
echo "CWLG = $CWLG"
if [[ -n $CWLG ]]; then
  echo "Found automation created CloudWatch Log groups for this AWS stack"
  for inst in $CWLG; do
    # Delete log group
    aws logs delete-log-group --log-group-name $inst --region $REGION
    echo "Deleted automation created CloudWatch Log group $inst"
  done
else
  echo "No automation created CloudWatch Log groups for this AWS stack"
fi
echo "---------------------------------------------"

## Delete secret in Secrets Manager
echo "Checking for secret"
for secret in maximo-ocp-secret-$UNIQ_STR maximo-mas-secret-$UNIQ_STR; do
  SECRET=$(aws secretsmanager describe-secret --secret-id $secret --region $REGION | jq ".Name" | tr -d '"')
  echo "SECRET = $SECRET"
  if [[ -n $SECRET ]]; then
    # Delete secret
    aws secretsmanager delete-secret --secret-id $secret --region $REGION
    echo "Deleted secret $secret"
  else
    echo "No secret named $secret for this AWS stack"
  fi
done

# Delete CloudFormation stack
if [[ -n $STACK_NAME ]]; then
  echo "Checking for CloudFormation stack"
  STACKARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION | jq ".Stacks[].StackId" | tr -d '"')
  echo "STACKARN = $STACKARN"
  if [[ -n $STACKARN ]]; then
    # Get stack ARN
    aws cloudformation delete-stack --stack-name $STACKARN --region $REGION
    echo "Delete initiated for CloudFormation stack $STACK_NAME"
    # Wait for delete complete
    aws cloudformation wait stack-delete-complete --stack-name $STACKARN --region $REGION
    echo "Deleted stack $STACK_NAME"
  else
    echo "No CloudFormation stack for this AWS stack"
  fi
  echo "---------------------------------------------"
else
  echo "No 'stack-name' specified, you may need to delete the CloudFormation stack explicitly if exists, or run the script with -s 'stack-name' parameter"
fi
echo "==== Execution completed at `date` ===="
