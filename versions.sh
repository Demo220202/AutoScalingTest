#!/bin/bash
if [ "$LT_VERSION" = "0" ]
then
   SOURCE_VERSION=$(aws ec2 describe-launch-templates --launch-template-id $LAUNCH_TEMPLATE_ID  --region $ASG_REGION  | jq  '.LaunchTemplates[].LatestVersionNumber')
   echo "$SOURCE_VERSION" > latest_lt_version.txt
   
else
   echo "$LT_VERSION" > latest_lt_version.txt
  
fi