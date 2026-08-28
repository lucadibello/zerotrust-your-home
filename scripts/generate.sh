#!/bin/bash
trap "exit" INT

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
    # Ignore unknown options passed from parent orchestrators
    shift
    ;;
  esac
  shift 2>/dev/null || break
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

# Core required variables (always needed)
required_vars=(
  "IP_ADDRESS"
  "IP_GATEWAY"
  "DNS_SERVERS"
  "SUBNET_MASK"
  "TLS_CERTIFICATE_COUNTRY"
  "TLS_CERTIFICATE_STATE"
  "TLS_CERTIFICATE_LOCALITY"
  "TLS_CERTIFICATE_ORGANIZATION"
  "CLOUDFLARE_EMAIL"
  "CLOUDFLARE_API_KEY"
  "RESTIC_REPOSITORY"
  "RESTIC_PASSWORD"
  "TELEGRAM_BOT_TOKEN"
  "TELEGRAM_CHAT_ID"
  "TUNNEL_TOKEN"
  "DNS_DOMAIN"
  "DNS_EMAIL"
)

# Optional Hotspot variables (only if ENABLE_HOTSPOT=true)
required_hotspot_vars=(
  "HOTSPOT_SSID"
  "HOTSPOT_PASSWORD"
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

# SearXNG required variables (only if ENABLE_SEARXNG=true)
required_searxng_vars=(
  "SEARCHXNG_SECRET_KEY"
)

# AWS required variables (only if using S3 restic backend)
required_aws_vars=(
  "AWS_DEFAULT_REGION"
  "AWS_ACCESS_KEY_ID"
  "AWS_SECRET_ACCESS_KEY"
)

# Verify required variables are set
echo "[*] Validating required environment variables..."
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "[!] $var is not set. Please update your .env file."
    exit 1
  fi
done

# Validate AWS variables only if using S3 repository
if [[ "$RESTIC_REPOSITORY" =~ ^s3: ]]; then
  for var in "${required_aws_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set (required for S3 restic repository). Please update your .env file."
      exit 1
    fi
  done
fi

# Validate Hotspot variables if enabled
if [ "${ENABLE_HOTSPOT:-false}" = "true" ]; then
  for var in "${required_hotspot_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set. Please update your .env file for hotspot."
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

# Validate SearXNG variables if enabled
if [ "$ENABLE_SEARXNG" = "true" ]; then
  echo "[*] Validating SearXNG environment variables..."
  for var in "${required_searxng_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "[!] $var is not set. Please update your .env file for SearXNG."
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

# Fix permissions for the generated files (User owned, Container readable)
if [ -n "$SUDO_USER" ]; then
    echo "[*] Fixing permissions for user $SUDO_USER..."
    chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" ./composes
    chmod -R o+rX ./composes
    
    # Restore strict permissions for acme.json (Traefik requirement)
    if [ -f ./composes/letsencrypt/acme.json ]; then
        echo "[*] Restoring strict permissions for acme.json..."
        chmod 600 ./composes/letsencrypt/acme.json
    fi
fi

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
