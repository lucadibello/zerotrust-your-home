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

# Core required variables (always needed)
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

# Immich required variables (only if ENABLE_IMMICH=true)
required_immich_vars=(
  "IMMICH_UPLOAD_LOCATION"
  "IMMICH_DB_DATA_LOCATION"
  "IMMICH_VERSION"
  "IMMICH_DB_PASSWORD"
  "IMMICH_DB_USERNAME"
  "IMMICH_DB_DATABASE_NAME"
)

# Minecraft required variables (only if ENABLE_MINECRAFT=true)
required_minecraft_vars=(
  "MC_TUNNEL_TOKEN"
)

# Verify required variables are set
echo "[*] Validating required environment variables..."
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

# Validate Immich variables if enabled
if [ "$ENABLE_IMMICH" = "true" ]; then
  echo "[*] Validating Immich environment variables..."
  for var in "${required_immich_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set. Please update your .env file for Immich."
      exit 1
    fi
  done
fi

# Validate Minecraft variables if enabled
if [ "$ENABLE_MINECRAFT" = "true" ]; then
  echo "[*] Validating Minecraft environment variables..."
  for var in "${required_minecraft_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set. Please update your .env file for Minecraft."
      exit 1
    fi
  done
fi

# Create a temporary directory (if needed)
mkdir -p ./.tmp || true

# === Print enabled services ===
echo ""
echo "[*] Enabled services:"
[ "$ENABLE_MONITORING" = "true" ] && echo "    - Monitoring (Prometheus, Grafana, Alertmanager)"
[ "$ENABLE_LOGGING" = "true" ] && echo "    - Logging (Loki, Promtail)"
[ "$ENABLE_BACKUP" = "true" ] && echo "    - Backup (Restic)"
[ "$ENABLE_DNS" = "true" ] && echo "    - DNS (BIND9)"
[ "$ENABLE_REVERSE_PROXY" = "true" ] && echo "    - Reverse Proxy (Traefik)"
[ "$ENABLE_HOME_AUTOMATION" = "true" ] && echo "    - Home Automation (Home Assistant, Zigbee2MQTT, Mosquitto)"
[ "$ENABLE_VAULTWARDEN" = "true" ] && echo "    - Vaultwarden (Password Manager)"
[ "$ENABLE_NEXTCLOUD" = "true" ] && echo "    - Nextcloud (Cloud Storage)"
[ "$ENABLE_PORTAINER" = "true" ] && echo "    - Portainer (Docker UI)"
[ "$ENABLE_UPTIME_KUMA" = "true" ] && echo "    - Uptime Kuma (Health Monitoring)"
[ "$ENABLE_WATCHTOWER" = "true" ] && echo "    - Watchtower (Auto Updates)"
[ "$ENABLE_IMMICH" = "true" ] && echo "    - Immich (Photo Library)"
[ "$ENABLE_SEARXNG" = "true" ] && echo "    - SearXNG (Search Engine)"
[ "$ENABLE_MINECRAFT" = "true" ] && echo "    - Minecraft Server"
echo ""

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
done

# Clean up temporary directory
rm -rf ./.tmp

echo ""
echo "----------------------------------------------"
echo "---- Successfully generated configurations ----"
echo "----------------------------------------------"
echo ""
echo "Next steps:"
echo "  1. Review your .env file and adjust feature toggles as needed"
echo "  2. Run 'make start' to start all enabled services"
echo "  3. Use 'make start-<service>' to start individual services"
echo "     Example: make start-immich, make start-searxng"
echo ""
