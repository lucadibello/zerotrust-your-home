#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"

echo "==========================================="
echo "   Rebuild Local Repository from Cloud     "
echo "==========================================="
echo "Scenario: Your local backup drive failed and you replaced it."
echo "This will download all backup packs from your Cloud repository"
echo "to the Local repository so you have local redundancy again."
echo ""
echo "Local Repo: /repos/local/restic"
echo "Cloud Repo: ${CLOUD_RESTIC_REPOSITORY}"
echo "-------------------------------------------"

if [ -z "${CLOUD_RESTIC_REPOSITORY:-}" ]; then
    echo "[!] CLOUD_RESTIC_REPOSITORY is not defined in .env!"
    exit 1
fi

echo -n "Are you sure you want to rebuild the local repository? [y/N]: "
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
fi

docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

echo "[*] Initializing Local Repository if missing..."
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec backup restic -r /repos/local/restic init || true

echo "[*] Starting restic copy (Cloud -> Local)..."
echo "[*] This may take a long time depending on your internet connection."

# Perform copy from cloud to local
# Since we pull from Cloud, we pass RESTIC_FROM_PASSWORD for the cloud repo if needed.
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec -e RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}" \
    backup restic -r /repos/local/restic copy --from-repo "${CLOUD_RESTIC_REPOSITORY}"

echo "[OK] Local repository rebuilt successfully!"
