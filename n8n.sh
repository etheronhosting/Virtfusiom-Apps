#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/n8n-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "🚀 n8n installatie gestart op $(date)"
echo "========================================"

# --- APT locks voorkomen ---
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ apt is nog bezig... wachten 10s"
    sleep 10
done

echo "📦 Updates & vereisten..."
apt update -y && apt upgrade -y
apt install -y docker.io docker-compose curl jq openssl certbot cron dnsutils

# --- Domein & IP bepalen ---
DOMAIN=$(hostname -f)
IP=$(hostname -I | awk '{print $1}')
SSL_ENABLED=false

# --- Netwerkcheck ---
echo "🌐 Controleren of netwerk actief is..."
for i in {1..10}; do
  if ping -c1 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ Internet werkt."
    break
  fi
  echo "⏳ Geen verbinding... poging $i/10, wachten 10s"
  sleep 10
done

echo "🔍 Controleren of $DOMAIN resolveert..."
for i in {1..10}; do
  if dig +short "$DOMAIN" >/dev/null 2>&1; then
    echo "✅ DNS-resolving OK."
    break
  fi
  echo "⏳ Wachten tot DNS resolvable is... poging $i/10"
  sleep 10
done

# --- Datamap ---
mkdir -p /opt/n8n/.n8n
chown -R 1000:1000 /opt/n8n/.n8n
chmod -R 755 /opt/n8n/.n8n
cd /opt/n8n

# --- Let's Encrypt certificaat aanvragen ---
RESOLVED_IP=$(dig +short "$DOMAIN" | tail -n1)
if [[ "$RESOLVED_IP" == "$IP" && -n "$RESOLVED_IP" ]]; then
  echo "🌍 DNS verwijst correct ($RESOLVED_IP), probeer Let's Encrypt..."
  if certbot certonly --standalone --non-interactive --agree-tos -m admin@$DOMAIN -d "$DOMAIN"; then
    SSL_ENABLED=true
    echo "✅ SSL-certificaat geïnstalleerd."
  else
    echo "⚠️ Certbot mislukt, verder zonder SSL."
  fi
else
  echo "⚠️ DNS mismatch of niet resolvable ($RESOLVED_IP), overslaan SSL."
fi

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# --- SSL permissies fixen ---
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "🔒 Permissies fixen voor SSL-mappen en bestanden..."
  chmod -R 755 /etc/letsencrypt/live || true
  chmod -R 755 /etc/letsencrypt/archive || true
  chmod 644 "$KEY_PATH" || true
  chmod 644 "$CRT_PATH" || true
fi

# --- Docker Compose aanmaken ---
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
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - /opt/n8n/.n8n:/home/node/.n8n
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF

# --- Container starten ---
echo "🐳 n8n container starten..."
docker-compose down || true
docker-compose up -d

# --- Output ---
cat <<INFO >/root/n8n_install_info.txt
========================================
✅ n8n is geïnstalleerd!
$(if [ "$SSL_ENABLED" = true ]; then echo "URL: https://$DOMAIN"; else echo "URL: http://$IP:5678"; fi)
📜 Logbestand: $LOGFILE
========================================
INFO

systemctl enable docker

# --- SSL-auto-renewal ---
if [ "$SSL_ENABLED" = true ]; then
  echo "🔄 SSL-vernieuwing gepland..."
  (crontab -l 2>/dev/null; echo "0 3 1 * * certbot renew --quiet && docker-compose -f /opt/n8n/docker-compose.yml restart n8n") | crontab -
else
  echo "ℹ️ SSL niet ingesteld; run later handmatig:"
  echo "certbot certonly --standalone -d $DOMAIN && docker-compose -f /opt/n8n/docker-compose.yml restart n8n"
fi

echo "🎉 Installatie voltooid op $(date)"
echo "🌐 Open de setup wizard in je browser en maak het eerste admin-account aan."
