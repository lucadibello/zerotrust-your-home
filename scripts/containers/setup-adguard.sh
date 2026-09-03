#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if AdGuard Home is not enabled
if [ "${ENABLE_ADGUARD:-false}" != "true" ]; then
  echo "[*] AdGuard Home is disabled, skipping setup..."
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/adguard/work" "$PROJECT_ROOT/composes/adguard/conf"

# Create external network if needed
docker network create traefik-network >/dev/null 2>&1 || true

echo "[OK] AdGuard Home setup completed"
