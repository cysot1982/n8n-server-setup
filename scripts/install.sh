#!/bin/bash
set -e

echo "===== Installing n8n Server ====="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Get domain from arguments or prompt
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
  read -p "Enter your domain for n8n (e.g., n8n.example.com): " DOMAIN
fi

# Determine script and repository paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( dirname "$SCRIPT_DIR" )"

# Create n8n directory
mkdir -p ~/n8n
cd ~/n8n

# Install dependencies
apt update
apt install -y nginx certbot python3-certbot-nginx

# Setup n8n
cp "$REPO_ROOT/package.json" ./
npm install

# Configure nginx
sed "s/n8n.lowcodeai.tech/$DOMAIN/g" "$REPO_ROOT/nginx/n8n.conf" > /etc/nginx/sites-available/n8n
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Configure systemd
cp "$REPO_ROOT/systemd/n8n.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable n8n

# Test nginx config
nginx -t

# Reload nginx
systemctl reload nginx

# Get SSL certificate
certbot --nginx -d $DOMAIN

# Start n8n
systemctl start n8n

echo "===== Installation Complete ====="
echo "Your n8n instance should be available at: https://$DOMAIN"
echo "Check status with: systemctl status n8n"
