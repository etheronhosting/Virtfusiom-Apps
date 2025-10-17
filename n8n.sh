#!/bin/bash
set -e

apt update && apt upgrade -y
apt install -y docker.io docker-compose curl jq openssl

USERNAME="n8nuser"
PASSWORD=$(openssl rand -base64 16)
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

mkdir -p /opt/n8n
cd /opt/n8n

cat <<EOF > docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - GENERIC_TIMEZONE=Europe/Amsterdam
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$USERNAME
      - N8N_BASIC_AUTH_PASSWORD=$PASSWORD
      - WEBHOOK_URL=http://$(hostname -I | awk '{print $1}'):5678/
    volumes:
      - /opt/n8n/.n8n:/home/node/.n8n
EOF

docker-compose up -d

IP=$(hostname -I | awk '{print $1}')
cat <<INFO >/root/n8n_credentials.txt
========================================
✅ n8n is geïnstalleerd!
URL: http://$IP:5678
Gebruikersnaam: $USERNAME
Wachtwoord: $PASSWORD
========================================
INFO

systemctl enable docker
