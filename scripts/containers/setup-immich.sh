#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Immich is not enabled
if [ "${ENABLE_IMMICH:-false}" != "true" ]; then
  echo "[*] Immich is disabled, skipping setup..."
  exit 0
fi

# Validate required Immich environment variables
required_vars=(
  "IMMICH_UPLOAD_LOCATION"
  "IMMICH_DB_DATA_LOCATION"
  "IMMICH_VERSION"
  "IMMICH_DB_PASSWORD"
  "IMMICH_DB_USERNAME"
  "IMMICH_DB_DATABASE_NAME"
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "[!] $var is not set. Please update your .env file for Immich."
    exit 1
  fi
done

# Create Immich persistent volumes
sudo docker volume create "${IMMICH_DB_DATA_LOCATION:-immich_db_data}" >/dev/null 2>&1 || true
sudo docker volume create immich_pgdata >/dev/null 2>&1 || true
sudo docker volume create immich-model-cache >/dev/null 2>&1 || true

# Create isolated immich internal network
sudo docker network create immich-network >/dev/null 2>&1 || true

# Ensure host upload and log directories exist
mkdir -p "${IMMICH_UPLOAD_LOCATION}" \
         /var/log/immich-go 2>/dev/null || true

echo "[OK] Immich setup completed"
