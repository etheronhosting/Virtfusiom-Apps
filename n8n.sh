#cloud-config
runcmd:
  # Wacht tot apt/dpkg vrij is
  - 'while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo "⏳ apt is nog bezig, wachten..."; sleep 10; done'

  # Update & installaties
  - 'apt update -y && apt upgrade -y'
  - 'apt install -y docker.io docker-compose curl jq openssl'

  # n8n user + random wachtwoord
  - 'USERNAME=n8nuser'
  - 'PASSWORD=$(openssl rand -base64 16)'
  - 'useradd -m -s /bin/bash "$USERNAME"'
  - 'echo "$USERNAME:$PASSWORD" | chpasswd'

  # Docker map + docker-compose file
  - 'mkdir -p /opt/n8n/.n8n'
  - 'echo "version: \"3\"" > /opt/n8n/docker-compose.yml'
  - 'echo "services:" >> /opt/n8n/docker-compose.yml'
  - 'echo "  n8n:" >> /opt/n8n/docker-compose.yml'
  - 'echo "    image: n8nio/n8n" >> /opt/n8n/docker-compose.yml'
  - 'echo "    restart: always" >> /opt/n8n/docker-compose.yml'
  - 'echo "    ports:" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - \"5678:5678\"" >> /opt/n8n/docker-compose.yml'
  - 'echo "    environment:" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - GENERIC_TIMEZONE=Europe/Amsterdam" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - N8N_BASIC_AUTH_ACTIVE=true" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - N8N_BASIC_AUTH_USER=${USERNAME}" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - N8N_BASIC_AUTH_PASSWORD=${PASSWORD}" >> /opt/n8n/docker-compose.yml'
  - 'IP=$(hostname -I | awk "{print \$1}")'
  - 'echo "      - WEBHOOK_URL=http://$IP:5678/" >> /opt/n8n/docker-compose.yml'
  - 'echo "    volumes:" >> /opt/n8n/docker-compose.yml'
  - 'echo "      - /opt/n8n/.n8n:/home/node/.n8n" >> /opt/n8n/docker-compose.yml'

  # Start container
  - 'cd /opt/n8n && docker-compose up -d'

  # Sla credentials op
  - 'IP=$(hostname -I | awk "{print \$1}")'
  - 'echo "========================================" > /root/n8n_credentials.txt'
  - 'echo "✅ n8n is geïnstalleerd!" >> /root/n8n_credentials.txt'
  - 'echo "URL: http://$IP:5678" >> /root/n8n_credentials.txt'
  - 'echo "Gebruikersnaam: $USERNAME" >> /root/n8n_credentials.txt'
  - 'echo "Wachtwoord: $PASSWORD" >> /root/n8n_credentials.txt'
  - 'echo "========================================" >> /root/n8n_credentials.txt'

  # Zorg dat docker mee opstart
  - 'systemctl enable docker'
