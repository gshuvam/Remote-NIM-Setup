#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="nvidia-nim"
SERVICE_NAME="nvidia-nim"
APP_PORT="8082"

clear

echo "====================================================="
echo " Remote-NIM-Setup"
echo " Automated Remote NVIDIA NIM Server Installer"
echo "====================================================="
echo ""

echo "==> Updating system packages..."
sudo apt update

echo "==> Installing required packages..."
sudo apt install -y \
    curl \
    git \
    nano \
    nginx \
    certbot \
    python3-certbot-nginx

echo ""
echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "==> Installing Python 3.14..."
uv python install 3.14

echo ""
echo "==> Cloning repository..."

if [ -d "$PROJECT_DIR" ]; then
    echo "Directory '$PROJECT_DIR' already exists."
    echo "Pulling latest changes..."

    cd "$PROJECT_DIR"
    git pull
    cd ..
else
    git clone https://github.com/gshuvam/free-claude-code.git "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

echo ""
echo "==> Creating .env file..."

if [ ! -f ".env" ]; then
    cp .env.example .env
fi

clear

echo "============================================================"
echo "                ACTION REQUIRED"
echo "============================================================"
echo ""
echo "Update these values inside .env:"
echo ""
echo 'ANTHROPIC_AUTH_TOKEN="YOUR_REAL_TOKEN"'
echo 'NVIDIA_NIM_API_KEY="YOUR_NVIDIA_API_KEY"'
echo ""
echo "SAVE AND EXIT NANO:"
echo ""
echo "  CTRL + O   -> Save"
echo "  ENTER      -> Confirm"
echo "  CTRL + X   -> Exit"
echo ""
echo "============================================================"
echo ""

sleep 3

nano .env

echo ""
echo "==> Validating environment configuration..."

if grep -q 'freecc' .env; then
    echo ""
    echo "============================================================"
    echo " ERROR"
    echo "============================================================"
    echo ""
    echo "Default ANTHROPIC_AUTH_TOKEN still detected."
    echo "Update your real token in .env and rerun script."
    echo ""
    echo "============================================================"
    exit 1
fi

if ! grep -q 'NVIDIA_NIM_API_KEY=' .env; then
    echo ""
    echo "============================================================"
    echo " ERROR"
    echo "============================================================"
    echo ""
    echo "NVIDIA_NIM_API_KEY missing from .env"
    echo ""
    echo "============================================================"
    exit 1
fi

clear

echo "====================================================="
echo " DOMAIN CONFIGURATION"
echo "====================================================="
echo ""
echo "Optional, but recommended."
echo ""
echo "A domain is required ONLY if you want:"
echo ""
echo "  - HTTPS / SSL"
echo "  - Public access via domain"
echo "  - Nginx reverse proxy"
echo ""
echo "Examples:"
echo ""
echo "  example.com"
echo "  api.example.com"
echo "  ai.example.com"
echo ""
echo "Path-based examples (handled externally):"
echo ""
echo "  example.com/api/ai/v1"
echo "  example.com/nim"
echo ""
echo "IMPORTANT:"
echo "This installer only configures DOMAIN or SUBDOMAIN routing."
echo "It does NOT configure URL path routing automatically."
echo ""
echo "Leave empty to skip Nginx + HTTPS setup."
echo ""
echo "====================================================="
echo ""

read -p "Enter domain/subdomain (or press ENTER to skip): " DOMAIN_NAME

if [[ -n "$DOMAIN_NAME" ]]; then
    clear

    echo "============================================================"
    echo " BEFORE CONTINUING"
    echo "============================================================"
    echo ""
    echo "Your domain MUST already point to this VM IP."
    echo ""
    echo "GoDaddy DNS records required:"
    echo ""
    echo "A     @       -> YOUR_EC2_PUBLIC_IP"
    echo "A     www     -> YOUR_EC2_PUBLIC_IP"
    echo ""
    echo "Wait for DNS propagation before continuing."
    echo ""
    echo "Verify using:"
    echo ""
    echo "  ping ${DOMAIN_NAME}"
    echo ""
    echo "============================================================"
    echo ""

    read -p "Press ENTER once DNS is configured..."
