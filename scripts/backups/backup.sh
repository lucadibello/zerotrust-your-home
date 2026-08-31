#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

cd "$PROJECT_DIR" || exit 1
 
FORCE_FULL=false
 
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|-f)
      FORCE_FULL=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--full|-f]"
      echo ""
      echo "Options:"
      echo "  --full, -f    Force a full backup (runs a full Immich export and snapshot)"
      echo "  --help, -h    Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--full|-f]"
      exit 1
      ;;
  esac
done

if [ "$FORCE_FULL" = "true" ]; then
  echo "[*] Full backup override enabled."
fi

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
if [ ! -f "$RESTIC_COMPOSE" ]; then
  RESTIC_COMPOSE="$PROJECT_DIR/composes/restic.docker-compose.yaml"
fi

# Build list of active compose files to manage during backup
COMPOSE_ARGS=$(bash "$PROJECT_DIR/scripts/get_docker_compose_files.sh")

BACKUP_COMPLETED=false
CLEANUP_RUNNING=false
SERVICES_STOPPED=false
NEXTCLOUD_MAINTENANCE_ENABLED=false

# Cleanup function to ensure containers restart and maintenance mode is off
cleanup() {
  # Prevent recursive execution when Ctrl+C is pressed repeatedly
  if [ "$CLEANUP_RUNNING" = "true" ]; then
    return 0
  fi
  CLEANUP_RUNNING=true
  trap '' EXIT INT TERM

  echo ""
  echo "[!] Script interrupted or failed. Running cleanup..."

  # Restart containers ONLY if they were previously stopped
  if [ "$SERVICES_STOPPED" = "true" ]; then
    echo "[*] Restarting containers (Emergency)..."
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start 2>/dev/null || true

    # Start Nextcloud AIO sibling containers explicitly
    if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
      echo "[*] Starting Nextcloud AIO containers (Emergency)..."
      docker start nextcloud-aio-database nextcloud-aio-redis nextcloud-aio-apache nextcloud-aio-nextcloud 2>/dev/null || true
      sleep 5
    fi
  fi

  # Disable Maintenance Mode for Nextcloud if it was activated
  if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ] && [ "$NEXTCLOUD_MAINTENANCE_ENABLED" = "true" ]; then
    if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
      echo "[*] Disabling Nextcloud Maintenance Mode (Emergency)..."
      docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off 2>/dev/null || true
    fi
  fi

  if [ "$BACKUP_COMPLETED" != "true" ]; then
    send_ntfy "Backup Aborted" "CRITICAL: Backup process was interrupted or encountered an unexpected failure." "warning,x,floppy_disk" "urgent"
  fi

  exit 1
}

# Function to restart containers and disable maintenance mode normally
start_services() {
  echo "[*] Restarting containers..."
  docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start

  if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
    echo "[*] Starting Nextcloud AIO containers..."
    docker start nextcloud-aio-database nextcloud-aio-redis nextcloud-aio-apache nextcloud-aio-nextcloud 2>/dev/null || true
    
    echo "[*] Waiting for Nextcloud container to start..."
    ATTEMPTS=0
    while ! docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; do
      if [ $ATTEMPTS -ge 30 ]; then
        echo "[WARNING] Nextcloud container failed to start within timeout. Cannot disable maintenance mode."
        break
      fi
      sleep 2
      ATTEMPTS=$((ATTEMPTS + 1))
    done

    if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
      echo "[*] Disabling Nextcloud Maintenance Mode..."
      sleep 5
      docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off 2>/dev/null || true
      NEXTCLOUD_MAINTENANCE_ENABLED=false
    fi
  fi
  SERVICES_STOPPED=false
}

# Register cleanup trap
trap cleanup EXIT INT TERM

# Check for required environment variables
if [ -z "${LOCAL_BACKUP_DIR:-}" ]; then
  echo "[ERROR] Required environment variable LOCAL_BACKUP_DIR is not set."
  echo "        Please check your .env file."
  send_ntfy "Backup Configuration Error" "Backup aborted: LOCAL_BACKUP_DIR is not set in .env." "warning,x,floppy_disk" "high"
  BACKUP_COMPLETED=true
  exit 1
fi

if [ -z "${RESTIC_PASSWORD:-}" ]; then
  echo "[ERROR] Required environment variable RESTIC_PASSWORD is not set."
  echo "        Please check your .env file."
  send_ntfy "Backup Configuration Error" "Backup aborted: RESTIC_PASSWORD is not set in .env." "warning,x,floppy_disk" "high"
  BACKUP_COMPLETED=true
  exit 1
fi

if [ -z "${RESTIC_REPOSITORY:-}" ]; then
  echo "[ERROR] Required environment variable RESTIC_REPOSITORY is not set."
  echo "        Please check your .env file."
  send_ntfy "Backup Configuration Error" "Backup aborted: RESTIC_REPOSITORY is not set in .env." "warning,x,floppy_disk" "high"
  BACKUP_COMPLETED=true
  exit 1
fi

if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ] && [ -z "${NEXTCLOUD_DATADIR:-}" ]; then
  echo "[ERROR] Required environment variable NEXTCLOUD_DATADIR is not set while Nextcloud is enabled."
  echo "        Please check your .env file."
  send_ntfy "Backup Configuration Error" "Backup aborted: NEXTCLOUD_DATADIR is not set in .env while Nextcloud is enabled." "warning,x,floppy_disk" "high"
  BACKUP_COMPLETED=true
  exit 1
fi

# Ensure local backup directory exists
mkdir -p "${LOCAL_BACKUP_DIR}" 2>/dev/null || true

