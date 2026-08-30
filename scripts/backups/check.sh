#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env file
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
if [ ! -f "$RESTIC_COMPOSE" ]; then
    RESTIC_COMPOSE="$PROJECT_DIR/composes/restic.docker-compose.yaml"
fi

echo "[*] Running integrity check (Local - 10% of data)..."
sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r /repos/local/restic check --read-data-subset=10%
LOCAL_EXIT=$?

CLOUD_EXIT=0
IS_RCLONE=false
if [[ "${RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "[*] Cloud integrity check skipped: Rclone is not configured."
else
    echo "[*] Running integrity check (Cloud - 10% of data)..."
    sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic check --read-data-subset=10%
    CLOUD_EXIT=$?
fi

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] Check completed successfully"
else
  echo "[ERROR] Check failed (local=$LOCAL_EXIT, cloud=$CLOUD_EXIT)"
fi

exit $(( LOCAL_EXIT || CLOUD_EXIT ))
