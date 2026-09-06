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

log "[*] Triggering manual integrity check via Restic container..."

# Ensure the check container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$PROJECT_DIR/composes/backup/docker-compose.yaml" --env-file "$PROJECT_DIR/.env" up -d check >/dev/null 2>&1 || true

if docker exec restic-check /bin/sh -c "check"; then
    log "[OK] Manual check triggered successfully."
else
    log "[*] Falling back to manual restic check execution..."
    docker exec restic-check restic -r /repos/local/restic check --read-data-subset=10%
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD:-}"
        docker exec -e RESTIC_FROM_PASSWORD="$RESTIC_FROM_PASSWORD" restic-check restic -r "$CLOUD_RESTIC_REPOSITORY" check --read-data-subset=10%
    fi
fi
