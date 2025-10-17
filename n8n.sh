#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "🚀 n8n installatie gestart op $(date)"
echo "========================================"

# --- Wacht tot apt/dpkg vrij is ---
echo "🔍 Controleren of apt vrij is..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ apt is nog bezig... wachten 10s"
    sleep 10
done

echo "📦 System update uitvoeren..."
apt update -y && apt upgrade -y

echo "⚙️  Vereiste pakketten installeren..."
apt install -y docker.io docker-compose curl jq openssl certbot

# --- Gebruiker aanmaken ---
USERNAME="n8nuser"
PASSWORD=$(openssl rand -base64 16)
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
fi

# --- Domein ophalen ---
DOMAIN=$(hostname)
IP=$(hostname -I | awk '{print $1}')
echo "🌐 Domein: $DOMAIN"

# --- n8n map aanmaken met juiste rechten ---
mkdir -p /opt/n8n/.n8n
chown -R 1000:1000 /opt/n8n/.n8n
chmod -R 755 /opt/n8n/.n8n
cd /opt/n8n

# --- Tijdelijk container starten om certbot te kunnen draaien ---
docker-compose down || true
docker-compose up -d
sleep 10

# --- Certbot gebruiken om SSL te genereren ---
echo "🔐 Let's Encrypt SSL aanvragen voor $DOMAIN..."
certbot certonly --standalone --non-interactive --agree-tos -m admin@$DOMAIN -d "$DOMAIN" || {
    echo "⚠️ SSL-aanvraag mislukt, n8n draait voorlopig via HTTP"
    SSL_ENABLED=false
}

# --- Certificaatpaden ---
CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# --- Docker Compose bestand aanmaken ---
echo "🧩 Docker Compose bestand genereren..."
cat <<EOF > docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "80:5678"
      - "443:5678"
    environment:
      - GENERIC_TIMEZONE=Europe/Amsterdam
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$USERNAME
      - N8N_BASIC_AUTH_PASSWORD=$PASSWORD
      - WEBHOOK_URL=https://$DOMAIN/
      - N8N_PROTOCOL=https
      - N8N_SSL_KEY=$KEY_PATH
      - N8N_SSL_CERT=$CRT_PATH
    volumes:
      - /opt/n8n/.n8n:/home/node/.n8n
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

# --- n8n herstarten met SSL ---
echo "🔁 n8n herstarten met HTTPS..."
docker-compose down || true
docker-compose up -d

# --- Credentials wegschrijven ---
cat <<INFO >/root/n8n_credentials.txt
========================================
✅ n8n is geïnstalleerd!
URL: https://$DOMAIN
Gebruikersnaam: $USERNAME
Wachtwoord: $PASSWORD
Logbestand: $LOGFILE
========================================
INFO

systemctl enable docker

echo "🎉 Installatie voltooid!"
echo "Inloggegevens staan in /root/n8n_credentials.txt"
