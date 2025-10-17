#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "🚀 n8n installatie gestart op $(date)"
echo "========================================"

# Wacht tot apt/dpkg vrij is
echo "🔍 Controleren of apt vrij is..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ apt is nog bezig... wachten 10s"
    sleep 10
done

echo "📦 System update uitvoeren..."
apt update -y && apt upgrade -y

echo "⚙️  Vereiste pakketten installeren..."
apt install -y docker.io docker-compose curl jq openssl

# Gebruiker aanmaken
USERNAME="n8nuser"
PASSWORD=$(openssl rand -base64 16)
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
fi

# Docker map aanmaken
echo "📁 n8n-directory aanmaken..."
mkdir -p /opt/n8n/.n8n
chown -R 1000:1000 /opt/n8n/.n8n
chmod -R 755 /opt/n8n/.n8n
cd /opt/n8n

# Docker compose bestand aanmaken
echo "🧩 Docker Compose bestand genereren..."
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

# Start container
echo "🐳 Container starten..."
docker-compose down || true
docker-compose up -d

# Credentials wegschrijven
IP=$(hostname -I | awk '{print $1}')
cat <<INFO >/root/n8n_credentials.txt
========================================
✅ n8n is geïnstalleerd!
URL: http://$IP:5678
Gebruikersnaam: $USERNAME
Wachtwoord: $PASSWORD
Log: $LOGFILE
========================================
INFO

# Docker bij opstarten activeren
systemctl enable docker

echo "🎉 Installatie voltooid!"
echo "Inloggegevens staan in /root/n8n_credentials.txt"
