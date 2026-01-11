#!/bin/bash
trap "exit" INT

# Load .env
set -a
source .env
set +a

# Skip if SearXNG is not enabled
if [ "$ENABLE_SEARXNG" != "true" ]; then
  echo "[*] SearXNG is disabled, skipping setup..."
  exit 0
fi

# Ensure the searxng settings directory exists
mkdir -p ./composes/searxng

# Create configuration file for SearXNG by replacing placeholders in the template
sed "s/<SEARCHXNG_SECRET_KEY>/$SEARCHXNG_SECRET_KEY/g" ./scripts/containers/templates/settings.yml.template | tee ./composes/searxng/settings.yml >/dev/null

echo "[OK] SearXNG setup completed"
