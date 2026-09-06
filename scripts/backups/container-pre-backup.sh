#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-/mnt/backup/project}"
if [ ! -d "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

log "[*] Running PRE_COMMANDS inside Restic container..."

DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"
mkdir -p "$DUMP_DIR"

# Ensure we have docker client available
if ! command -v docker &> /dev/null; then
    log "[!] Docker CLI not found. Trying to install docker-cli..."
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
    log "[*] [pre-backup] $(basename "$(dirname "$handler")")..."
    bash "$handler" "pre-backup" || log "[WARNING] Handler $handler failed in phase pre-backup."
done

# Run dump handlers
for handler in "${HANDLERS[@]}"; do
    log "[*] [dump] $(basename "$(dirname "$handler")")..."
    bash "$handler" "dump" || log "[WARNING] Handler $handler failed in phase dump."
done

log "[*] Gathering excludes..."
rm -f /tmp/excludes.txt
touch /tmp/excludes.txt
for handler in "${HANDLERS[@]}"; do
    dir="$(dirname "$handler")"
    if [ -f "$dir/excludes.txt" ]; then
        cat "$dir/excludes.txt" >> /tmp/excludes.txt
    fi
done

log "[*] Stopping containers for consistent snapshot..."
docker ps -q --filter "label=com.docker.compose.project=zerotrust-your-home" --filter "status=running" | grep -v "$HOSTNAME" > /tmp/containers_to_restart || true

if [ -s /tmp/containers_to_restart ]; then
    container_count=$(wc -l < /tmp/containers_to_restart | tr -d ' ')
    log "[*] Stopping $container_count containers..."
    xargs docker stop < /tmp/containers_to_restart
    
    log "[*] Restarting containers to minimize downtime (snapshotting from stable volumes)..."
    sleep 2
    xargs docker start < /tmp/containers_to_restart
    log "[OK] Containers restarted successfully."
fi

# Run resume handlers
for handler in "${HANDLERS[@]}"; do
    log "[*] [resume] $(basename "$(dirname "$handler")")..."
    bash "$handler" "resume" || log "[WARNING] Handler $handler failed in phase resume."
done

log "[*] Pre-backup tasks completed. Restic will now run."
