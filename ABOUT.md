Project Directory and Setup Guide

1. Project Directory

This project is designed to run in an Ubuntu/Linux environment with AWS CLI and SSH installed.

Default project directory:

~/LAB/

Example directory structure:

LAB/
├── config.sh
├── deploy.sh
├── web-server.sh
├── load-balancer.sh
├── monitor-backend.sh
├── network-report.sh
├── lb-auto-adjust.sh
├── manage-backend.sh
├── manage-frontend.sh
└── ABOUT.md

The following files are generated automatically during deployment or execution and do not need to be committed to GitHub:

lab-info.txt — stores lab configuration and instance information.

backend-list.txt — stores the private IP addresses of backend instances.

cluster-report-*.txt — generated infrastructure monitoring reports.
2. Configuration Paths

Item

Default path

Project directory

~/LAB

AWS lab information

~/LAB/lab-info.txt

SSH private key

~/vockey.pem

Backend list on Load Balancer

/etc/nginx/backend-list.txt

Backend monitoring key on Load Balancer

/home/ec2-user/.ssh/backend_monitor_key

These paths must match the actual environment. If the project directory or SSH key location changes, update the corresponding variables in the scripts.

Example:

DIR="$HOME/LAB"
LAB_INFO="$DIR/lab-info.txt"
LB_KEY="$HOME/vockey.pem"

3. Prerequisites

Ensure the following tools are installed and configured:

AWS CLI

SSH client

Bash

Git

An active AWS Academy lab session with the required EC2 permissions

Check the installed tools:

aws --version
ssh -V
git --version

4. Setup Instructions

Place the project files in ~/LAB/.

Place the authorized SSH private key at ~/vockey.pem, or update the configured path.

Set appropriate permissions for the private key:

chmod 600 ~/vockey.pem

Verify that AWS CLI is configured for the intended lab and region.

Review the settings in config.sh.

Run the deployment script before running monitoring or management scripts that depend on deployed instances.

Make the scripts executable if necessary:

chmod +x ./*.sh