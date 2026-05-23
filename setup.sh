#!/usr/bin/env bash

set -euo pipefail

# ANSI Color Codes
BOLD='\033[1m'
GREEN='\033[0;32m'
BGREEN='\033[1;32m'
BLUE='\033[0;34m'
BBLUE='\033[1;34m'
CYAN='\033[0;36m'
BCYAN='\033[1;36m'
YELLOW='\033[0;33m'
BYELLOW='\033[1;33m'
RED='\033[0;31m'
BRED='\033[1;31m'
MAGENTA='\033[0;35m'
BMAGENTA='\033[1;35m'
RESET='\033[0m'
CLEAR_LINE='\033[2K\r'

# Styled Printing Helpers
print_header() {
    echo -e "\n${BOLD}${BCYAN}======================================================================${RESET}"
    echo -e " ${BOLD}${BMAGENTA}➔ $1${RESET}"
    echo -e "${BOLD}${BCYAN}======================================================================${RESET}\n"
}

print_success() {
    echo -e "${BGREEN}[✓] $1${RESET}"
}

print_warning() {
    echo -e "${BYELLOW}[!] WARNING: $1${RESET}"
}

print_error() {
    echo -e "${BRED}[✗] ERROR: $1${RESET}"
}

print_info() {
    echo -e "${BBLUE}[i] $1${RESET}"
}

print_status() {
    echo -e "${BCYAN}==➔ $1...${RESET}"
}

# Domain Sanitization Function
sanitize_domain() {
    local input="$1"
    # Remove http:// or https://
    local domain="${input#http://}"
    domain="${domain#https://}"
    # Remove any trailing path or slash
    domain="${domain%%/*}"
    # Remove port number if any
    domain="${domain%%:*}"
    # Remove www. prefix if present
    domain="${domain#www.}"
    echo "$domain"
}

# Domain Validation Function
validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

PROJECT_DIR="nvidia-nim"
SERVICE_NAME="nvidia-nim"
APP_PORT="8082"

clear

