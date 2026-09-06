#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
    load_env "$PROJECT_DIR/.env"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

log "[*] Triggering manual prune via Restic container..."

# Ensure the prune container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$PROJECT_DIR/composes/backup/docker-compose.yaml" --env-file "$PROJECT_DIR/.env" up -d prune >/dev/null 2>&1 || true

if docker exec restic-prune /bin/sh -c "prune"; then
    log "[OK] Manual prune triggered successfully."
else
    PRUNE_ARGS="${RESTIC_FORGET_ARGS:---keep-last 3 --keep-daily 3 --keep-weekly 2 --keep-monthly 1}"
    docker exec restic-prune restic -r /repos/local/restic forget --prune $PRUNE_ARGS
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD:-}"
        docker exec -e RESTIC_FROM_PASSWORD="$RESTIC_FROM_PASSWORD" restic-prune restic -r "$CLOUD_RESTIC_REPOSITORY" forget --prune $PRUNE_ARGS
    fi
fi
