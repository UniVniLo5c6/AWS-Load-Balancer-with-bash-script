#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
KEY_NAME="vockey"
SSH_KEY="$HOME/vockey.pem"

LAB_INFO="$(dirname "$(realpath "$0")")/lab-info.txt"

LB_INSTANCE_ID="${LB_INSTANCE_ID:-$(awk '/Instance ID:/ {print $3; exit}' "$LAB_INFO" | tr -d '\r')}"
LB_PUBLIC_IP="${LB_PUBLIC_IP:-$(awk '/Public IP:/ {print $3; exit}' "$LAB_INFO" | tr -d '\r')}"

REMOTE_LIST="/etc/nginx/backend-list.txt"
REMOTE_CONFIG="/etc/nginx/conf.d/load-balancer.conf"

usage() {
    echo "Usage:"
    echo "  $0 add <BACKEND_PRIVATE_IP>"
    echo "  $0 remove <BACKEND_PRIVATE_IP>"
    echo "  $0 list"
    exit 1
}

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

if [ -z "$LB_IP" ] || [ "$LB_IP" = "None" ]; then
    echo "ERROR: Cannot find LB public IP."
    exit 1
fi

ssh_lb() {
    ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "ec2-user@$LB_IP" "$@"
}

case "$1" in

    add)

        IP="$2"

        [ -n "$IP" ] || usage

        ssh_lb "sudo grep -qx '$IP' '$REMOTE_LIST' 2>/dev/null" &&
        {
            echo "Backend $IP already exists."
            exit 1
        }

        ssh_lb "echo '$IP' | sudo tee -a '$REMOTE_LIST' > /dev/null"

        echo "Backend added: $IP"

        ssh_lb "sudo /opt/aws-lb-lab/lb-auto-adjust.sh"

        ;;

    remove)

        IP="$2"

        [ -n "$IP" ] || usage

        ssh_lb "sudo grep -qx '$IP' '$REMOTE_LIST' 2>/dev/null" ||
        {
            echo "Backend $IP does not exist."
            exit 1
        }

        ssh_lb "sudo sed -i '\|^$IP\$|d' '$REMOTE_LIST'"

        echo "Backend removed: $IP"

        ssh_lb "sudo /opt/aws-lb-lab/lb-auto-adjust.sh"

        ;;

    list)

        echo "Current backends:"
        ssh_lb "sudo cat '$REMOTE_LIST'"

        ;;

    *)

        usage

        ;;

esac
