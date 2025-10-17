#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    sleep 10
done

apt update -y && apt upgrade -y
apt install -y docker.io docker-compose curl jq openssl certbot cron dnsutils

DOMAIN=$(hostname -f)
IP=$(hostname -I | awk '{print $1}')
SSL_ENABLED=false

for i in {1..10}; do
  if ping -c1 8.8.8.8 >/dev/null 2>&1; then break; fi
  sleep 10
done

for i in {1..10}; do
  if dig +short "$DOMAIN" >/dev/null 2>&1; then break; fi
  sleep 10
done

mkdir -p /opt/n8n/.n8n
chown -R 1000:1000 /opt/n8n/.n8n
chmod -R 755 /opt/n8n/.n8n
cd /opt/n8n

RESOLVED_IP=$(dig +short "$DOMAIN" | tail -n1)
if [[ "$RESOLVED_IP" == "$IP" && -n "$RESOLVED_IP" ]]; then
  if certbot certonly --standalone --non-interactive --agree-tos -m admin@$DOMAIN -d "$DOMAIN"; then
    SSL_ENABLED=true
  fi
fi

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  chmod -R 755 /etc/letsencrypt/live || true
  chmod -R 755 /etc/letsencrypt/archive || true
  chmod 644 "$KEY_PATH" || true
  chmod 644 "$CRT_PATH" || true
fi

cat <<EOF > docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
EOF

if [ "$SSL_ENABLED" = true ]; then
cat <<EOF >> docker-compose.yml
      - "80:5678"
      - "443:5678"
    environment:
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - N8N_SSL_KEY=$KEY_PATH
      - N8N_SSL_CERT=$CRT_PATH
EOF
else
cat <<EOF >> docker-compose.yml
      - "5678:5678"
    environment:
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://$IP:5678/
EOF
fi

cat <<EOF >> docker-compose.yml
      - GENERIC_TIMEZONE=Europe/Amsterdam
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - /opt/n8n/.n8n:/home/node/.n8n
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

docker-compose down || true
docker-compose up -d
systemctl enable docker

if [ "$SSL_ENABLED" = true ]; then
  (crontab -l 2>/dev/null; echo "0 3 1 * * certbot renew --quiet && docker-compose -f /opt/n8n/docker-compose.yml restart n8n") | crontab -
fi

echo "n8n installatie voltooid" > /root/n8n_done.txt
