#!/bin/bash
 
while :
do
	command=`aws ec2 describe-images --image-id $LATEST_AMI --region $DR_REGION | jq --raw-output '.Images[].State'`
        read command
	if [ "$command" != "pending" ]
	then
		break
	fi
	sleep 20
	echo $command
done