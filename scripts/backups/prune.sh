#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env file
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

cd "$PROJECT_DIR/composes" || exit 1

echo "[*] Running prune (Local)..."
sudo docker compose -f restic.docker-compose.yaml --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r /repos/local/restic forget --keep-last 5 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
LOCAL_EXIT=$?

CLOUD_EXIT=0
IS_RCLONE=false
if [[ "$RESTIC_REPOSITORY" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "[*] Cloud prune skipped: Rclone is not configured."
else
    echo "[*] Running prune (Cloud)..."
    sudo docker compose -f restic.docker-compose.yaml --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic forget --keep-last 5 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
    CLOUD_EXIT=$?
fi

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] Prune completed successfully"
else
  echo "[ERROR] Prune failed (local=$LOCAL_EXIT, cloud=$CLOUD_EXIT)"
fi

cd "$PROJECT_DIR"
exit $(( LOCAL_EXIT || CLOUD_EXIT ))
