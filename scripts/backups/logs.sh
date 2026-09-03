#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"

echo "==========================================="
echo "       ZeroTrust Backup Daemon Logs        "
echo "==========================================="
echo "Fetching the last 100 lines of logs from the backup daemons..."
echo ""

docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" logs --tail=100 -f backup prune check
