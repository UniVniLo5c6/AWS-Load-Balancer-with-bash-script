
#!/bin/bash

# Configuration
DIR="$HOME/LAB"
LAB_INFO="$DIR/lab-info.txt"
AWS_REGION=$(awk '/^Region:/ {getline; gsub(/^[[:space:]]+/, ""); print; exit}' "$LAB_INFO")
LB_ID=$(awk '/^Instance ID:/ {print $3; exit}' "$LAB_INFO")
LB_KEY="$HOME/vockey.pem"

REPORT="$DIR/cluster-report-$(date +%Y%m%d-%H%M%S).txt"

# Validate configuration
if [[ ! -f "$LAB_INFO" || -z "$LB_ID" || -z "$AWS_REGION" ]]; then
    echo "Khong doc duoc Region/Instance ID tu $LAB_INFO"
    exit 1
fi

if [[ ! -f "$LB_KEY" ]]; then
    echo "Khong tim thay SSH key: $LB_KEY"
    exit 1
fi

# Get current LB public IP
LB=$(aws ec2 describe-instances \
    --instance-ids "$LB_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text) || exit 1

if [[ -z "$LB" || "$LB" == "None" ]]; then
    echo "Khong lay duoc Public IP cua LB: $LB_ID"
    exit 1
fi

echo "LB Instance: $LB_ID"
echo "LB Public IP: $LB"
echo "Dang thu thap thong so backend..."

# Collect data through LB
ssh -i "$LB_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    "ec2-user@$LB" 'bash -s' <<'REMOTE' | tee "$REPORT"

BACKENDS="/etc/nginx/backend-list.txt"
KEY="/home/ec2-user/.ssh/backend_monitor_key"

echo "========================================"
echo "       LOAD BALANCER CLUSTER REPORT"
echo "========================================"
echo "Thoi gian: $(date)"
echo

if [[ ! -f "$BACKENDS" ]]; then
    echo "ERROR: Khong tim thay $BACKENDS"
    exit 1
fi

while IFS= read -r IP || [[ -n "$IP" ]]; do
    IP=${IP%$'\r'}
    [[ -z "$IP" || "$IP" == \#* ]] && continue

    echo "----------------------------------------"
    echo "BACKEND: $IP"
    echo "----------------------------------------"

    ssh -i "$KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "ec2-user@$IP" 'bash -s' <<'BACKEND'
echo "Hostname: $(hostname)"


echo
echo "[CPU]"
read -r _ u n s id wa irq sirq st _ < /proc/stat
IDLE1=$((id + wa))
TOTAL1=$((u + n + s + id + wa + irq + sirq + st))
sleep 1
read -r _ u n s id wa irq sirq st _ < /proc/stat
IDLE2=$((id + wa))
TOTAL2=$((u + n + s + id + wa + irq + sirq + st))
awk -v t1="$TOTAL1" -v t2="$TOTAL2" \
    -v i1="$IDLE1" -v i2="$IDLE2" \
    'BEGIN {d=t2-t1; if(d>0) printf "CPU Usage: %.1f%%\n",100*(d-(i2-i1))/d; else print "CPU Usage: N/A"}'

echo
echo "[RAM USED]"
free -h | awk '/^Mem:/ {print "Used: "$3" / Total: "$2}'

echo
echo "[DISK]"
df -h -x tmpfs -x devtmpfs

echo
echo "[NETWORK RX/TX BYTES]"
for f in /sys/class/net/*; do
    IFACE=${f##*/}
    echo "$IFACE: RX=$(cat "$f/statistics/rx_bytes") bytes, TX=$(cat "$f/statistics/tx_bytes") bytes"
done

echo
echo "[PROCESS / THREAD]"
printf "Total processes: "
ps -e --no-headers | wc -l
printf "Running processes: "
ps -eo stat= | awk '$1 ~ /^R/ {n++} END {print n+0}'
printf "Total threads: "
ps -eLo tid= | wc -l
BACKEND

    if [[ $? -ne 0 ]]; then
        echo "WARNING: Khong thu thap duoc du lieu tu $IP"
    fi
    echo
done < "$BACKENDS"

REMOTE

SSH_STATUS=${PIPESTATUS[0]}

if [[ "$SSH_STATUS" -ne 0 ]]; then
    echo "Loi SSH vao LB hoac thu thap bao cao that bai."
    exit 1
fi

echo
echo "Bao cao da luu tai: $REPORT"
