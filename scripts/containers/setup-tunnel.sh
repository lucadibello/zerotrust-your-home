#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Check if Cloudflare Tunnel is enabled (default: true)
if [ "${ENABLE_TUNNEL:-true}" != "true" ]; then
  echo "[*] Cloudflare Tunnel is disabled, skipping setup..."
  exit 0
fi

# Validate TUNNEL_TOKEN if tunnel is enabled
if [ -z "${TUNNEL_TOKEN:-}" ]; then
  echo "[!] TUNNEL_TOKEN is not set. Please update your .env file."
  exit 1
fi

# Ensure traefik-network exists for tunnel connectivity
docker network create traefik-network >/dev/null 2>&1 || true

echo "[OK] Cloudflare Tunnel setup completed"
