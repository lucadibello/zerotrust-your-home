#!/bin/bash
set -uo pipefail

echo "[*] Triggering manual prune via Restic container..."

# Ensure the prune container is running
docker compose -f composes/backup/docker-compose.yaml up -d prune >/dev/null 2>&1 || true

if docker exec restic-prune /bin/sh -c "prune"; then
    echo "[OK] Manual prune triggered successfully."
else
    source "$PROJECT_DIR/.env" 2>/dev/null || true
    PRUNE_ARGS="${RESTIC_FORGET_ARGS:---keep-last 3 --keep-daily 3 --keep-weekly 2 --keep-monthly 1}"
    docker exec restic-prune restic -r /repos/local/restic forget --prune $PRUNE_ARGS
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD:-}"
        docker exec -e RESTIC_FROM_PASSWORD="$RESTIC_FROM_PASSWORD" restic-prune restic -r "$CLOUD_RESTIC_REPOSITORY" forget --prune $PRUNE_ARGS
    fi
fi
