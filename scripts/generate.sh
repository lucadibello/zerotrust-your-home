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

export HEADLESS_MODE

# Source common functions
source ./scripts/common.sh

# Load environment variables
load_env .env

# Core required variables (always needed)
required_vars=(
  "IP_ADDRESS"
  "IP_GATEWAY"
  "PRIMARY_DNS"
  "SECONDARY_DNS"
  "SUBNET_MASK"
  "TLS_CERTIFICATE_COUNTRY"
  "TLS_CERTIFICATE_STATE"
  "TLS_CERTIFICATE_LOCALITY"
  "TLS_CERTIFICATE_ORGANIZATION"
  "CLOUDFLARE_EMAIL"
  "CLOUDFLARE_API_KEY"
  "RESTIC_REPOSITORY"
  "RESTIC_PASSWORD"
  "NTFY_TOPIC"
  "DNS_DOMAIN"
  "DNS_EMAIL"
)

export NTFY_URL="${NTFY_URL:-https://ntfy.home.lucadibello.ch}"
export PRIMARY_DNS="${PRIMARY_DNS:-192.168.0.253}"
export SECONDARY_DNS="${SECONDARY_DNS:-1.1.1.1}"

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

# Validate Cloudflare Tunnel if enabled
if [ "${ENABLE_TUNNEL:-true}" = "true" ]; then
  if [ -z "${TUNNEL_TOKEN:-}" ]; then
    echo "[!] TUNNEL_TOKEN is not set (required when ENABLE_TUNNEL=true). Please update your .env file."
    exit 1
  fi
fi

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

# Validate CrowdSec configuration if enabled
if [ "${ENABLE_CROWDSEC:-false}" = "true" ]; then
  echo "[*] Validating CrowdSec configuration..."
fi


# Create a temporary directory (if needed)
mkdir -p ./.tmp || true

# === Print enabled services ===
echo ""
echo "[*] Enabled services:"
for service_dir in composes/*/; do
  if [ -d "$service_dir" ]; then
    service_name=$(basename "$service_dir")
    if [ "$service_name" != "extras" ] && [ "$service_name" != "gatus" ]; then
      if is_service_enabled "$service_name" false; then
        echo "    - ${service_name}"
      fi
    fi
  fi
done

# Print discovered extra services
if [ -d "composes/extras" ]; then
  extras_found=false
  for extra_dir in composes/extras/*/; do
    if [ -d "$extra_dir" ]; then
      if [ -f "${extra_dir}docker-compose.yml" ] || [ -f "${extra_dir}docker-compose.yaml" ]; then
        service_name=$(basename "$extra_dir")
        if is_service_enabled "$service_name" true; then
          if [ "$extras_found" = false ]; then
            echo ""
            echo "[*] Extra services (from composes/extras/):"
            extras_found=true
          fi
          echo "    - ${service_name}"
        fi
      fi
    fi
  done
fi
echo ""

# === Docker Containers Configuration ===
echo "[*] Executing Docker containers configuration scripts..."

# Ordered execution list for deterministic service setup
ordered_scripts=(
  "./scripts/containers/setup-traefik.sh"
  "./scripts/containers/setup-letsencrypt.sh"
  "./scripts/containers/setup-tunnel.sh"
  "./scripts/containers/setup-adguard.sh"
  "./scripts/containers/post-setup-bind9.sh"
  "./scripts/containers/setup-ntfy.sh"
  "./scripts/containers/setup-prometheus.sh"
  "./scripts/containers/setup-alertmanager.sh"
  "./scripts/containers/setup-loki.sh"
  "./scripts/containers/setup-home-assistant.sh"
  "./scripts/containers/setup-immich.sh"
  "./scripts/containers/setup-nextcloud.sh"
  "./scripts/containers/setup-searxng.sh"
  "./scripts/containers/setup-vaultwarden.sh"
  "./scripts/containers/setup-crowdsec.sh"
  "./scripts/containers/setup-gatus.sh"
  "./scripts/containers/setup-homepage.sh"
  "./scripts/containers/setup-diun.sh"
  "./scripts/containers/setup-minecraft.sh"
  "./scripts/containers/setup-backup.sh"
)

# Run ordered scripts
for script in "${ordered_scripts[@]}"; do
  if [ -f "$script" ]; then
    short_name=$(basename "$script" | sed -E 's/^(setup-|post-setup-)//' | cut -d. -f1)
    echo "[*] Configuring ${short_name}..."
    bash "$script"
    if [ $? -ne 0 ]; then
      echo "[!] Error occurred while configuring ${short_name}. Aborting..."
      exit 1
    fi
  fi
done

# Run any additional custom setup scripts not in the ordered list
for extra_script in ./scripts/containers/setup-*.sh ./scripts/containers/post-setup-*.sh; do
  if [ -f "$extra_script" ]; then
    # Check if already executed
    already_run=false
    for run_script in "${ordered_scripts[@]}"; do
      if [ "$extra_script" = "$run_script" ]; then
        already_run=true
        break
      fi
    done
    if [ "$already_run" = false ]; then
      short_name=$(basename "$extra_script" | sed -E 's/^(setup-|post-setup-)//' | cut -d. -f1)
      echo "[*] Configuring custom ${short_name}..."
      bash "$extra_script"
      if [ $? -ne 0 ]; then
        echo "[!] Error occurred while configuring ${short_name}. Aborting..."
        exit 1
      fi
    fi
  fi
done

# Clean up temporary directory
rm -rf ./.tmp

# Fix permissions for generated files (User owned, Container readable)
if [ -n "${SUDO_USER:-}" ]; then
  echo "[*] Fixing permissions for user $SUDO_USER..."
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" ./composes
  chmod -R o+rX ./composes

  # Restore strict permissions for acme.json files (Traefik requirement)
  find ./composes -name "acme.json" -exec chmod 600 {} + 2>/dev/null || true

  # Ensure CrowdSec bouncer key is readable by Traefik container
  find ./composes -name "BOUNCER_KEY_traefik" -exec chmod 644 {} + 2>/dev/null || true
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
