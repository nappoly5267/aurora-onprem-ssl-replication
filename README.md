# Repository holding artifacts required to deploy aurora DB
aurora_cf

## Components
1. aurora.sh - bash script that pass values to yaml
2. aurora.yaml: CloudFormation that will create an aurora instance in WEST REGION
3. CRR.yaml: Cloudformation that will create a read-replica in EAST REGION


## Usage:  
To create a new aurora database

1. Login to AWS
5. To run the cloudformation, run: aurora.sh <Servicename> <env> <aws_profile> <region>

NOTE: Stack names have to conform to this naming scheme
appname-env

   aurora.sh <Servicename> <env> <aws_profile> <region>
   servicename: <Application prefix> Examples: app1, app2, app3
   env:  dev/qa/e2e/prf/prd
   aws_profile: The profile name in your credentials file
   region: us-west-2 | us-east-2


## Prerequisites: stash installed on your laptop

## How to store your secrets in idps (if you don't have stash already installed on your laptop)

# Create an API key for your appliance using secrets manager

