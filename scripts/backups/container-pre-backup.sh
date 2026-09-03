#!/bin/bash
set -uo pipefail

echo "[*] Running PRE_COMMANDS inside Restic container..."

PROJECT_DIR="/mnt/backup/project"
DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"
mkdir -p "$DUMP_DIR"

# Ensure we have docker client available
if ! command -v docker &> /dev/null; then
    echo "[!] Docker CLI not found. Trying to install docker-cli..."
    apk add --no-cache docker-cli || true
fi

# Load active handlers
HANDLERS=()
for handler in "$PROJECT_DIR/scripts/backups/services"/*/handler.sh; do
    if [ -f "$handler" ]; then
        svc="$(basename "$(dirname "$handler")")"
        FLAG="ENABLE_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
        # In this container context, we only check the explicit env variables passed through compose
        if [ "${!FLAG:-false}" = "true" ]; then
            HANDLERS+=("$handler")
        fi
    fi
done

# Run pre-backup handlers
for handler in "${HANDLERS[@]}"; do
    echo "[*] [pre-backup] $(basename "$(dirname "$handler")")..."
    bash "$handler" "pre-backup" || echo "[WARNING] Handler $handler failed in phase pre-backup."
done

# Run dump handlers
for handler in "${HANDLERS[@]}"; do
    echo "[*] [dump] $(basename "$(dirname "$handler")")..."
    bash "$handler" "dump" || echo "[WARNING] Handler $handler failed in phase dump."
done

echo "[*] Gathering excludes..."
rm -f /tmp/excludes.txt
touch /tmp/excludes.txt
for handler in "${HANDLERS[@]}"; do
    dir="$(dirname "$handler")"
    if [ -f "$dir/excludes.txt" ]; then
        cat "$dir/excludes.txt" >> /tmp/excludes.txt
    fi
done

echo "[*] Stopping containers for consistent snapshot..."
docker ps -q --filter "label=com.docker.compose.project=zerotrust-your-home" --filter "status=running" | grep -v "$HOSTNAME" > /tmp/containers_to_restart || true

if [ -s /tmp/containers_to_restart ]; then
    echo "Stopping $(wc -l < /tmp/containers_to_restart) containers..."
    xargs docker stop < /tmp/containers_to_restart
    
    echo "[*] Restarting containers to minimize downtime (snapshotting from stable volumes)..."
    sleep 2
    xargs docker start < /tmp/containers_to_restart
fi

# Run resume handlers
for handler in "${HANDLERS[@]}"; do
    echo "[*] [resume] $(basename "$(dirname "$handler")")..."
    bash "$handler" "resume" || echo "[WARNING] Handler $handler failed in phase resume."
done

echo "[*] Pre-backup tasks completed. Restic will now run."
