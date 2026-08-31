#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if DIUN is disabled
if [ "${ENABLE_DIUN:-false}" != "true" ]; then
  echo "[*] DIUN image update notifier is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
DIUN_DIR="$PROJECT_ROOT/composes/diun"
mkdir -p "$DIUN_DIR/config"

# Create external networks if not already present
docker network create traefik-network >/dev/null 2>&1 || true

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/diun.yml.template"
TARGET="$DIUN_DIR/config/diun.yml"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

render_template "$TEMPLATE" "$TARGET" \
  NTFY_URL="${NTFY_URL:-https://ntfy.home.lucadibello.ch}" \
  NTFY_TOPIC="${NTFY_TOPIC:-lucadibello-homelab-status}" \
  NTFY_TOKEN="${NTFY_TOKEN:-}"

echo "[OK] DIUN setup completed"