IMMICH_EXPORT_FAILED=false
DB_DUMP_FAILED=false

# Run Immich backup if enabled (requires Immich to be running)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
  echo "[*] Running Immich export..."
  IMMICH_FLAGS=()
  if [ "$FORCE_FULL" = "true" ]; then
    IMMICH_FLAGS+=("--full")
  fi
  if ! bash "$PROJECT_DIR/scripts/backups/backup-immich.sh" ${IMMICH_FLAGS[@]+"${IMMICH_FLAGS[@]}"}; then
    echo "[WARNING] Immich export encountered errors."
    IMMICH_EXPORT_FAILED=true
  fi
fi

# Enable Maintenance Mode for Nextcloud
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ] && docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
  echo "[*] Enabling Nextcloud Maintenance Mode..."
  docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --on
  NEXTCLOUD_MAINTENANCE_ENABLED=true
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
if ! bash "$PROJECT_DIR/scripts/backups/dump-databases.sh"; then
  echo "[ERROR] Database dumps encountered errors."
  DB_DUMP_FAILED=true
fi

echo "[*] Stopping containers for consistent state..."
SERVICES_STOPPED=true
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" stop

# Explicitly stop Nextcloud AIO sibling containers if they are running
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
  echo "[*] Ensuring Nextcloud AIO containers are stopped..."
  docker stop nextcloud-aio-database nextcloud-aio-nextcloud nextcloud-aio-redis nextcloud-aio-apache 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Restart services NOW after securing database dumps
# ------------------------------------------------------------------------------
echo "[*] Database dumps secured. Restarting services to minimize downtime..."
start_services

# Ensure the backup container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

echo "[*] Initializing repository if needed..."
# 1. Local Repository Initialization
if ! docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic -r /repos/local/restic snapshots >/dev/null 2>&1; then
  echo "[*] Local Repository not found. Initializing..."
  docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec backup restic -r /repos/local/restic init
fi

# 2. Cloud Repository Initialization (Check Rclone setup if using rclone backend)
IS_RCLONE=false
if [[ "${RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
  IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
  echo "[WARNING] Cloud backup skipped: Rclone is not configured ($PROJECT_DIR/config/rclone/rclone.conf missing)."
  echo "          Run 'make backup-configure' to configure Google Drive remote."
else
  if ! docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic snapshots >/dev/null 2>&1; then
    echo "[*] Cloud Repository not found. Initializing..."
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
      exec backup restic init
  fi
fi

echo "[*] Running backup (Services are ONLINE)..."
BACKUP_EXIT_CODE=0

# 1. Local Backup
echo "[*] >> Starting Local Backup (Live System to Second Disk)..."
echo "[!] NOTE: Raw database files in /var/lib/docker/volumes may be inconsistent."
echo "[!]       You MUST use the SQL dumps in backups/db-dumps/ for database recovery."
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec backup restic -r /repos/local/restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --verbose
LOCAL_EXIT=$?

# 2. Cloud Backup (Copy from Local Repo)
CLOUD_EXIT=0
if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
  CLOUD_EXIT=1
else
  echo "[*] >> Starting Cloud Backup (Copying from Local Repo)..."
  docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec -e RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}" backup restic copy --from-repo /repos/local/restic
  CLOUD_EXIT=$?
fi

# Send status notification
if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  if [ "$DB_DUMP_FAILED" = "true" ] || [ "$IMMICH_EXPORT_FAILED" = "true" ]; then
    echo "[WARNING] Backups completed, but pre-backup export had errors."
    BACKUP_EXIT_CODE=1
    send_ntfy "Backup Completed (Warnings)" "Restic snapshots completed to Local & Cloud, but database/photo export had errors. Check logs." "warning,floppy_disk" "high"
  else
    echo "[OK] All backups completed successfully"
    send_ntfy "Backup Successful" "Docker volumes backup to Local Disk and Cloud completed successfully!" "white_check_mark,floppy_disk" "default"
  fi
elif [ $LOCAL_EXIT -ne 0 ] && [ $CLOUD_EXIT -ne 0 ]; then
  echo "[ERROR] BOTH backups failed!"
  BACKUP_EXIT_CODE=1
  send_ntfy "Backup Failed" "CRITICAL: Both Local and Cloud backups failed! Check logs immediately." "warning,x,floppy_disk" "urgent"
elif [ $LOCAL_EXIT -ne 0 ]; then
  echo "[WARNING] Local backup failed, but Cloud backup succeeded."
  BACKUP_EXIT_CODE=1
  send_ntfy "Backup Warning" "Local backup to second disk failed, but Cloud backup succeeded. Check logs." "warning,floppy_disk" "high"
else
  if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "[WARNING] Local backup succeeded. Cloud backup skipped (Rclone not configured)."
    send_ntfy "Backup Warning" "Local backup to second disk completed. Cloud backup skipped: Rclone not configured. Run 'make backup-configure'." "warning,floppy_disk" "high"
  else
    echo "[WARNING] Cloud backup/copy failed, but Local backup succeeded."
    send_ntfy "Backup Warning" "Cloud backup copy to Google Drive failed (Local copy is SAFE on second disk). Check logs." "warning,floppy_disk" "high"
  fi
  BACKUP_EXIT_CODE=1
fi

# 3. Prune Old Backups
if [ $BACKUP_EXIT_CODE -eq 0 ]; then
  echo "[*] >> Pruning old snapshots to free up space..."
  bash "$PROJECT_DIR/scripts/backups/prune.sh"
fi

BACKUP_COMPLETED=true

# Unset trap before exiting successfully
trap - EXIT INT TERM

exit $BACKUP_EXIT_CODE
