#!/bin/bash
#set -x
#
# Usage:  To create a new aurora database
#  Prerequisites: stash installed on your laptop
#   aurora.sh <Servicename> <env> <aws_profile> <region>
#   aurora.sh SREG e2e app1_preprod us-east-2
#   servicename: <Application prefix> Examples: app1, app2, app3
#   env:  dev/qa/e2e/prf/prd
#   aws_profile: The profile name in your credentials file
#   region: us-west-2 | us-east-2
# How to store your secrets in idps (if you don't have stash already installed on your laptop)
# 
# Create a API key for your appliance using a secret manager that your company provides.

# Get the Vpcs and DataSubnets for a given aws $PROFILE
SERVICE=$1 # Example: tep, sreg, apip, dcl
ENV=$2
PROFILE=$3 # pass aws_profile
REGION=$4  # pass region

# Create a stackname based off of the inputs
STACK=$SERVICE"-"$ENV   # pass stack Name
#echo "Stack being created is $STACK"

# Get AWS AccountId
ACCOUNT_ID=`aws sts get-caller-identity --output text --query 'Account' --profile $PROFILE --region ${REGION}`
echo "AWS ACCOUNT_ID is ${ACCOUNT_ID}"

ids=()
for vpcid in $(aws ec2 describe-vpcs --profile ${PROFILE} --region ${REGION} --query 'Vpcs[].VpcId' --output text | sed 's/None$/None\n/' | sed '$!N;s/\n/ /') ; do ids+=($vpcid) ; done
echo Select VPC: ${#ids[@]}

select opt in "${ids[@]}"
do
    if [ "$opt" == "" ]; then
        echo No VPC Selected
        exit
    else
        echo "Selected VPC"
        export VPC_ID="$opt"
        echo $VPC_ID
	for subnetid in `aws --profile ${PROFILE} --region ${REGION} ec2 describe-subnets --filter "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values='DataSubnetAz*'" |grep SubnetId |cut -d'"' -f4 ` ; do SUBNET_IDS+=$subnetid',' ; done
	echo $SUBNET_IDS | sed 's/,$//'


# Default parameter for RDS. Change these below per stack.
INSTANCE_TYPE='db.r5.xlarge'
ENGINE='aurora-mysql'
ENGINEVERSION='5.7.mysql_aurora.2.04.1.1'
PORT=3306
MULTIAZ=true
BAK_RETENTION_PERIOD=3
READREPLICA=yes # means do you want READREPLICA in default region (us-west-2)
DRREADREPLICA=no # IS this DR (east-2) region. Default is set to no
MASTERRDS_REGION="us-west-2" # This parameter only used when creating DR read replica instance.
template='file://./aurora.yaml'
#Setting parameters for DR read replica instance
if [ "$REGION" = "us-east-2" ]; then
# Only Create DR_READREPLICA.
  READREPLICA=no
  DRREADREPLICA=yes
  template='file://./CRR.yaml'
  # arn:aws:rds:<region>:<account number>:<resourcetype>:<name
  # Needed to pass the master db source identified
  MASTER_DB_ARN="arn:aws:rds:us-west-2:${ACCOUNT_ID}:db:${SERVICE}-${ENV}1"
  MASTER_CLUSTER_ARN="arn:aws:rds:us-west-2:${ACCOUNT_ID}:cluster:sreg-prf-auroracluster-jgtks6k4v9c1"  #TODO
fi

# The name should match otherwise the RDS instance creation would fail.
case "$ENV" in
  dev*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
	;;
  rtb*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
	;;
  qa*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
	;;
  e2e*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
	;;
  etoe*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
  ;;
  prf*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=preprd
    MYSQL_IHP_CIDRS="10.x.x.x/24"
	;;
  prd*)
    ## UPDATE AS NECESSARY ####
    ENVIRONMENT=prd
    BAK_RETENTION_PERIOD=7
    MYSQL_IHP_CIDRS="10.x.x.x/24"
    INSTANCE_TYPE='db.r5.2xlarge'
  ;;
  *)
    echo "Not supported - by this script."
    exit 1
	;;
esac

# count number of CIDRs in MYSQL_IHP_CIDRS, start with 0 tp N-1 to match the indexes in Select
# this is used to determine how many Ingress rules to create in the template
MYSQL_CIDR_COUNT=$(echo $MYSQL_IHP_CIDRS | grep -o , | wc -l | sed 's/ //g')

