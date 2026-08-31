#!/bin/bash

trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
if [ -f "$PROJECT_DIR/.env" ]; then
    load_env "$PROJECT_DIR/.env"
elif [ -f .env ]; then
    load_env .env
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
YESTERDAY=$(date -d '1 day ago' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')

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

# Ensure log directory exists on host
IMMICH_LOG_DIR="/var/log/immich-go"
mkdir -p "$IMMICH_LOG_DIR" 2>/dev/null || true

# Run immich-go inside an alpine container attached to the immich-network
# We mount the statically linked binary from the host
# Logs are exported to /var/log/immich-go/ for Loki collection
docker run --rm \
    --network immich-network \
    -v /usr/local/bin/immich-go:/usr/local/bin/immich-go:ro \
    -v "$BACKUP_DIR":/backup \
    -v "$IMMICH_LOG_DIR":/root/.cache/immich-go \
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
