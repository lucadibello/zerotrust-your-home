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

# Skip if Vaultwarden is not enabled
if [ "${ENABLE_VAULTWARDEN:-false}" != "true" ]; then
  echo "[*] Vaultwarden is disabled, skipping setup..."
  exit 0
fi

# Create vaultwarden persistent volume
sudo docker volume create vaultwarden_data >/dev/null 2>&1 || true

echo "[OK] Vaultwarden setup completed"
