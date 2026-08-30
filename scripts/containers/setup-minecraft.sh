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
sudo docker volume create mcdata >/dev/null 2>&1 || true

# Create isolated Minecraft network
sudo docker network create mc-network >/dev/null 2>&1 || true

echo "[OK] Minecraft server setup completed"
