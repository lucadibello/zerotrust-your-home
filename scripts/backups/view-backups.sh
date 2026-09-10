#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
if [ ! -f "$RESTIC_COMPOSE" ]; then
    RESTIC_COMPOSE="$PROJECT_DIR/composes/restic.docker-compose.yaml"
fi

# Ensure backup container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

echo "=== Local Repository ==="
LOCAL_REPO="/repos/local/restic"
if docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup test -f /repos/local/config 2>/dev/null; then
    LOCAL_REPO="/repos/local"
fi

docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r "$LOCAL_REPO" snapshots -H docker || {
    log "[!] Could not read local repository at $LOCAL_REPO"
    echo "      Check that LOCAL_BACKUP_DIR in .env matches your host path and RESTIC_PASSWORD is correct."
}

echo ""
echo "=== Cloud Repository ==="
IS_RCLONE=false
if [[ "${RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" != "true" ]; then
    echo "  (Cloud repository not configured. Set RESTIC_REPOSITORY to an rclone remote in .env to enable.)"
elif [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "  (Cloud repository skipped: Rclone is not configured. Run 'make backup-configure' to set up.)"
else
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic -r "$RESTIC_REPOSITORY" snapshots -H docker || {
        log "[!] Could not read cloud repository."
    }
fi