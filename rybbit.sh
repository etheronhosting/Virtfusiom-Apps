#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/rybbit-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "==> Wachten tot apt vrij is..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  sleep 8
done

echo "==> Pakketten bijwerken en basis-tools installeren..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y curl ca-certificates gnupg lsb-release git jq dnsutils

# --- Docker Engine + Compose plugin (officiële methode) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "==> Docker repository toevoegen..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt update -y
  echo "==> Docker Engine & Compose plugin installeren..."
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# helper alias voor compose v2
dc() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Docker Compose is niet geïnstalleerd." >&2
    exit 1
  fi
}

# --- optionele firewall openzetten (indien ufw aanwezig) ---
if command -v ufw >/dev/null 2>&1; then
  echo "==> UFW: poorten 80/443 openzetten..."
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi

# --- Domein bepalen ---
DOMAIN="${1:-}"
if [[ -z "${DOMAIN}" ]]; then
  DOMAIN="$(hostname -f || true)"
fi
if [[ -z "${DOMAIN}" ]]; then
  echo "Kon geen domein bepalen. Geef een domein mee:  ./rybbit.sh tracking.jouwdomein.nl"
  exit 1
fi

# Optioneel: Mapbox token via env var MAPBOX_TOKEN meegeven
MAPBOX_TOKEN="${MAPBOX_TOKEN:-}"

echo "==> DNS check voor ${DOMAIN}..."
IP_LOCAL="$(hostname -I | awk '{print $1}')"
IP_DNS="$(dig +short "${DOMAIN}" | tail -n1 || true)"
echo "  - Server IP  : ${IP_LOCAL}"
echo "  - DNS A-record: ${IP_DNS:-<geen>}"
if [[ -n "${IP_DNS}" && "${IP_DNS}" != "${IP_LOCAL}" ]]; then
  echo "⚠️  Waarschuwing: DNS wijst nog niet naar deze server. Caddy kan SSL pas uitgeven zodra DNS klopt."
fi

# --- Rybbit repo clonen en setup draaien ---
echo "==> Rybbit repository clonen..."
mkdir -p /opt
cd /opt
if [[ -d /opt/rybbit ]]; then
  echo "Repo bestaat al, overslaan van clone. Updaten..."
  cd /opt/rybbit
  git reset --hard HEAD
  git pull --ff-only
else
  git clone https://github.com/rybbit-io/rybbit.git
  cd rybbit
fi

echo "==> Scripts uitvoerbaar maken..."
chmod +x *.sh || true

echo "==> Rybbit setup uitvoeren voor domein: ${DOMAIN}"
if [[ -n "${MAPBOX_TOKEN}" ]]; then
  ./setup.sh "${DOMAIN}" --mapbox-token "${MAPBOX_TOKEN}"
else
  ./setup.sh "${DOMAIN}"
fi

echo "==> Services opstarten (met webserver-profiel)..."
# volgens docs: met webserver-profiel gebruiken
dc --profile with-webserver up -d

echo "✅ Klaar! Rybbit zou bereikbaar moeten zijn op: https://${DOMAIN}"
echo "   Admin aanmaken: https://${DOMAIN}/signup"
echo "   Logs volgen:     docker compose logs -f    (of docker-compose logs -f)"
