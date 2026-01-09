#!/bin/bash

# Load .env
set -a
source .env
set +a

# Skip if Home Automation is not enabled
if [ "$ENABLE_HOME_AUTOMATION" != "true" ]; then
  echo "[*] Home Automation is disabled, skipping setup..."
  exit 0
fi

# Create custom network for Home Assistant and other dependant containers (ignore if already exists)
docker network create home-network || true

echo "[OK] Home Assistant setup completed"
