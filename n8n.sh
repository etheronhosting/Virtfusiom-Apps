#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "🚀 n8n installatie gestart op $(date)"
echo "========================================"

# --- APT locks ---
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ apt is nog bezig... wachten 10s"
    sleep 10
done

echo "📦 Updates & vereisten..."
apt update -y && apt upgrade -y
apt install -y docker.io docker-compose curl jq openssl certbot cron

USERNAME="n8nuser"
PASSWORD=$(openssl rand -base64 16)
id "$USERNAME" &>/dev/null || { useradd -m -s /bin/bash "$USERNAME"; echo "$USERNAME:$PASSWORD" | chpasswd; }

DOMAIN=$(hostname)
IP=$(hostname -I | awk '{print $1}')
SSL_ENABLED=false

mkdir -p /opt/n8n/.n8n
chown -R 1000:1000 /opt/n8n/.n8n
chmod -R 755 /opt/n8n/.n8n
cd /opt/n8n

echo "🌍 Controleren of $DOMAIN publiek bereikbaar is..."
if host "$DOMAIN" >/dev/null 2>&1; then
  RESOLVED_IP=$(dig +short "$DOMAIN" | tail -n1)
  if [[ "$RESOLVED_IP" == "$IP" ]]; then
    echo "✅ DNS klopt, proberen Let's Encrypt..."
    if certbot certonly --standalone --non-interactive --agree-tos -m admin@$DOMAIN -d "$DOMAIN"; then
      SSL_ENABLED=true
    else
      echo "⚠️ Certbot is mislukt, ga verder zonder SSL."
    fi
  else
    echo "⚠️ DNS verwijst naar ander IP ($RESOLVED_IP), SSL overgeslagen."
  fi
else
  echo "⚠️ Domein niet resolvable, SSL overgeslagen."
fi

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

echo "🧩 Docker Compose genereren..."
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
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$USERNAME
      - N8N_BASIC_AUTH_PASSWORD=$PASSWORD
    volumes:
      - /opt/n8n/.n8n:/home/node/.n8n
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

echo "🐳 n8n container starten..."
docker-compose down || true
docker-compose up -d

cat <<INFO >/root/n8n_credentials.txt
========================================
✅ n8n is geïnstalleerd!
$(if [ "$SSL_ENABLED" = true ]; then echo "URL: https://$DOMAIN"; else echo "URL: http://$IP:5678"; fi)
Gebruikersnaam: $USERNAME
Wachtwoord: $PASSWORD
Logbestand: $LOGFILE
========================================
INFO

systemctl enable docker

# --- SSL-auto-renewal ---
if [ "$SSL_ENABLED" = true ]; then
  echo "🔄 SSL-vernieuwing elke maand..."
  (crontab -l 2>/dev/null; echo "0 3 1 * * certbot renew --quiet && docker-compose -f /opt/n8n/docker-compose.yml restart n8n") | crontab -
else
  echo "ℹ️  SSL niet ingesteld; voeg DNS toe en run later handmatig:"
  echo "certbot certonly --standalone -d $DOMAIN && docker-compose -f /opt/n8n/docker-compose.yml restart n8n"
fi

echo "🎉 Installatie klaar!"
