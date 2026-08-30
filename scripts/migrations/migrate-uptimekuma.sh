#!/bin/bash
# Migration script for Uptime Kuma (Bind Mount -> Named Volume)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

VOLUME_NAME="uptimekuma_data"
CONTAINER_NAME="uptimekuma"
BIND_PATH="$PROJECT_DIR/composes/uptimekuma"
if [ ! -d "$BIND_PATH" ] && [ -d "$PROJECT_DIR/composes/uptime-kuma" ]; then
    BIND_PATH="$PROJECT_DIR/composes/uptime-kuma"
fi

echo "[*] Migrating Uptime Kuma from bind mount to named volume..."

# 1. Stop the container
echo "[*] Stopping Uptime Kuma..."
sudo docker compose -f "$PROJECT_DIR/composes/uptimekuma/docker-compose.yaml" --env-file "$PROJECT_DIR/.env" stop 2>/dev/null || true

# 2. Create the volume
echo "[*] Creating volume '$VOLUME_NAME'..."
sudo docker volume create "$VOLUME_NAME"

# 3. Copy data
if [ -d "$BIND_PATH" ]; then
    echo "[*] Copying data from $BIND_PATH to volume..."
    sudo docker run --rm \
        -v "$BIND_PATH":/source \
        -v "$VOLUME_NAME":/target \
        alpine \
        sh -c "cp -av /source/. /target/"
fi

echo "[*] Data copy complete."
echo "[*] NOTE: You can now start Uptime Kuma with 'make start-uptimekuma'."
