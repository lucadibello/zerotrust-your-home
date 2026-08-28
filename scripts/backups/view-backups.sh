#!/bin/bash
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

cd "$PROJECT_DIR/composes" || exit 1

echo "=== Local Repository ==="
sudo docker compose -f restic.docker-compose.yaml --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r /repos/local/restic snapshots -H docker 2>/dev/null || echo "  (No local repository found or not initialized)"

echo ""
echo "=== Cloud Repository ==="
# Check if rclone is needed and configured
IS_RCLONE=false
if [[ "$RESTIC_REPOSITORY" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "  (Cloud repository skipped: Rclone is not configured. Run 'make configure-backup' to set up.)"
else
    sudo docker compose -f restic.docker-compose.yaml --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic snapshots -H docker 2>/dev/null || echo "  (No cloud repository found or not initialized)"
fi

cd "$PROJECT_DIR"