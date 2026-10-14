#!/bin/bash

set -e

source ./config.sh

echo "========================================"
echo "       AWS LOAD BALANCER LAB"
echo "========================================"

echo
echo "[1] Checking AWS credentials..."

aws sts get-caller-identity \
    --region "$REGION" > /dev/null

echo "AWS credentials: OK"

echo
echo "[2] Checking SSH key..."

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH private key not found:"
    echo "$SSH_KEY_PATH"
    exit 1
fi

chmod 400 "$SSH_KEY_PATH"

SSH_PUBLIC_KEY=$(ssh-keygen -y -f "$SSH_KEY_PATH")
SSH_PRIVATE_KEY=$(cat "$SSH_KEY_PATH")

echo "SSH key: OK"

echo
echo "[3] Finding Default VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: Default VPC not found."
    exit 1
fi

echo "VPC: $VPC_ID"

echo
echo "[4] Finding public subnet..."

SUBNET_ID=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters \
        "Name=vpc-id,Values=$VPC_ID" \
        "Name=map-public-ip-on-launch,Values=true" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: Public subnet not found."
    exit 1
fi

echo "Subnet: $SUBNET_ID"

echo
echo "[5] Finding Amazon Linux 2023 AMI..."

AMI_ID=$(aws ssm get-parameter \
    --region "$REGION" \
    --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
    --query 'Parameter.Value' \
    --output text)

echo "AMI: $AMI_ID"

RUN_ID=$(date +%s)

LB_SG_NAME="${PROJECT_NAME}-lb-sg-$RUN_ID"
WEB_SG_NAME="${PROJECT_NAME}-web-sg-$RUN_ID"

echo
echo "[6] Creating Load Balancer Security Group..."

LB_SG=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$LB_SG_NAME" \
    --description "Load Balancer Security Group" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

echo "DEBUG: LB_SG=$LB_SG"

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$LB_SG" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$LB_SG" \
    --protocol tcp \
    --port 22 \
    --cidr "$(curl -s https://checkip.amazonaws.com)/32"

echo "LB SG: $LB_SG"

echo
echo "[7] Creating Web Server Security Group..."

WEB_SG=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$WEB_SG_NAME" \
    --description "Backend Web Server Security Group" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$WEB_SG" \
    --protocol tcp \
    --port 80 \
    --source-group "$LB_SG"

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$WEB_SG" \
    --protocol tcp \
    --port 22 \
    --source-group "$LB_SG"

echo "Web SG: $WEB_SG"

echo
echo "[8] Preparing Web Server User Data..."

WEB_USER_DATA=$(sed \
    "s|SSH_PUBLIC_KEY_PLACEHOLDER|$SSH_PUBLIC_KEY|g" \
    web-server.sh)

echo
echo "[9] Creating Web Servers..."

WEB_IDS=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --count "$WEB_SERVER_COUNT" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$WEB_SG" \
    --associate-public-ip-address \
    --key-name "$KEY_NAME" \
    --user-data "$WEB_USER_DATA" \
    --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=LB-Lab-WebServer}]' \
    --query 'Instances[*].InstanceId' \
    --output text)

echo "Web Server IDs:"
echo "$WEB_IDS"

echo
echo "[10] Waiting for Web Servers..."

aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids $WEB_IDS

echo "Web Servers are running."

echo
echo "[11] Getting Backend Private IPs..."

read -ra WEB_IPS <<< "$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids $WEB_IDS \
    --query 'Reservations[*].Instances[*].PrivateIpAddress' \
    --output text)"

if [ "${#WEB_IPS[@]}" -ne "$WEB_SERVER_COUNT" ]; then
    echo "ERROR: Backend IP count does not match."
    exit 1
fi

printf "%s\n" "${WEB_IPS[@]}" > backend-list.txt

echo "Backend IPs:"
cat backend-list.txt

echo
echo "[12] Preparing Load Balancer User Data..."

BACKEND_LIST=$(cat backend-list.txt)

# Encode SSH private key để tránh lỗi khi nhúng nhiều dòng
SSH_KEY_B64=$(base64 -w0 "$SSH_KEY_PATH")

# Encode các script monitoring
MONITOR_B64=$(base64 -w0 monitor-backend.sh)
NETWORK_B64=$(base64 -w0 network-report.sh)
AUTO_B64=$(base64 -w0 lb-auto-adjust.sh)

cat > /tmp/lb-user-data.sh <<EOF
#!/bin/bash
dnf install -y openssh-server nginx cronie

systemctl disable --now firewalld 2>/dev/null || true
systemctl disable --now nftables 2>/dev/null || true

systemctl enable --now crond

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh

# Install SSH private key
echo "$SSH_KEY_B64" | base64 -d > /home/ec2-user/.ssh/backend_monitor_key
chmod 600 /home/ec2-user/.ssh/backend_monitor_key
chown ec2-user:ec2-user /home/ec2-user/.ssh/backend_monitor_key

# Backend list
mkdir -p /opt/aws-lb-lab

