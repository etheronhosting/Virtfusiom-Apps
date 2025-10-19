#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

apt update -y && apt install -y docker.io docker-compose curl jq

DOMAIN=$(hostname -f)
EMAIL="admin@$DOMAIN"

mkdir -p /opt/n8n
cd /opt/n8n

# Docker Compose configuratie
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - GENERIC_TIMEZONE=Europe/Amsterdam
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - web
    expose:
      - "5678"

  caddy:
    image: caddy:latest
    restart: unless-stopped
    environment:
      - ACME_AGREE=true
      - DOMAIN=$DOMAIN
      - EMAIL=$EMAIL
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy_data:/data
      - ./caddy_config:/config
    networks:
      - web
    command: |
      caddy reverse-proxy --from https://$DOMAIN --to n8n:5678

networks:
  web:
    driver: bridge
EOF

docker-compose up -d
systemctl enable docker

echo "✅ n8n installatie voltooid met Caddy proxy"
echo "🌍 Toegang via: https://$DOMAIN"
