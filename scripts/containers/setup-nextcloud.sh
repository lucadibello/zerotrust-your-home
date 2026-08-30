#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Skip if Nextcloud is not enabled
if [ "${ENABLE_NEXTCLOUD:-false}" != "true" ]; then
  echo "[*] Nextcloud is disabled, skipping setup..."
  exit 0
fi

# Create Nextcloud AIO volume
sudo docker volume create nextcloud_aio_mastercontainer >/dev/null 2>&1 || true

# Create network for Nextcloud AIO internal cluster
sudo docker network create nextcloud-aio >/dev/null 2>&1 || true

# Ensure Nextcloud datadir exists
mkdir -p "${NEXTCLOUD_DATADIR:-/mnt/nas-data}"

# Generate dynamic configuration for Traefik using template
TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/nextcloud.yml.template"
TARGET="$PROJECT_ROOT/composes/traefik/dynamic/nextcloud.yml"

render_template "$TEMPLATE" "$TARGET" \
  DOMAIN="$DNS_DOMAIN"

echo "[OK] Nextcloud setup completed"
