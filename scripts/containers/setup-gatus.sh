#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Check enable flag (support ENABLE_GATUS, with fallback to legacy ENABLE_UPTIME_KUMA)
IS_ENABLED="${ENABLE_GATUS:-${ENABLE_UPTIME_KUMA:-false}}"
if [ "$IS_ENABLED" != "true" ]; then
  echo "[*] Gatus health monitoring is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
GATUS_DIR="$PROJECT_ROOT/composes/gatus"
mkdir -p "$GATUS_DIR/config"

# Create external networks if not already present
docker network create traefik-network >/dev/null 2>&1 || true
docker network create prometheus-network >/dev/null 2>&1 || true
docker network create loki-network >/dev/null 2>&1 || true
docker network create dns-network >/dev/null 2>&1 || true
docker network create home-network >/dev/null 2>&1 || true
docker network create immich-network >/dev/null 2>&1 || true
docker network create nextcloud-aio >/dev/null 2>&1 || true

# Render Gatus config from template
TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/gatus.yaml.template"
TARGET="$GATUS_DIR/config/config.yaml"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

render_template "$TEMPLATE" "$TARGET" \
  NTFY_URL="${NTFY_URL:-https://ntfy.sh}" \
  NTFY_TOPIC="${NTFY_TOPIC:-zerotrust-alerts}" \
  NTFY_TOKEN="${NTFY_TOKEN:-}" \
  DNS_DOMAIN="${DNS_DOMAIN:-example.com}"

echo "[OK] Gatus health monitoring setup completed"