cat > /etc/nginx/backend-list.txt <<'BACKENDS'
$BACKEND_LIST
BACKENDS

# Install monitoring scripts
echo "$MONITOR_B64" | base64 -d > /opt/aws-lb-lab/monitor-backend.sh
echo "$NETWORK_B64" | base64 -d > /opt/aws-lb-lab/network-report.sh
echo "$AUTO_B64" | base64 -d > /opt/aws-lb-lab/lb-auto-adjust.sh

# Restrict script ownership and write permissions
chown -R root:root /opt/aws-lb-lab
chmod 755 /opt/aws-lb-lab
chmod 755 /opt/aws-lb-lab/*.sh

# Backup default Nginx configuration
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.default

cat > /etc/nginx/nginx.conf <<'NGINX_MAIN'
user nginx;
worker_processes auto;

error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
}
NGINX_MAIN

# Nginx Load Balancer
cat > /etc/nginx/conf.d/load-balancer.conf <<'NGINX'
upstream backend_servers {
    server ${WEB_IPS[0]}:80;
    server ${WEB_IPS[1]}:80;
    server ${WEB_IPS[2]}:80;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://backend_servers;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf

# Auto-adjust every minute
cat > /etc/cron.d/aws-lb-monitor <<'CRON'
* * * * *  /opt/aws-lb-lab/lb-auto-adjust.sh >> /var/log/lb-auto-adjust.log 2>&1
CRON

chmod 644 /etc/cron.d/aws-lb-monitor

echo "===== FIREWALL STATUS =====" > /usr/share/nginx/html/firewall-debug.txt

echo >> /usr/share/nginx/html/firewall-debug.txt
echo "=== firewalld ===" >> /usr/share/nginx/html/firewall-debug.txt
systemctl is-active firewalld >> /usr/share/nginx/html/firewall-debug.txt 2>&1

echo >> /usr/share/nginx/html/firewall-debug.txt
echo "=== nftables ===" >> /usr/share/nginx/html/firewall-debug.txt
systemctl is-active nftables >> /usr/share/nginx/html/firewall-debug.txt 2>&1
nft list ruleset >> /usr/share/nginx/html/firewall-debug.txt 2>&1

echo >> /usr/share/nginx/html/firewall-debug.txt
echo "=== iptables ===" >> /usr/share/nginx/html/firewall-debug.txt
iptables -L -n -v >> /usr/share/nginx/html/firewall-debug.txt 2>&1

chmod 644 /usr/share/nginx/html/firewall-debug.txt

nginx -t

systemctl enable nginx
systemctl start nginx
systemctl restart nginx

# Configure SSH server
ssh-keygen -A

# Validate SSH configuration
sshd -t

echo "=== SSHD DEBUG ===" > /var/log/aws-lb-lab/sshd-debug.log

ssh-keygen -A >> /var/log/aws-lb-lab/sshd-debug.log 2>&1
sshd -t >> /var/log/aws-lb-lab/sshd-debug.log 2>&1

systemctl enable sshd >> /var/log/aws-lb-lab/sshd-debug.log 2>&1
systemctl restart sshd >> /var/log/aws-lb-lab/sshd-debug.log 2>&1

echo "=== STATUS ===" >> /var/log/aws-lb-lab/sshd-debug.log
systemctl status sshd --no-pager >> /var/log/aws-lb-lab/sshd-debug.log 2>&1

echo "=== LISTEN ===" >> /var/log/aws-lb-lab/sshd-debug.log
ss -lntp | grep ':22' >> /var/log/aws-lb-lab/sshd-debug.log 2>&1
EOF
echo
echo "[13] Creating Load Balancer..."

LB_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --count 1 \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$LB_SG" \
    --associate-public-ip-address \
    --key-name "$KEY_NAME" \
    --user-data file:///tmp/lb-user-data.sh \
    --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=LB-Lab-LoadBalancer}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "Load Balancer ID: $LB_ID"

echo
echo "[14] Waiting for Load Balancer..."

aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids "$LB_ID"

echo "Load Balancer is running."

LB_PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$LB_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

LB_PRIVATE_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$LB_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

cat > lab-info.txt <<EOF
AWS Load Balancer Lab
=====================

Region:
$REGION

VPC:
$VPC_ID

Subnet:
$SUBNET_ID

Load Balancer:
Instance ID: $LB_ID
Public IP: $LB_PUBLIC_IP
Private IP: $LB_PRIVATE_IP
Security Group: $LB_SG

Backend Web Servers:
EOF

for i in "${!WEB_IPS[@]}"; do
    echo "Backend $((i+1)): ${WEB_IPS[$i]}" >> lab-info.txt
done

cat >> lab-info.txt <<EOF

Web Security Group:
$WEB_SG

Backend list:
$(cat backend-list.txt)
EOF

echo
echo "========================================"
echo "        DEPLOYMENT COMPLETED"
echo "========================================"

cat lab-info.txt

echo
echo "Test:"
echo "curl http://$LB_PUBLIC_IP"
