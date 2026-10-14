#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SSH_KEY="$HOME/vockey.pem"

LB_INSTANCE_ID="${LB_INSTANCE_ID:-}"
LB_PUBLIC_IP="${LB_PUBLIC_IP:-}"

REPORT="network-report-$(date +%Y%m%d-%H%M%S).txt"

get_lb_ip() {

    if [ -n "$LB_PUBLIC_IP" ]; then
        echo "$LB_PUBLIC_IP"
        return
    fi

    if [ -n "$LB_INSTANCE_ID" ]; then
        aws ec2 describe-instances \
            --region "$REGION" \
            --instance-ids "$LB_INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text
        return
    fi

    echo "ERROR: LB_PUBLIC_IP or LB_INSTANCE_ID is not set."
    exit 1
}

LB_IP=$(get_lb_ip)

echo "========================================" > "$REPORT"
echo "       LOAD BALANCER CLUSTER REPORT" >> "$REPORT"
echo "========================================" >> "$REPORT"
echo "Generated: $(date)" >> "$REPORT"
echo "Load Balancer: $LB_IP" >> "$REPORT"
echo >> "$REPORT"

ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    "ec2-user@$LB_IP" \
    "sudo bash -s" >> "$REPORT" <<'REMOTE'

BACKEND_LIST="/etc/nginx/backend-list.txt"
SSH_KEY="/home/ec2-user/.ssh/backend_monitor_key"

while read -r IP; do

    [ -z "$IP" ] && continue

    echo "========================================"
    echo "BACKEND: $IP"
    echo "========================================"

    ssh -n \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "ec2-user@$IP" 'bash -s' <<'BACKEND'

echo "[HOST]"
hostname

echo
echo "[CPU]"
awk '/^cpu / {
    idle=$5
    total=0
    for(i=2;i<=NF;i++) total+=$i
    printf "%.1f%%\n",100-(idle*100/total)
}' /proc/stat

echo
echo "[RAM]"
free -h

echo
echo "[DISK]"
df -h /

echo
echo "[NETWORK INTERFACES]"
ip -br addr

echo
echo "[NETWORK TRAFFIC]"
cat /proc/net/dev

echo
echo "[PROCESS COUNT]"
ps -e --no-headers | wc -l

echo
echo "[THREAD COUNT]"
ps -eL --no-headers | wc -l

echo
echo "[NGINX STATUS]"
systemctl is-active nginx

BACKEND

done < "$BACKEND_LIST"

REMOTE

echo
echo "Report generated:"
echo "$REPORT"
