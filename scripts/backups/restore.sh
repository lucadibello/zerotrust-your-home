#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
COMPOSE_ARGS=$(bash "$PROJECT_DIR/scripts/get_docker_compose_files.sh")

RESTORE_SERVICES_STOPPED=false
RESTORE_CLEANUP_RUNNING=false
cleanup() {
    if [ "$RESTORE_CLEANUP_RUNNING" = "true" ]; then return 0; fi
    RESTORE_CLEANUP_RUNNING=true
    trap '' EXIT INT TERM

    if [ "$RESTORE_SERVICES_STOPPED" = "true" ]; then
        echo ""
        echo "[!] Interrupted during restore. Attempting to restart services..."
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start 2>/dev/null || true
    fi
    exit 1
}
trap cleanup EXIT INT TERM

echo "==========================================="
echo "      ZeroTrust Home Restore Utility       "
echo "==========================================="
echo "1) System Restore (Full Overwrite)"
echo "   - Restores entire Restic snapshot to /"
echo "2) Immich Photos Restore"
echo "   - Restores photos via immich-go zip archives"
echo "3) Database Restore"
echo "   - Restore SQL dumps (PostgreSQL / Immich / Nextcloud)"
echo "4) Single Service Restore (In-Place)"
echo "   - Restore ONLY a specific folder directly over live data"
echo "5) Extract to Staging (Safe File Recovery)"
echo "   - Extract specific files/folders to a temporary folder"
echo "   - Safest way to recover a single accidentally deleted file"
echo "6) Rebuild Local Repository from Cloud"
echo "   - Download entire repository to local disk (Drive Failure Scenario)"
echo "7) Nextcloud Data Info"
echo "q) Quit"
echo "-------------------------------------------"
echo -n "Select an option: "
read OPTION

get_repo_args() {
    echo "Select Restore Source:"
    echo "1) Local Disk (Recommended - Fast)"
    echo "2) Cloud Storage"
    echo -n "Select option [1]: "
    read SOURCE_OPT
    
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

    if [ "$SOURCE_OPT" = "1" ] || [ -z "$SOURCE_OPT" ]; then
        LOCAL_REPO="/repos/local/restic"
        if docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
          exec -T backup test -f /repos/local/config 2>/dev/null; then
            LOCAL_REPO="/repos/local"
        fi
        echo "-r $LOCAL_REPO"
    else
        echo ""
    fi
}

case $OPTION in
    1)
        REPO_ARGS=$(get_repo_args)
        echo "[*] Fetching snapshots..."
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic $REPO_ARGS snapshots -H docker
        
        echo -n "Enter backup ID to restore: "
        read ID
        if [ -z "$ID" ]; then exit 1; fi

        echo "[!] WARNING: This will STOP all services and OVERWRITE Docker volumes."
        echo -n "Are you sure? [y/N]: "
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then exit 0; fi

        echo "[*] Stopping service containers..."
        RESTORE_SERVICES_STOPPED=true
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" stop
        
        echo "[*] Restoring Snapshot $ID..."
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" \
            exec backup restic $REPO_ARGS restore $ID -H docker --exclude backingFsBlockDev --target / 
            
        echo "[*] Restarting containers..."
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start
        RESTORE_SERVICES_STOPPED=false

        for handler in "$PROJECT_DIR/scripts/backups/services"/*/handler.sh; do
            if [ -f "$handler" ]; then bash "$handler" "post-restore" || true; fi
        done
        ;;
    
    2)
        bash "$SCRIPT_DIR/restore-immich.sh"
        ;;
    
    3)
        bash "$SCRIPT_DIR/restore-db.sh"
        ;;

    4)
        REPO_ARGS=$(get_repo_args)
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic $REPO_ARGS snapshots -H docker
        echo -n "Enter backup ID: "
        read ID
        if [ -z "$ID" ]; then exit 1; fi
        
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic $REPO_ARGS ls $ID /mnt/backup | grep "^d" | awk '{print $NF}'
        echo -n "Path to restore (e.g. /mnt/backup/docker/vaultwarden_data): "
        read TARGET_PATH
        if [ -z "$TARGET_PATH" ]; then exit 1; fi

        echo "[!] Restoring ONLY: $TARGET_PATH OVERWRITING live data!"
        echo -n "Are you sure? [y/N]: "
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then exit 0; fi

        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" \
            exec backup restic $REPO_ARGS restore $ID --include "$TARGET_PATH" --target /
            
        for handler in "$PROJECT_DIR/scripts/backups/services"/*/handler.sh; do
            if [ -f "$handler" ]; then bash "$handler" "post-restore" || true; fi
        done
        ;;

    5)
        echo "-------------------------------------------"
        echo "Extract to Staging (Safe File Recovery)"
        echo "-------------------------------------------"
        REPO_ARGS=$(get_repo_args)
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic $REPO_ARGS snapshots -H docker
        echo -n "Enter backup ID: "
        read ID
        if [ -z "$ID" ]; then exit 1; fi
        
        echo -n "Path to extract (e.g. /mnt/backup/docker/vaultwarden_data/config.json): "
        read TARGET_PATH
        if [ -z "$TARGET_PATH" ]; then exit 1; fi

        STAGING_DIR="$PROJECT_DIR/composes/backup/staging-restore"
        mkdir -p "$STAGING_DIR"
        
        echo "[*] Extracting $TARGET_PATH to $STAGING_DIR..."
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1
        docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" \
            exec backup restic $REPO_ARGS restore $ID --include "$TARGET_PATH" --target /mnt/backup/project/composes/backup/staging-restore
            
        echo "[OK] Extracted successfully!"
        echo "You can find your files safely extracted on the host machine at:"
        echo "$STAGING_DIR$TARGET_PATH"
        echo ""
        echo "Copy them manually to where you need them."
        ;;

    6)
        bash "$SCRIPT_DIR/rebuild-local-repo.sh"
        ;;

    7)
        echo "Nextcloud data (files) are backed up by Restic from ${NEXTCLOUD_DATADIR:-/mnt/nas-data/nextcloud}."
        echo "You can restore them using System Restore (Option 1) or Extract to Staging (Option 5)."
        ;;
        
    q|Q)
        exit 0
        ;;
        
    *)
        echo "Invalid option."
        exit 1
        ;;
esac

trap - EXIT INT TERM
