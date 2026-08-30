#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

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
sudo docker network create traefik-network >/dev/null 2>&1 || true

echo "[OK] Cloudflare Tunnel setup completed"
