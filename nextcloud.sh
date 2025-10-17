#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/nextcloud-install.log"
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

mkdir -p /opt/nextcloud/data
cd /opt/nextcloud

# --- MariaDB wachtwoord genereren ---
DB_ROOT_PASS=$(openssl rand -base64 16)
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASS=$(openssl rand -base64 12)

# --- SSL aanmaken indien domein resolvable ---
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

# --- docker-compose.yml genereren ---
cat <<EOF > docker-compose.yml
version: "3"
services:
  db:
    image: mariadb:11
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    volumes:
      - db_data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=$DB_ROOT_PASS
      - MYSQL_DATABASE=$DB_NAME
      - MYSQL_USER=$DB_USER
      - MYSQL_PASSWORD=$DB_PASS

  app:
    image: nextcloud
    restart: always
    ports:
EOF

if [ "$SSL_ENABLED" = true ]; then
cat <<EOF >> docker-compose.yml
      - "80:80"
      - "443:443"
    environment:
      - NEXTCLOUD_TRUSTED_DOMAINS=$DOMAIN
      - OVERWRITEPROTOCOL=https
      - APACHE_DISABLE_REWRITE_IP=1
      - APACHE_SSL_CERTIFICATE=$CRT_PATH
      - APACHE_SSL_CERTIFICATE_KEY=$KEY_PATH
EOF
else
cat <<EOF >> docker-compose.yml
      - "80:80"
    environment:
      - NEXTCLOUD_TRUSTED_DOMAINS=$IP
EOF
fi

cat <<EOF >> docker-compose.yml
      - MYSQL_PASSWORD=$DB_PASS
      - MYSQL_DATABASE=$DB_NAME
      - MYSQL_USER=$DB_USER
      - MYSQL_HOST=db
    depends_on:
      - db
    volumes:
      - nextcloud_data:/var/www/html
volumes:
  db_data:
  nextcloud_data:
EOF

docker-compose down || true
docker-compose up -d
systemctl enable docker

# --- SSL auto-renew ---
if [ "$SSL_ENABLED" = true ]; then
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && docker-compose -f /opt/nextcloud/docker-compose.yml restart app") | crontab -
fi

# --- Info ---
cat <<INFO >/root/nextcloud_info.txt
Nextcloud geïnstalleerd
URL: $( [ "$SSL_ENABLED" = true ] && echo "https://$DOMAIN" || echo "http://$IP" )
DB: $DB_NAME
DB user: $DB_USER
DB password: $DB_PASS
DB root password: $DB_ROOT_PASS
INFO