# for now, we have a max of 4 CIDRs defined in the template, so cap at MAX-1
# the rest of CIDRs (after #MAX are passed to template, but ignored by it)
MAX_MYSQL_CIDR_COUNT=11
if [[ $MYSQL_CIDR_COUNT -gt $MAX_MYSQL_CIDR_COUNT ]]; then
    echo "You've passed more MySQL CIDRs ($MYSQL_CIDR_COUNT) than what's supported ($MAX_MYSQL_CIDR_COUNT), extra CIDRS after #$MAX_MYSQL_CIDR_COUNT are ignored. Press enter to continue."; read X
    MYSQL_CIDR_COUNT=$MAX_MYSQL_CIDR_COUNT
fi

MASTERUSERNAME=$SERVICE

echo "Stack being created is $STACK"

aws cloudformation create-stack \
    --stack-name $STACK \
                 --template-body $template \
                 --profile=$PROFILE \
                 --region=$REGION \
                 --parameters \
                   ParameterKey=TagPrefix,ParameterValue=$STACK \
                   ParameterKey=TagComponent,ParameterValue=$SERVICE \
                   ParameterKey=TagEnv,ParameterValue=$ENVIRONMENT \
                   ParameterKey=DBName,ParameterValue=$STACK \
                   ParameterKey=Engine,ParameterValue=$ENGINE \
                   ParameterKey=EngineVersion,ParameterValue=$ENGINEVERSION \
                   ParameterKey=SubnetIds,ParameterValue=\"${SUBNET_IDS%?}\" \
                   ParameterKey=MasterUsername,ParameterValue=$MASTERUSERNAME \
                   ParameterKey=MasterUserPassword,ParameterValue="TypePasswordHere" \
                   ParameterKey=MultiAZ,ParameterValue=$MULTIAZ \
                   ParameterKey=Port,ParameterValue=$PORT \
                   ParameterKey=DBInstanceClass,ParameterValue=$INSTANCE_TYPE \
                   ParameterKey=VpcId,ParameterValue=$VPC_ID \
                   ParameterKey=BackupRetentionPeriod,ParameterValue=$BAK_RETENTION_PERIOD \
                   ParameterKey=DestinationRegion,ParameterValue=$REGION \
                   ParameterKey=MySQLIHPCidrs,ParameterValue=\"$MYSQL_IHP_CIDRS\" \
                   ParameterKey=MySQLIHPCidrCount,ParameterValue=\"$MYSQL_CIDR_COUNT\" \
                   ParameterKey=NeedReadReplica,ParameterValue=$READREPLICA \
                   ParameterKey=DRReadReplica,ParameterValue=$DRREADREPLICA \
                   ParameterKey=SourceRegion,ParameterValue=$MASTERRDS_REGION \
                   ParameterKey=DestinationRegion,ParameterValue=$REGION \
                   ParameterKey=MasterDBARN,ParameterValue=$MASTER_DB_ARN \
                   ParameterKey=MasterClusterARN,ParameterValue=$MASTER_CLUSTER_ARN \
                 --capabilities CAPABILITY_IAM
# Wait for stack to complete before extrapolating the RDS_IDENTIFIER name
echo "Waiting for stack $STACK to complete..."
aws cloudformation wait stack-create-complete --stack-name $STACK --profile $PROFILE --region $REGION
echo "Getting RDS_IDENTIFIER for stack $STACK ..."
# grab RDS_IDENTIFIER
get_stack_output() {
  aws cloudformation describe-stacks --profile $PROFILE --region $REGION --stack-name $STACK | jq -r ".Stacks[0].Outputs[] | select(.OutputKey == \"$2\").OutputValue" | sed 's/ //g'
 }
 RDS_IDENTIFIER=$(get_stack_output $STACK DBIdentifier)

# Get secrets from aws secrets manager
echo " Getting secrets for masteruser of the cluster ..."
echo "Master password retrieved from aws-secrets-mgr successfully ..."

echo " Updating the default master password for RDS instance ..."
echo " Enabling cloudwatch for RDS instance ..."
echo " Enabling IAM role authenticatoin for RDS instance ..."
aws rds modify-db-cluster --profile $PROFILE --region $REGION  \
 --db-cluster-identifier $RDS_IDENTIFIER \
 --master-user-password $MASTERPASSWORD \
 --cloudwatch-logs-export-configuration '{"EnableLogTypes":["audit","error"]}' \
 --enable-iam-database-authentication \
 --apply-immediately

 exit
fi
done
