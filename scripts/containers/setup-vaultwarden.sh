#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Vaultwarden is not enabled
if [ "${ENABLE_VAULTWARDEN:-false}" != "true" ]; then
  echo "[*] Vaultwarden is disabled, skipping setup..."
  exit 0
fi

# Create vaultwarden persistent volume
docker volume create vaultwarden_data >/dev/null 2>&1 || true

echo "[OK] Vaultwarden setup completed"
