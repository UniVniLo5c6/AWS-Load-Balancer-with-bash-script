
#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

DIR="$HOME/LAB"
LAB_INFO="$DIR/lab-info.txt"
REGION=$(awk '/^Region:/ {getline; gsub(/^[[:space:]]+/, ""); print; exit}' "$LAB_INFO")
LB_ID=$(awk '/^Instance ID:/ {print $3; exit}' "$LAB_INFO")
SSH_KEY="$HOME/vockey.pem"

WEB_ROOT="/var/www/static"
ROUTE_DIR="/etc/nginx/conf.d/static-routes"

usage() {
    echo "Usage:"
    echo "  $0 add <ROUTE> <HTML_FILE>"
    echo "  $0 remove <ROUTE>"
    echo "  $0 list"
    exit 1
}

[[ -n "$LB_ID" && -n "$REGION" ]] || {
    echo "ERROR: Cannot read LB configuration from lab-info.txt"
    exit 1
}

[[ -f "$SSH_KEY" ]] || {
    echo "ERROR: SSH key not found: $SSH_KEY"
    exit 1
}

LB_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$LB_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text) || exit 1

[[ -n "$LB_IP" && "$LB_IP" != "None" ]] || {
    echo "ERROR: Cannot get LB public IP"
    exit 1
}

ssh_lb() {
    ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "ec2-user@$LB_IP" "$@"
}

case "$1" in
    add)
        ROUTE="${2:-}"
        HTML_FILE="${3:-}"

        [[ "$ROUTE" =~ ^/[a-zA-Z0-9_-]+/?$ ]] || {
            echo "Route must look like /web1 or /web1/"
            exit 1
        }

        [[ -f "$HTML_FILE" ]] || {
            echo "HTML file not found: $HTML_FILE"
            exit 1
        }

        ROUTE="${ROUTE%/}"
        NAME="${ROUTE#/}"

        ssh_lb "sudo mkdir -p '$WEB_ROOT/$NAME' '$ROUTE_DIR'"

        ssh_lb "sudo test ! -e '$ROUTE_DIR/$NAME.conf'" || {
            echo "Route already exists: $ROUTE/"
            exit 1
        }

        cat "$HTML_FILE" | ssh -i "$SSH_KEY" \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            "ec2-user@$LB_IP" \
            "sudo tee '$WEB_ROOT/$NAME/index.html' >/dev/null" || exit 1

cat <<EOF | ssh_lb "sudo tee '$ROUTE_DIR/$NAME.conf' >/dev/null"
location ^~ $ROUTE/ {
    alias $WEB_ROOT/$NAME/;
    index index.html;
    default_type text/html;
}
location = $ROUTE {
    return 301 $ROUTE/;
}
EOF

        if ssh_lb "sudo nginx -t"; then
            ssh_lb "sudo systemctl reload nginx"
            echo "Added: http://$LB_IP$ROUTE/"
        else
            ssh_lb "sudo rm -f '$ROUTE_DIR/$NAME.conf' '$WEB_ROOT/$NAME/index.html'"
            echo "ERROR: Nginx configuration invalid"
            exit 1
        fi
        ;;

    remove)
        ROUTE="${2:-}"
        [[ "$ROUTE" =~ ^/[a-zA-Z0-9_-]+/?$ ]] || usage

        ROUTE="${ROUTE%/}"
        NAME="${ROUTE#/}"

        ssh_lb "sudo test -f '$ROUTE_DIR/$NAME.conf'" || {
            echo "Route does not exist: $ROUTE"
            exit 1
        }

        ssh_lb "sudo rm -f '$ROUTE_DIR/$NAME.conf' '$WEB_ROOT/$NAME/index.html' &&
            sudo nginx -t && sudo systemctl reload nginx"

        echo "Removed route: $ROUTE"
        ;;

    list)
        echo "Static routes on LB:"
        ssh_lb "sudo find '$ROUTE_DIR' -maxdepth 1 -name '*.conf' -printf '%f\n' 2>/dev/null"
        ;;

    *)
        usage
        ;;
esac
