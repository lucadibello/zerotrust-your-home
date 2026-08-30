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

# Skip if ntfy self-hosting is disabled
if [ "${ENABLE_NTFY:-false}" != "true" ]; then
  echo "[*] Self-hosted ntfy is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
NTFY_DIR="$PROJECT_ROOT/composes/ntfy"
mkdir -p "$NTFY_DIR/config"

# Create external networks if not already present
sudo docker network create traefik-network >/dev/null 2>&1 || true
sudo docker network create prometheus-network >/dev/null 2>&1 || true

# Render ntfy server config from template
TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/ntfy-server.yml.template"
TARGET="$NTFY_DIR/config/server.yml"

render_template "$TEMPLATE" "$TARGET" \
  DNS_DOMAIN="${DNS_DOMAIN:-example.com}"

echo "[OK] Self-hosted ntfy setup completed"
