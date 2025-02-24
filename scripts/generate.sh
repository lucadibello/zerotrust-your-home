#!/bin/bash

# generate.sh: Regenerate configuration files and execute configuration scripts.
#
# Usage: ./generate.sh [options]
# Options:
#   -y, --yes, --headless    Run in headless mode (auto-confirm prompts)
#   --skip-firewall          Skip firewall configuration
#   -h, --help               Display this help message

# Default options
HEADLESS_MODE=${HEADLESS_MODE:-false}
SKIP_FIREWALL=false

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -y, --yes, --headless    Run in headless mode"
  echo "  -h, --help               Display this help message"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -y | --yes | --headless)
    HEADLESS_MODE=true
    ;;
  --skip-firewall)
    SKIP_FIREWALL=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# Check if .env file exists
if [ ! -f .env ]; then
  echo "[!] .env file not found. Please create one by copying .env.example and filling in the required variables."
  exit 1
fi

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root"
  exit 1
fi

export HEADLESS_MODE

# Source common functions
source ./scripts/common.sh

# Load environment variables
set -a
source .env
set +a

# Define required environment variables for configuration
required_hotspot_vars=(
  "HOTSPOT_SSID"
  "HOTSPOT_PASSWORD"
)
required_vars=(
  "IP_ADDRESS"
  "IP_GATEWAY"
  "DNS_SERVERS"
  "SUBNET_MASK"
  "ENABLE_HOTSPOT"
  "ALLOW_LOCAL_SSH_ACCESS"
  "ALLOW_LOCAL_SERVICES_ACCESS"
  "TLS_CERTIFICATE_COUNTRY"
  "TLS_CERTIFICATE_STATE"
  "TLS_CERTIFICATE_LOCALITY"
  "TLS_CERTIFICATE_ORGANIZATION"
  "CLOUDFLARE_EMAIL"
  "CLOUDFLARE_API_KEY"
  "RESTIC_REPOSITORY"
  "AWS_DEFAULT_REGION"
  "AWS_ACCESS_KEY_ID"
  "AWS_SECRET_ACCESS_KEY"
  "TELEGRAM_BOT_TOKEN"
  "TELEGRAM_CHAT_ID"
  "TUNNEL_TOKEN"
  "DNS_DOMAIN"
  "DNS_EMAIL"
)

# Verify required variables are set
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "[!] $var is not set. Please update your .env file."
    exit 1
  fi
done

if [ "$ENABLE_HOTSPOT" = true ]; then
  for var in "${required_hotspot_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set. Please update your .env file."
      exit 1
    fi
  done
fi

# Create a temporary directory (if needed)
mkdir -p ./.tmp || true

# === Docker Containers Configuration ===
echo "[*] Executing Docker containers configuration scripts..."
containers_scripts=$(find ./scripts/containers -type f \( -name "setup-*.sh" -o -name "post-setup-*.sh" \) | sort -r)
for script in $containers_scripts; do
  short_name=$(basename "$script" | cut -d- -f2 | cut -d. -f1)
  echo "[*] Configuring ${short_name}..."
  sudo bash "$script"
  if [ $? -ne 0 ]; then
    echo "[!] Error occurred while configuring ${short_name}. Aborting..."
    exit 1
  fi
  echo "[OK] ${short_name} configured successfully"
done

# Clean up temporary directory
rm -rf ./.tmp

echo "----------------------------------------------"
echo "---- Successfully generated configurations ----"
echo "----------------------------------------------"
