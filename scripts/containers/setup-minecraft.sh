#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Minecraft is not enabled
if [ "${ENABLE_MINECRAFT:-false}" != "true" ]; then
  echo "[*] Minecraft server is disabled, skipping setup..."
  exit 0
fi

# Validate required environment variables
if [ -z "${MC_TUNNEL_TOKEN:-}" ]; then
  echo "[!] MC_TUNNEL_TOKEN is not set. Please update your .env file."
  exit 1
fi

# Create Minecraft persistent data volume
docker volume create mcdata >/dev/null 2>&1 || true

# Create isolated Minecraft network
docker network create mc-network >/dev/null 2>&1 || true

echo "[OK] Minecraft server setup completed"
