#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/nextcloud-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Basisinstallatie ---
apt update -y && apt upgrade -y
apt install -y docker.io docker-compose curl jq openssl dnsutils

# --- Variabelen ---
DOMAIN=$(hostname -f)
IP=$(hostname -I | awk '{print $1}')
DB_ROOT_PASS=$(openssl rand -base64 16)
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASS=$(openssl rand -base64 12)
EMAIL="admin@$DOMAIN"

mkdir -p /opt/nextcloud/{db_data,app_data,proxy_data,certs}
cd /opt/nextcloud

# --- docker-compose.yml ---
cat <<EOF > docker-compose.yml
version: "3"

services:
  nginx-proxy:
    image: jwilder/nginx-proxy:alpine
    container_name: nginx-proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./certs:/etc/nginx/certs
      - ./proxy_data:/usr/share/nginx/html
      - ./vhost.d:/etc/nginx/vhost.d
    environment:
      - DEFAULT_HOST=$DOMAIN

  letsencrypt:
    image: nginxproxy/acme-companion
    container_name: nginx-proxy-acme
    restart: always
    depends_on:
      - nginx-proxy
    environment:
      - DEFAULT_EMAIL=$EMAIL
    volumes_from:
      - nginx-proxy
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/nginx/certs
      - ./acme:/etc/acme.sh

  db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      - MYSQL_ROOT_PASSWORD=$DB_ROOT_PASS
      - MYSQL_DATABASE=$DB_NAME
      - MYSQL_USER=$DB_USER
      - MYSQL_PASSWORD=$DB_PASS
    volumes:
      - ./db_data:/var/lib/mysql

  app:
    image: nextcloud
    container_name: nextcloud-app
    restart: always
    depends_on:
      - db
      - nginx-proxy
      - letsencrypt
    environment:
      - VIRTUAL_HOST=$DOMAIN
      - LETSENCRYPT_HOST=$DOMAIN
      - LETSENCRYPT_EMAIL=$EMAIL
      - MYSQL_PASSWORD=$DB_PASS
      - MYSQL_DATABASE=$DB_NAME
      - MYSQL_USER=$DB_USER
      - MYSQL_HOST=db
      - NEXTCLOUD_TRUSTED_DOMAINS=$DOMAIN
    volumes:
      - ./app_data:/var/www/html
EOF

# --- Start containers ---
docker-compose down || true
docker-compose up -d
systemctl enable docker

# --- Info ---
cat <<INFO >/root/nextcloud_info.txt
Nextcloud is geïnstalleerd en draait achter nginx-proxy.
URL: https://$DOMAIN
DB: $DB_NAME
DB user: $DB_USER
DB password: $DB_PASS
DB root password: $DB_ROOT_PASS
INFO
