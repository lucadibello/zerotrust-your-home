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
    echo "Immich is not enabled. Cannot restore photos."
    exit 1
fi

BACKUP_DIR="${IMMICH_BACKUP_LOCATION:-/mnt/nextcloud-backups/immich}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Backup directory $BACKUP_DIR does not exist."
    exit 1
fi

echo "------------------------------------------------"
echo "Immich Photo Restore"
echo "------------------------------------------------"
echo "Location: $BACKUP_DIR"
echo ""
echo "Available Backup Types:"
if [ -d "$BACKUP_DIR/full" ]; then
    echo "  [full] Periodic Full Backups:"
    ls -1 "$BACKUP_DIR/full" | sed 's/^/    - /'
fi

if [ -d "$BACKUP_DIR/incremental" ]; then
    echo "  [incremental] Daily Incremental Backups:"
    ls -1 "$BACKUP_DIR/incremental" | sed 's/^/    - /'
fi
echo ""
echo "Enter the relative path to the backup folder you want to restore."
echo "Example: full/2026-01 or incremental/2026-01-10"
echo -n "> "
read RESTORE_REL_PATH

if [ -z "$RESTORE_REL_PATH" ]; then
    echo "Aborted."
    exit 1
fi

# Validate path
if [ ! -d "$BACKUP_DIR/$RESTORE_REL_PATH" ]; then
    echo "Error: Directory $BACKUP_DIR/$RESTORE_REL_PATH not found."
    exit 1
fi

echo "[*] Starting Immich restore from $RESTORE_REL_PATH..."
echo "[*] Note: This will import photos into your current Immich instance."

IMMICH_GO_BIN=$(command -v immich-go || echo "/usr/local/bin/immich-go")

# Run immich-go upload
sudo docker run --rm \
    --network immich-network \
    -v "$IMMICH_GO_BIN":/usr/local/bin/immich-go:ro \
    -v "$BACKUP_DIR":/backup \
    alpine:latest \
    /usr/local/bin/immich-go upload from-folder \
    --server http://immich_server:2283 \
    --api-key "$IMMICH_API_KEY" \
    "/backup/$RESTORE_REL_PATH"


if [ $? -eq 0 ]; then
    echo "[OK] Restore/Import completed successfully."
else
    echo "[ERROR] Restore/Import failed."
    exit 1
fi
