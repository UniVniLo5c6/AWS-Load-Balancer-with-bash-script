#!/bin/bash

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
INSTANCE_TYPE="t2.micro"
WEB_SERVER_COUNT=3
PROJECT_NAME="aws-lb-lab"

KEY_NAME="vockey"
SSH_KEY_PATH="$HOME/vockey.pem"

CPU_LIMIT=80
RAM_LIMIT=85
DISK_LIMIT=90

# Latest Amazon Linux 2023 AMI
AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --filters \
        "Name=name,Values=al2023-ami-2023*-x86_64" \
        "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)
