#!/bin/bash
set -uo pipefail

echo "[*] Triggering manual integrity check via Restic container..."

# Ensure the check container is running
docker compose -f composes/backup/docker-compose.yaml up -d check >/dev/null 2>&1 || true

if docker exec restic-check /bin/sh -c "check"; then
    echo "[OK] Manual check triggered successfully."
else
    echo "[*] Falling back to manual restic check execution..."
    docker exec restic-check restic -r /repos/local/restic check --read-data-subset=10%
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD:-}"
        docker exec -e RESTIC_FROM_PASSWORD="$RESTIC_FROM_PASSWORD" restic-check restic -r "$CLOUD_RESTIC_REPOSITORY" check --read-data-subset=10%
    fi
fi
