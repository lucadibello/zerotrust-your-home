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

# Check if settings.yml exists, if not create from example
if [ ! -f ./composes/searxng/settings.yml ]; then
  echo "[!] SearXNG settings.yml not found. Please configure ./composes/searxng/settings.yml"
  exit 1
fi

echo "[OK] SearXNG setup completed"
