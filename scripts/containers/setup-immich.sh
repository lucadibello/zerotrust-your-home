#!/bin/bash
trap "exit" INT

# Load .env
set -a
source .env
set +a

# Skip if Immich is not enabled
if [ "$ENABLE_IMMICH" != "true" ]; then
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
  if [ -z "${!var}" ]; then
    echo "[!] $var is not set. Please update your .env file for Immich."
    exit 1
  fi
done

# Create immich volume for pgdata / db_data
sudo docker volume create "${IMMICH_DB_DATA_LOCATION:-immich_db_data}" || true
sudo docker volume create immich_pgdata || true

# Create immich network
sudo docker network create immich-network || true


echo "[OK] Immich setup completed"
