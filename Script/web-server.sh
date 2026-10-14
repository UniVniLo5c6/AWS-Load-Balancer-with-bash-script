#!/bin/bash
set -euo pipefail

dnf install -y nginx
systemctl enable --now nginx

TOKEN=$(curl -fsS --connect-timeout 2 --max-time 5 \
    -X PUT \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -fsS --connect-timeout 2 --max-time 5 \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

PRIVATE_IP=$(curl -fsS --connect-timeout 2 --max-time 5 \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)

HOSTNAME=$(hostname)

cat > /usr/share/nginx/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>AWS Load Balancer Lab</title>
</head>
<body>
<h1>AWS Load Balancer Lab</h1>
<h2>Backend Web Server</h2>
<p><b>Hostname:</b> $HOSTNAME</p>
<p><b>Instance ID:</b> $INSTANCE_ID</p>
<p><b>Private IP:</b> $PRIVATE_IP</p>
<hr>
<p>This page is served by an EC2 Web Server.</p>
</body>
</html>
HTML

install -d -o ec2-user -g ec2-user -m 700 /home/ec2-user/.ssh

PUBLIC_KEY='SSH_PUBLIC_KEY_PLACEHOLDER'

if [[ "$PUBLIC_KEY" == "SSH_PUBLIC_KEY_PLACEHOLDER" ]]; then
    echo "ERROR: SSH public key placeholder was not replaced." >&2
    exit 1
fi

if [[ ! "$PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
    echo "ERROR: SSH public key format appears invalid." >&2
    exit 1
fi

touch /home/ec2-user/.ssh/authorized_keys
grep -qxF "$PUBLIC_KEY" /home/ec2-user/.ssh/authorized_keys ||
    printf '%s\n' "$PUBLIC_KEY" >> /home/ec2-user/.ssh/authorized_keys

chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys