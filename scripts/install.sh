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
# Install prerequisites
apt update
apt install -y curl git
# Install Node.js (at least v20.15 as required by n8n)
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g npm@latest
# Verify Node.js installation
echo "Node.js version:"
node -v
echo "npm version:"
npm -v
# Install other dependencies
apt install -y nginx certbot python3-certbot-nginx
# Create n8n directory
mkdir -p ~/n8n
cd ~/n8n
# Setup n8n
cp "$REPO_ROOT/package.json" ./
npm install
# Configure Nginx for HTTP first (without SSL)
cat > /etc/nginx/sites-available/n8n << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_intercept_errors on;
        client_max_body_size 500m;
        
        # Longer timeouts for webhooks
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
        proxy_send_timeout 90s;
    }
}
EOF
# Enable site
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
# Test Nginx config
nginx -t
# Reload Nginx
systemctl reload nginx
# Get SSL certificate
echo "Getting SSL certificate for $DOMAIN..."
certbot --nginx -d $DOMAIN
# Configure systemd with webhook URL
cat > /etc/systemd/system/n8n.service << EOF
[Unit]
Description=n8n workflow automation
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/n8n
Environment="WEBHOOK_URL=https://$DOMAIN"
ExecStart=/root/n8n/node_modules/.bin/n8n start
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
# Start n8n
systemctl start n8n
echo "===== Installation Complete ====="
echo "Your n8n instance should be available at: https://$DOMAIN"
echo "Webhook URLs will be configured to use https://$DOMAIN"
echo "Check status with: systemctl status n8n"
