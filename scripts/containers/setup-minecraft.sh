#!/bin/bash

# Load .env
set -a
source .env
set +a

# Skip if Minecraft is not enabled
if [ "$ENABLE_MINECRAFT" != "true" ]; then
  echo "[*] Minecraft server is disabled, skipping setup..."
  exit 0
fi

# Validate required environment variables
if [ -z "$MC_TUNNEL_TOKEN" ]; then
  echo "[!] MC_TUNNEL_TOKEN is not set. Please update your .env file."
  exit 1
fi

# Create minecraft data volume
sudo docker volume create mcdata || true

echo "[OK] Minecraft server setup completed"
