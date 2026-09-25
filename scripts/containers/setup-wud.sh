#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if WUD is disabled
if [ "${ENABLE_WUD:-false}" != "true" ]; then
  echo "[*] WUD image update notifier is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
WUD_DIR="$PROJECT_ROOT/composes/wud"
mkdir -p "$WUD_DIR"

# Create external networks if not already present
docker network create traefik-network >/dev/null 2>&1 || true

# Ensure persistent volume exists
docker volume create wud_data >/dev/null 2>&1 || true

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/wud.env.template"
TARGET="$WUD_DIR/wud.env"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

# Build optional bearer auth token config for ntfy if NTFY_TOKEN is configured
token_config=""
if [ -n "${NTFY_TOKEN:-}" ]; then
  token_config="WUD_TRIGGER_NTFY_HOMELAB_AUTH_TOKEN=${NTFY_TOKEN}"
fi

render_template "$TEMPLATE" "$TARGET" \
  TZ="${TZ:-Europe/Zurich}" \
  WUD_ADMIN_USER="${WUD_ADMIN_USER:-admin}" \
  WUD_ADMIN_PASSWORD="${WUD_ADMIN_PASSWORD:-admin}" \
  NTFY_URL="${NTFY_URL:-https://ntfy.home.lucadibello.ch}" \
  NTFY_TOPIC="${NTFY_TOPIC:-lucadibello-homelab-status}" \
  NTFY_AUTH_TOKEN_CONFIG="$token_config"

echo "[OK] WUD setup completed"
