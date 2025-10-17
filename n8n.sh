#!/bin/bash
set -e

# ==========================================
# n8n INSTALL SCRIPT for Debian 12
# By Etheron Hosting
# ==========================================

echo "🔍 Controleren of APT vrij is..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ apt is nog bezig... wachten 10s"
    sleep 10
done

echo "🚀 Updates uitvoeren..."
apt update -y && apt upgrade -y

echo "📦 Vereiste pakketten installeren..."
apt install -y docker.io docker-compose curl jq openssl

echo "👤 Gebruiker aanmaken..."
USERNAME="n8nuser"
PASSWORD=$(openssl rand -base64 16)
id "$USERNAME" &>/dev/null || useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

echo "📁 Docker-map aanmaken..."
mkdir -p /opt/n8n/.n8n
cd /opt/n8n

echo "🧩 Docker Compose bestand aanmaken..."
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

echo "🐳 Container starten..."
docker-compose up -d

echo "📝 Inloggegevens opslaan..."
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
echo "✅ Installatie voltooid!"
echo "Inloggegevens staan in /root/n8n_credentials.txt"