# Premium Colorful Branding Banner
echo -e "${BOLD}${BCYAN}"
cat << "EOF"
    ____                      __             _   _______ ___  ___
   / __ \___  ____ ___  ____ / /____  ____  / | / /  _/  |/  |/ /
  / /_/ / _ \/ __ `__ \/ __  / __/ _ \/ __ \/  |/ // / / /|_/ /|_/ 
 / _, _/  __/ / / / / / /_/ / /_/  __/ /_/ / /|  // /_/ /  / /  /  
/_/ |_|\___/_/ /_/ /_/\____/\__/\___/\____/_/ |_/___/_/  /_/  /_/   
                                                                   
EOF
echo -e "${RESET}"
echo -e "${BOLD}${BMAGENTA}         AUTOMATED REMOTE NVIDIA NIM SERVER INSTALLER${RESET}"
echo -e "${BOLD}${BCYAN}======================================================================${RESET}\n"

# Detect and verify public IP dynamically
print_status "Detecting VM public IP address"
DETECTED_IP=$(curl -s --max-time 3 https://api.ipify.org || echo "")

if [[ -n "$DETECTED_IP" ]]; then
    print_success "Detected Public IP: ${BOLD}${YELLOW}${DETECTED_IP}${RESET}"
    echo ""
    print_warning "Standard cloud VM public IPs (AWS, Azure, GCP, etc.) are typically DYNAMIC and change on reboot."
    print_info "For reliable DNS configuration, associate a Static IP (e.g. AWS Elastic IP, Azure Static Public IP, or GCP Static IP)."
    echo ""
    echo -e "${BOLD}${BCYAN}➔ Press ENTER to use the detected IP (${YELLOW}${DETECTED_IP}${RESET}${BOLD}),${RESET}"
    echo -e "${BOLD}${BCYAN}  or enter your custom Elastic/Static IP address:${RESET}"
    read -p "➔ " CUSTOM_IP < /dev/tty
    if [[ -n "$CUSTOM_IP" ]]; then
        VM_PUBLIC_IP="$CUSTOM_IP"
        print_success "Using custom IP address: ${BOLD}${YELLOW}${VM_PUBLIC_IP}${RESET}"
    else
        VM_PUBLIC_IP="$DETECTED_IP"
        print_success "Proceeding with detected IP: ${BOLD}${YELLOW}${VM_PUBLIC_IP}${RESET}"
    fi
else
    print_warning "Could not auto-detect public IP."
    echo -e "${BOLD}${BCYAN}➔ Please enter your VM's public/Elastic IP address:${RESET}"
    read -p "➔ " VM_PUBLIC_IP < /dev/tty
    if [[ -z "$VM_PUBLIC_IP" ]]; then
        VM_PUBLIC_IP="YOUR_VM_IP"
    fi
fi
echo ""

print_status "Updating system packages via apt"
sudo apt update

print_status "Installing dependency packages (curl, git, nginx, certbot)"
sudo apt install -y \
    curl \
    git \
    nginx \
    certbot \
    python3-certbot-nginx

echo ""
print_status "Installing uv package manager"
curl -LsSf https://astral.sh/uv/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

echo ""
print_status "Installing Python 3.14 via uv"
uv python install 3.14

echo ""
print_status "Bootstrapping application repository"

if [ -d "$PROJECT_DIR" ]; then
    print_info "Directory '$PROJECT_DIR' already exists. Pulling latest code changes..."
    echo ""
    cd "$PROJECT_DIR"
    git pull
    cd ..
else
    print_info "Cloning Free-Claude-Code application..."
    echo ""
    git clone https://github.com/gshuvam/free-claude-code.git "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

print_header "ENVIRONMENT CONFIGURATION"
print_info "You must provide two secure API keys to integrate and run the inference server."
echo ""

while true; do
    echo -e "${BOLD}${BCYAN}➔ Enter ANTHROPIC_AUTH_TOKEN:${RESET}"
    read -p "➔ " ANTHROPIC_TOKEN < /dev/tty
    if [[ -n "$ANTHROPIC_TOKEN" ]]; then
        break
    else
        print_error "ANTHROPIC_AUTH_TOKEN cannot be empty. Please enter a valid token."
        echo ""
    fi
done

while true; do
    echo -e "\n${BOLD}${BCYAN}➔ Enter NVIDIA_NIM_API_KEY:${RESET}"
    read -p "➔ " NVIDIA_NIM_API_KEY < /dev/tty
    if [[ -n "$NVIDIA_NIM_API_KEY" ]]; then
        break
    else
        print_error "NVIDIA_NIM_API_KEY cannot be empty. Please enter a valid API key."
    fi
done

cat > .env <<EOF
ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_TOKEN}"
NVIDIA_NIM_API_KEY="${NVIDIA_NIM_API_KEY}"
EOF

echo ""
print_success "Environment configuration saved to ${BOLD}.env${RESET}"
echo ""

clear

print_header "DOMAIN CONFIGURATION"
print_info "A domain or subdomain is required ONLY if you want to configure:"
echo -e "  - ${BOLD}HTTPS / SSL Secure Access${RESET}"
echo -e "  - ${BOLD}Public access${RESET} on ports 80/443"
echo -e "  - ${BOLD}Nginx reverse proxy${RESET} routing\n"

print_warning "This installer configures DOMAIN or SUBDOMAIN routing (e.g. api.domain.com)."
print_info "It does NOT configure URL path routing (e.g. domain.com/v1/nim) automatically."
print_info "Leave empty and press ENTER to skip Nginx + HTTPS setup entirely.\n"

DOMAIN_NAME=""
while true; do
    echo -e "${BOLD}${BCYAN}➔ Enter domain/subdomain${RESET} (or press ENTER to skip):"
    read -p "➔ " RAW_DOMAIN < /dev/tty
    if [[ -z "$RAW_DOMAIN" ]]; then
        print_warning "Skipping Nginx + SSL setup. Direct access on port ${APP_PORT} will be used."
        DOMAIN_NAME=""
        sleep 2
        break
    fi
    
    # Sanitize and extract clean domain
    DOMAIN_NAME=$(sanitize_domain "$RAW_DOMAIN")
    
    if validate_domain "$DOMAIN_NAME"; then
        if [[ "$RAW_DOMAIN" != "$DOMAIN_NAME" ]]; then
            echo ""
            print_success "Extracted clean domain: ${BOLD}${BYELLOW}${DOMAIN_NAME}${RESET}"
        fi
        sleep 1.5
        break
    else
        echo ""
        print_error "Invalid domain format: '${RAW_DOMAIN}'."
        print_info "Please enter a valid domain name (e.g. ${BOLD}api.byshuvam.co.in${RESET} or ${BOLD}domain.com${RESET})."
        echo ""
    fi
done

if [[ -n "$DOMAIN_NAME" ]]; then
    clear
    print_header "DNS & FIREWALL PRE-REQUISITES"
    print_warning "Port 80 (HTTP) and Port 443 (HTTPS) MUST be open in your cloud firewall/security group!"
    print_info "Let's Encrypt (Certbot) requires Port 80 to be open to perform domain verification."
    echo ""
    echo -e "  ${BOLD}1. Cloud Firewall & Security Group Setup (AWS, Azure, GCP, etc.):${RESET}"
    echo -e "     Ensure these Inbound Rules are active in your cloud provider's firewall console:"
    echo -e "       ${BOLD}${CYAN}• HTTP  (Port 80)${RESET}  ➔ source: ${BOLD}0.0.0.0/0${RESET}"
    echo -e "       ${BOLD}${CYAN}• HTTPS (Port 443)${RESET} ➔ source: ${BOLD}0.0.0.0/0${RESET}"
    echo ""
    echo -e "  ${BOLD}2. DNS Record Setup (GoDaddy, Cloudflare, etc.):${RESET}"
    echo -e "     Ensure your domain points to this VM's IP (${BOLD}${VM_PUBLIC_IP}${RESET}):"
    echo -e "       ${BOLD}${CYAN}A     ${DOMAIN_NAME}${RESET} ➔ ${BOLD}${GREEN}${VM_PUBLIC_IP}${RESET}"
    echo ""
    print_info "Verify propagation from another terminal using: ${BOLD}ping ${DOMAIN_NAME}${RESET}"
    echo ""
    print_warning "If firewall ports are closed or DNS is not pointed, SSL generation WILL fail."
    echo ""
    
    echo -e "${BOLD}${BCYAN}➔ Press ENTER once DNS and Firewall (Port 80/443) are configured to continue...${RESET}"
    read -p "" < /dev/tty
fi

echo ""
print_status "Creating systemd service configuration"

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

print_status "Reloading systemd daemon"
sudo systemctl daemon-reload

print_status "Enabling auto-start on boot"
sudo systemctl enable ${SERVICE_NAME}

print_status "Starting application service"
sudo systemctl restart ${SERVICE_NAME}

# Wait for service initialization
print_status "Waiting for service to stabilize"
for i in {1..5}; do
    echo -ne "  [${i}/5] Waiting...\r"
    sleep 1
done
echo -ne "${CLEAR_LINE}"

print_header "VERIFYING APPLICATION SERVICE"

if sudo systemctl is-active --quiet ${SERVICE_NAME}; then
    print_success "Application service '${BOLD}${SERVICE_NAME}${RESET}' is successfully running!"
    echo ""
    sudo systemctl --no-pager status ${SERVICE_NAME} | grep -E "Active:|Main PID:" || true
else
    print_error "Application service failed to start! Printing diagnostics:"
    echo ""
    sudo systemctl --no-pager status ${SERVICE_NAME} || true
    print_warning "Review logs using: journalctl -u ${SERVICE_NAME} -n 50"
fi

if [[ -n "$DOMAIN_NAME" ]]; then

    echo ""
    print_status "Configuring Nginx reverse proxy for ${BOLD}${DOMAIN_NAME}${RESET}"

    sudo tee /etc/nginx/sites-available/${SERVICE_NAME} > /dev/null <<EOF
server {
    listen 80;

    server_name ${DOMAIN_NAME};

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

    print_status "Testing Nginx configuration"
    if sudo nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration check passed!"
    else
        print_error "Nginx configuration check failed! Showing diagnostics:"
        sudo nginx -t || true
        exit 1
    fi

    print_status "Reloading Nginx reverse proxy"
    sudo systemctl reload nginx

    echo ""
    print_status "Acquiring SSL certificate and enabling HTTPS with Certbot"

    sudo certbot --nginx \
        -d ${DOMAIN_NAME} \
        --redirect \
        --agree-tos \
        --register-unsafely-without-email \
        -n

    print_header "VERIFYING NGINX WEB SERVER"

    if sudo systemctl is-active --quiet nginx; then
        print_success "Nginx reverse proxy is active and routing traffic securely!"
        echo ""
        sudo systemctl --no-pager status nginx | grep -E "Active:" || true
    else
        print_error "Nginx service is inactive! Showing status:"
        echo ""
        sudo systemctl --no-pager status nginx || true
    fi

fi

clear
echo -e "${BOLD}${BGREEN}"
cat << "EOF"
======================================================================
  ██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗███╗   ███╗███████╗███╗   ██╗████████╗
  ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
  ██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝ ██╔████╔██║█████╗  ██╔██╗ ██║   ██║   
  ██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║   
  ██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║   ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║   
  ╚══════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝   
======================================================================
EOF
echo -e "${RESET}"

print_header "DEPLOYMENT COMPLETE & PERSISTENT"

if [[ -n "$DOMAIN_NAME" ]]; then
    echo -e "  ${BOLD}Public Secured Endpoint:${RESET}"
    echo -e "    ${BOLD}${BGREEN}➔ https://${DOMAIN_NAME}${RESET}\n"
else
    echo -e "  ${BOLD}Local API Server Endpoint:${RESET}"
    echo -e "    ${BOLD}${BYELLOW}➔ http://YOUR_SERVER_IP:${APP_PORT}${RESET}\n"
fi

echo -e "${BOLD}${BBLUE}----------------------------------------------------------------------${RESET}"
echo -e " ${BOLD}${BBLUE}★  IMPORTANT POST-INSTALL STEPS  ★${RESET}"
echo -e "${BOLD}${BBLUE}----------------------------------------------------------------------${RESET}"

echo -e "\n ${BOLD}${BYELLOW}1. CLOUD FIREWALL & SECURITY GROUP CONFIGURATION (AWS, Azure, GCP, etc.)${RESET}"
echo -e "    Ensure these inbound ports are open to the internet:"
echo -e "      ${BOLD}${CYAN}• Port 80${RESET}   (HTTP for Certbot / SSL redirects)"
echo -e "      ${BOLD}${CYAN}• Port 443${RESET}  (HTTPS for secure public traffic)"
if [[ -z "$DOMAIN_NAME" ]]; then
    echo -e "      ${BOLD}${CYAN}• Port 8082${RESET} (Temporary direct API endpoint)"
fi
echo ""
echo -e "    ${BOLD}${BRED}⚠ SECURITY NOTE:${RESET} Remember to disable external access to port ${BOLD}${APP_PORT}${RESET}"
echo -e "    once your Nginx reverse proxy and HTTPS domain is working."

echo -e "\n ${BOLD}${BYELLOW}2. TEST AUTO-START & REBOOT PERSISTENCE${RESET}"
echo -e "    Run this command to test systemd restart on crash:"
echo -e "      ${BOLD}${CYAN}sudo systemctl restart ${SERVICE_NAME}${RESET}"
echo -e "    Then verify persistence on a full machine restart:"
echo -e "      ${BOLD}${CYAN}sudo reboot${RESET}"
echo -e "    Reconnect your SSH session and verify:"
echo -e "      ${BOLD}${CYAN}sudo systemctl status ${SERVICE_NAME}${RESET}"

echo -e "\n ${BOLD}${BYELLOW}3. VIEW RUNTIME LIVE LOGS${RESET}"
echo -e "    Stream active application logs live using systemd journal:"
echo -e "      ${BOLD}${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${RESET}"

echo -e "\n ${BOLD}${BYELLOW}4. RESTARTING SERVICES${RESET}"
echo -e "    Application Server:"
echo -e "      ${BOLD}${CYAN}sudo systemctl restart ${SERVICE_NAME}${RESET}"
if [[ -n "$DOMAIN_NAME" ]]; then
    echo -e "    Nginx Web Server:"
    echo -e "      ${BOLD}${CYAN}sudo systemctl restart nginx${RESET}"
fi

echo -e "\n${BOLD}${BCYAN}======================================================================${RESET}"
print_success "Server successfully deployed using Python 3.14 + uv + systemd + Nginx!"
echo -e "${BOLD}${BCYAN}======================================================================${RESET}\n"
