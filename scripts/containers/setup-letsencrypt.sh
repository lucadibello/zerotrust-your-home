#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Ensure the letsencrypt directory exists inside Traefik composes directory
ACME_DIR="$PROJECT_ROOT/composes/traefik/letsencrypt"
ACME_FILE="$ACME_DIR/acme.json"

mkdir -p "$ACME_DIR"

# If acme.json exists as a directory (created by Docker mistakenly), remove it
if [ -d "$ACME_FILE" ]; then
  echo "[!] $ACME_FILE is a directory (created by Docker by mistake). Removing and replacing with file..."
  rm -rf "$ACME_FILE"
fi

# Check if acme.json exists, if not create it
if [ ! -f "$ACME_FILE" ]; then
  echo "[*] Initializing $ACME_FILE..."
  touch "$ACME_FILE"
fi

# Set permissions to 600 (strictly required by Traefik for security)
chmod 600 "$ACME_FILE"

echo "[OK] LetsEncrypt ACME storage setup completed."
