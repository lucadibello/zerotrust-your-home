#!/bin/bash

# Load .env
set -a
source .env
set +a

# Skip if Vaultwarden is not enabled
if [ "$ENABLE_VAULTWARDEN" != "true" ]; then
  echo "[*] Vaultwarden is disabled, skipping setup..."
  exit 0
fi

# Create vaultwarden docker volume
docker volume create vaultwarden_data || true

echo "[OK] Vaultwarden setup completed"
