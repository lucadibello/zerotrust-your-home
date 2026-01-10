#!/bin/bash

trap "exit" INT

# Load .env file
# We assume the script is run from project root or we find .env
if [ -f .env ]; then
    set -a
    source .env
    set +a
elif [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
elif [ -f ../../.env ]; then
    set -a
    source ../../.env
    set +a
else
    echo "Error: .env file not found."
    exit 1
fi

if [ "$ENABLE_IMMICH" != "true" ]; then
    echo "Immich is not enabled. Skipping backup."
    exit 0
fi

if [ -z "$IMMICH_API_KEY" ] || [ "$IMMICH_API_KEY" = "your-api-key" ]; then
    echo "Error: IMMICH_API_KEY is not set or is default. Please configure it in .env"
    exit 1
fi

BACKUP_DIR="${IMMICH_BACKUP_LOCATION:-/mnt/nextcloud-backups/immich}"
DAY_OF_MONTH=$(date '+%d')
TODAY=$(date '+%Y-%m-%d')
YESTERDAY=$(date -d '1 day ago' '+%Y-%m-%d')

# Ensure host directory exists (requires sudo if path is restricted, or user permissions)
if [ ! -d "$BACKUP_DIR" ]; then
    echo "[*] Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Determine Backup Strategy (Full vs Incremental)
if [ "$DAY_OF_MONTH" = "01" ]; then
    echo "[*] Date is 1st of the month. Running FULL Periodic Backup..."
    TARGET_PATH="/backup/full/$(date +%Y-%m)"
    ARGS=""
else
    echo "[*] Running INCREMENTAL Backup (Yesterday: $YESTERDAY to Today: $TODAY)..."
    TARGET_PATH="/backup/incremental/$TODAY"
    ARGS="--from-date-range=$YESTERDAY,$TODAY"
fi

echo "[*] Starting Immich backup to $BACKUP_DIR$TARGET_PATH..."

# Run immich-go inside an alpine container attached to the immich-network
# We mount the statically linked binary from the host
sudo docker run --rm \
    --network traefik-network \
    -v /usr/local/bin/immich-go:/usr/local/bin/immich-go:ro \
    -v "$BACKUP_DIR":/backup \
    alpine:latest \
    /usr/local/bin/immich-go archive from-immich \
    --from-server=http://immich_server:2283 \
    --from-api-key="$IMMICH_API_KEY" \
    --write-to-folder="$TARGET_PATH" \
    $ARGS

if [ $? -eq 0 ]; then
    echo "[OK] Immich backup completed successfully."
else
    echo "[ERROR] Immich backup failed."
    exit 1
fi
