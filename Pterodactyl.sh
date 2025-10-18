#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/pterodactyl-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Systeemupdate ---
apt update -y && apt upgrade -y
apt install -y curl sudo git zip unzip tar ufw

# --- Variabelen ---
DOMAIN=$(hostname -f)
EMAIL="admin@$DOMAIN"
INSTALL_DIR="/opt/pterodactyl"
IP=$(hostname -I | awk '{print $1}')

# --- Firewall (voor Wings en Panel) ---
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8080:8081/tcp
ufw --force enable

# --- Installer ophalen ---
cd /root
if [ ! -d "$INSTALL_DIR" ]; then
  mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# --- Installer downloaden ---
curl -Lo installer.sh https://github.com/pterodactyl-installer/pterodactyl-installer/releases/latest/download/installer.sh
chmod +x installer.sh

# --- Panel installeren ---
bash installer.sh --panel --release latest --email "$EMAIL" --fqdn "$DOMAIN" --timezone "Europe/Amsterdam" --mysql-host 127.0.0.1 --mysql-password "auto" --ssl

# --- Wings installeren ---
bash installer.sh --wings --release latest --auto

# --- Systemd herladen en starten ---
systemctl daemon-reload
systemctl enable pteroq.service
systemctl enable wings.service
systemctl restart pteroq.service
systemctl restart wings.service

# --- Info opslaan ---
cat <<EOF >/root/pterodactyl_info.txt
✅ Pterodactyl is succesvol geïnstalleerd!

🌐 Panel: https://$DOMAIN
📂 Installatiedirectory: $INSTALL_DIR
📧 Email: $EMAIL
🐦 Wings API draait op: $IP:8080

Logbestand: $LOGFILE
EOF
