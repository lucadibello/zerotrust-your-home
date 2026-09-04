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
         "$PROJECT_ROOT/composes/traefik/letsencrypt" \
         "$PROJECT_ROOT/composes/traefik/logs" \
         "$PROJECT_ROOT/composes/traefik/crowdsec"
touch "$PROJECT_ROOT/composes/traefik/logs/access.log"

# Ensure crowdsec bouncer key file exists so volume mount never fails
if [ ! -f "$PROJECT_ROOT/composes/traefik/crowdsec/BOUNCER_KEY_traefik" ]; then
  touch "$PROJECT_ROOT/composes/traefik/crowdsec/BOUNCER_KEY_traefik"
fi


# Create external networks if they don't already exist
docker network create traefik-network >/dev/null 2>&1 || true
docker network create nextcloud-aio >/dev/null 2>&1 || true

echo "[OK] Traefik setup completed"
