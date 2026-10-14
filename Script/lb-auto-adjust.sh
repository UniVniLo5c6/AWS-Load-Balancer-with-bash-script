#!/bin/bash

BACKEND_LIST="/etc/nginx/backend-list.txt"
SSH_KEY="/home/ec2-user/.ssh/backend_monitor_key"
NGINX_CONFIG="/etc/nginx/conf.d/load-balancer.conf"

CPU_LIMIT=80
RAM_LIMIT=85
DISK_LIMIT=90

GOOD_BACKENDS=()

echo "========================================"
echo "          LB AUTO ADJUST"
echo "========================================"
echo "Time: $(date)"

while read -r IP; do

    [ -z "$IP" ] && continue

    echo
    echo "Checking backend: $IP"

    if ! curl -s --max-time 3 "http://$IP" > /dev/null; then
        echo "  DOWN: HTTP failed"
        continue
    fi

    CPU=$(ssh \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 \
        "ec2-user@$IP" \
        "top -bn1 | awk '/Cpu\(s\)/ {print 100-\$8}'" \
        2>/dev/null)

    RAM=$(ssh \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 \
        "ec2-user@$IP" \
        "free | awk '/Mem:/ {printf \"%.0f\", \$3/\$2*100}'" \
        2>/dev/null)

    DISK=$(ssh \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 \
        "ec2-user@$IP" \
        "df / | awk 'NR==2 {gsub(\"%\",\"\"); print \$5}'" \
        2>/dev/null)

    if [ -z "$CPU" ] || [ -z "$RAM" ] || [ -z "$DISK" ]; then
        echo "  ERROR: Cannot read system information"
        continue
    fi

    CPU_INT=${CPU%.*}

    echo "  CPU : $CPU%"
    echo "  RAM : $RAM%"
    echo "  Disk: $DISK%"

    if [ "$CPU_INT" -gt "$CPU_LIMIT" ]; then
        echo "  OVERLOAD: CPU"
        continue
    fi

    if [ "$RAM" -gt "$RAM_LIMIT" ]; then
        echo "  OVERLOAD: RAM"
        continue
    fi

    if [ "$DISK" -gt "$DISK_LIMIT" ]; then
        echo "  OVERLOAD: DISK"
        continue
    fi

    echo "  HEALTHY"

    GOOD_BACKENDS+=("$IP")

done < "$BACKEND_LIST"

if [ "${#GOOD_BACKENDS[@]}" -eq 0 ]; then
    echo
    echo "ERROR: No healthy backend."
    exit 1
fi

TMP_CONFIG=$(mktemp)

cat > "$TMP_CONFIG" <<EOF
upstream backend_servers {
EOF

for IP in "${GOOD_BACKENDS[@]}"; do
    echo "    server $IP:80;" >> "$TMP_CONFIG"
done

cat >> "$TMP_CONFIG" <<'EOF'
}

server {
    listen 80;
    server_name _;

    include /etc/nginx/conf.d/static-routes/*.conf;

    location / {
        proxy_pass http://backend_servers;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

cp "$TMP_CONFIG" "$NGINX_CONFIG"

if nginx -t; then

    systemctl reload nginx

    echo
    echo "========================================"
    echo "Nginx updated successfully."
    echo "Healthy backends:"
    printf '%s\n' "${GOOD_BACKENDS[@]}"
    echo "========================================"

else

    echo "ERROR: Invalid Nginx configuration."
    rm -f "$TMP_CONFIG"
    exit 1
fi

rm -f "$TMP_CONFIG"
