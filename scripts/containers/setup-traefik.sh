#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if reverse proxy is disabled
if [ "${ENABLE_REVERSE_PROXY:-true}" != "true" ]; then
  echo "[*] Reverse proxy (Traefik) is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
mkdir -p "$PROJECT_ROOT/composes/traefik/dynamic" \
         "$PROJECT_ROOT/composes/traefik/letsencrypt"

# Create external networks if they don't already exist
sudo docker network create traefik-network >/dev/null 2>&1 || true
sudo docker network create nextcloud-aio >/dev/null 2>&1 || true

echo "[OK] Traefik setup completed"
