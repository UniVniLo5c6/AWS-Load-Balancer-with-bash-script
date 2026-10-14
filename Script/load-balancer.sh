#!/bin/bash

dnf install -y nginx openssh-server cronie

systemctl enable sshd
systemctl start sshd

systemctl enable crond
systemctl start crond

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh

cat > /home/ec2-user/.ssh/backend_monitor_key <<'SSHKEY'
SSH_PRIVATE_KEY_PLACEHOLDER
SSHKEY

chmod 600 /home/ec2-user/.ssh/backend_monitor_key
chown -R ec2-user:ec2-user /home/ec2-user/.ssh

cat > /etc/nginx/backend-list.txt <<'BACKENDS'
BACKEND_LIST_PLACEHOLDER
BACKENDS

cat > /etc/nginx/conf.d/load-balancer.conf <<'NGINX'
upstream backend_servers {
    server WEB_SERVER_1:80;
    server WEB_SERVER_2:80;
    server WEB_SERVER_3:80;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://backend_servers;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

rm -f /etc/nginx/conf.d/default.conf

mkdir -p /opt/aws-lb-lab

cat > /opt/aws-lb-lab/monitor-backend.sh <<'MONITOR'
MONITOR_BACKEND_PLACEHOLDER
MONITOR

cat > /opt/aws-lb-lab/network-report.sh <<'NETWORK'
NETWORK_REPORT_PLACEHOLDER
NETWORK

cat > /opt/aws-lb-lab/lb-auto-adjust.sh <<'AUTO'
LB_AUTO_ADJUST_PLACEHOLDER
AUTO

chown -R root:root /opt/aws-lb-lab
chmod 755 /opt/aws-lb-lab
chmod 755 /opt/aws-lb-lab/*.sh
# Auto-adjust every minute
cat > /etc/cron.d/aws-lb-monitor <<'CRON'
* * * * * root /opt/aws-lb-lab/lb-auto-adjust.sh >> /var/log/lb-auto-adjust.log 2>&1
CRON

chmod 644 /etc/cron.d/aws-lb-monitor
if nginx -t; then
    systemctl enable --now nginx
else
    echo "ERROR: Nginx configuration validation failed." >&2
    exit 1
fi
systemctl start nginx
systemctl restart nginx
