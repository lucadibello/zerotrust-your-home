#!/bin/bash
# Migration script for Uptime Kuma (Bind Mount -> Named Volume)

set -e

# Load .env
set -a
source .env
set +a

VOLUME_NAME="uptimekuma_data"
CONTAINER_NAME="uptimekuma"
BIND_PATH="./composes/uptime-kuma"

echo "[*] Migrating Uptime Kuma from bind mount to named volume..."

# 1. Stop the container
echo "[*] Stopping Uptime Kuma..."
sudo docker-compose -f composes/uptimekuma.docker-compose.yaml stop

# 2. Create the volume
echo "[*] Creating volume '$VOLUME_NAME'..."
sudo docker volume create $VOLUME_NAME

# 3. Copy data
echo "[*] Copying data from $BIND_PATH to volume..."
# Use a temporary container to mount both and copy
sudo docker run --rm \
    -v $(pwd)/$BIND_PATH:/source \
    -v $VOLUME_NAME:/target \
    alpine \
    sh -c "cp -av /source/. /target/"

echo "[*] Data copy complete."
echo "[*] NOTE: You must now apply the updated docker-compose file."