fi

echo ""
echo "==> Creating systemd service..."

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Remote NVIDIA NIM Server
After=network.target

[Service]
User=$USER
WorkingDirectory=$(pwd)
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/.local/bin/uv run uvicorn server:app --host 0.0.0.0 --port ${APP_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "==> Reloading systemd..."
sudo systemctl daemon-reload

echo "==> Enabling auto-start on boot..."
sudo systemctl enable ${SERVICE_NAME}

echo "==> Starting application..."
sudo systemctl restart ${SERVICE_NAME}

sleep 5

echo ""
echo "============================================================"
echo " VERIFYING APPLICATION"
echo "============================================================"
echo ""

sudo systemctl --no-pager status ${SERVICE_NAME} || true

if [[ -n "$DOMAIN_NAME" ]]; then

    echo ""
    echo "==> Configuring Nginx reverse proxy..."

    sudo tee /etc/nginx/sites-available/${SERVICE_NAME} > /dev/null <<EOF
server {
    listen 80;

    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    if [ ! -L "/etc/nginx/sites-enabled/${SERVICE_NAME}" ]; then
        sudo ln -s \
            /etc/nginx/sites-available/${SERVICE_NAME} \
            /etc/nginx/sites-enabled/
    fi

    echo ""
    echo "==> Testing Nginx configuration..."
    sudo nginx -t

    echo "==> Reloading Nginx..."
    sudo systemctl reload nginx

    echo ""
    echo "==> Enabling HTTPS with Certbot..."

    sudo certbot --nginx \
        -d ${DOMAIN_NAME} \
        -d www.${DOMAIN_NAME} \
        --redirect \
        --agree-tos \
        --register-unsafely-without-email \
        -n

    echo ""
    echo "============================================================"
    echo " VERIFYING NGINX"
    echo "============================================================"
    echo ""

    sudo systemctl --no-pager status nginx || true

fi

clear

echo "============================================================"
echo " INSTALLATION COMPLETE"
echo "============================================================"
echo ""

if [[ -n "$DOMAIN_NAME" ]]; then
    echo "Public URL:"
    echo ""
    echo "  https://${DOMAIN_NAME}"
else
    echo "Server URL:"
    echo ""
    echo "  http://YOUR_SERVER_IP:${APP_PORT}"
fi

echo ""
echo "============================================================"
echo " IMPORTANT POST-INSTALL STEPS"
echo "============================================================"
echo ""
echo "1. AWS SECURITY GROUP"
echo ""
echo "Open these inbound ports:"
echo ""
echo "  80   (HTTP)"
echo "  443  (HTTPS)"
echo ""

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "  8082 (Temporary direct access)"
    echo ""
fi

echo "Remove public access to:"
echo ""
echo "  8082"
echo ""
echo "after Nginx/HTTPS is working."
echo ""
echo "------------------------------------------------------------"
echo ""
echo "2. VERIFY AUTO-START"
echo ""
echo "Test reboot persistence:"
echo ""
echo "  sudo reboot"
echo ""
echo "Reconnect SSH and verify:"
echo ""
echo "  sudo systemctl status ${SERVICE_NAME}"
echo ""
echo "------------------------------------------------------------"
echo ""
echo "3. VIEW LIVE LOGS"
echo ""
echo "  sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "------------------------------------------------------------"
echo ""
echo "4. RESTART SERVICES"
echo ""
echo "Application:"
echo "  sudo systemctl restart ${SERVICE_NAME}"
echo ""

if [[ -n "$DOMAIN_NAME" ]]; then
    echo "Nginx:"
    echo "  sudo systemctl restart nginx"
    echo ""
fi

echo "============================================================"
echo " DEPLOYMENT COMPLETE"
echo "============================================================"
