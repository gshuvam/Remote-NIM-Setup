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

SERVICE_NAME="nvidia-nim"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

clear || true

# Premium Colorful Branding Banner for Updates
echo -e "${BOLD}${BCYAN}"
cat << "EOF"
    ____                      __             _   _______ ___  ___
   / __ \___  ____ ___  ____ / /____  ____  / | / /  _/  |/  |/ /
  / /_/ / _ \/ __ `__ \/ __  / __/ _ \/ __ \/  |/ // / / /|_/ /|_/ 
 / _, _/  __/ / / / / / /_/ / /_/  __/ /_/ / /|  // /_/ /  / /  /  
/_/ |_|\___/_/ /_/ /_/\____/\__/\___/\____/_/ |_/___/_/  /_/  /_/   
                                                                   
EOF
echo -e "${RESET}"
echo -e "${BOLD}${BMAGENTA}         AUTOMATED REMOTE NVIDIA NIM SERVER UPDATER${RESET}"
echo -e "${BOLD}${BCYAN}======================================================================${RESET}\n"

# 1. Verify if the app service is running, and stop it
print_header "VERIFYING SERVICE STATE"

if ! systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1 && [ ! -f "$SERVICE_FILE" ]; then
    print_error "Service '${SERVICE_NAME}' is not registered/installed on this VM."
    print_info "Please run the setup script first: curl -sL https://raw.githubusercontent.com/gshuvam/Remote-NIM-Setup/main/setup.sh | bash"
    exit 1
fi

WAS_RUNNING=false
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    WAS_RUNNING=true
    print_info "Application service '${SERVICE_NAME}' is currently RUNNING."
    print_status "Stopping service to perform updates"
    sudo systemctl stop "$SERVICE_NAME"
    print_success "Service stopped successfully."
else
    print_info "Application service '${SERVICE_NAME}' is currently NOT running."
fi

# 2. Identify the app project directory
print_status "Locating application directory"
PROJECT_DIR=""

if [ -f "$SERVICE_FILE" ]; then
    # Parse WorkingDirectory from the systemd unit file
    PROJECT_DIR=$(grep -E "^WorkingDirectory=" "$SERVICE_FILE" | cut -d= -f2- | xargs)
fi

if [ -z "${PROJECT_DIR:-}" ] || [ ! -d "$PROJECT_DIR" ]; then
    # Fallback paths
    if [ -d "nvidia-nim" ]; then
        PROJECT_DIR="$(pwd)/nvidia-nim"
    elif [ -d "$HOME/nvidia-nim" ]; then
        PROJECT_DIR="$HOME/nvidia-nim"
    else
        print_error "Could not locate the application directory."
        print_info "Parsed WorkingDirectory from service file: '${PROJECT_DIR:-None}'"
        exit 1
    fi
fi

print_success "Application directory located at: ${BOLD}${YELLOW}${PROJECT_DIR}${RESET}"

# 3. Compare files and update files
print_header "COMPARING AND UPDATING FILES"
cd "$PROJECT_DIR"

if [ ! -d ".git" ]; then
    print_error "The directory '${PROJECT_DIR}' is not a valid git repository."
    exit 1
fi

print_status "Fetching latest updates from origin"
git fetch origin

# Find current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
print_info "Active branch: ${BOLD}${CYAN}${BRANCH}${RESET}"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/${BRANCH}")

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
    print_success "No file updates available. The application is already at the latest version."
else
    print_info "New updates detected on the remote repository!"
    echo ""
    echo -e "${BOLD}${CYAN}--- CHANGELOG (Modified Files) ---${RESET}"
    git diff --name-status "HEAD...origin/${BRANCH}"
    echo -e "${BOLD}${CYAN}----------------------------------${RESET}"
    echo ""

    # Check if there are local uncommitted changes that might conflict
    if ! git diff --quiet; then
        print_warning "Local uncommitted changes detected in the application repository."
        print_info "Stashing local modifications to guarantee a clean merge..."
        git stash
    fi

    print_status "Updating files via git pull"
    git pull origin "${BRANCH}"
    print_success "Files successfully updated."
fi

# 4. Start the app via daemon
print_header "RESTARTING APPLICATION DAEMON"

print_status "Reloading systemd daemon"
sudo systemctl daemon-reload

print_status "Starting application service (${SERVICE_NAME})"
sudo systemctl start "$SERVICE_NAME"

# Wait for service stabilization
print_status "Waiting for service to stabilize"
for i in {1..3}; do
    echo -ne "  [${i}/3] Stabilizing...\r"
    sleep 1
done
echo -ne "${CLEAR_LINE}"

# 5. Check if service is enabled (auto on) and active
print_header "VERIFYING AUTO-START & RUNNING STATUS"

print_status "Checking if service is enabled (auto on)"
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    print_success "Service '${SERVICE_NAME}' is configured to auto-start on boot."
else
    print_warning "Service '${SERVICE_NAME}' is NOT configured to auto-start on boot."
    print_status "Enabling service auto-start"
    sudo systemctl enable "$SERVICE_NAME"
    print_success "Service '${SERVICE_NAME}' is now configured to auto-start on boot."
fi

echo ""
print_status "Checking active running state"
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    print_success "Application service '${BOLD}${SERVICE_NAME}${RESET}' is successfully running!"
    echo ""
    sudo systemctl --no-pager status "$SERVICE_NAME" | grep -E "Active:|Main PID:" || true
    echo ""
    print_success "Update completed successfully! Exiting."
    exit 0
else
    print_error "Application service failed to start after update!"
    echo ""
    sudo systemctl --no-pager status "$SERVICE_NAME" || true
    print_warning "Review runtime logs using: journalctl -u ${SERVICE_NAME} -n 50"
    exit 1
fi
