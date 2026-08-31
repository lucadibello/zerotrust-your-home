#!/bin/bash

trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
if [ -f "$PROJECT_DIR/.env" ]; then
    load_env "$PROJECT_DIR/.env"
elif [ -f .env ]; then
    load_env .env
else
    echo "Error: .env file not found."
    exit 1
fi

if [ "$ENABLE_IMMICH" != "true" ]; then
    echo "Immich is not enabled. Skipping backup."
    exit 0
fi

if [ -z "$IMMICH_API_KEY" ] || [ "$IMMICH_API_KEY" = "your-api-key" ]; then
    echo "Error: IMMICH_API_KEY is not set or is default. Please configure it in .env"
    send_ntfy "Immich Backup Config Error" "IMMICH_API_KEY is not configured in .env." "warning,camera" "high"
    exit 1
fi

FORCE_FULL=false
CUSTOM_DATE_RANGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|-f)
      FORCE_FULL=true
      shift
      ;;
    --from-date-range=*|--date-range=*)
      CUSTOM_DATE_RANGE="${1#*=}"
      shift
      ;;
    --from-date-range|--date-range|-d)
      CUSTOM_DATE_RANGE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--full|-f] [--date-range <range>]"
      echo ""
      echo "Options:"
      echo "  --full, -f               Force a full photo archive (all photos without date filter)"
      echo "  --date-range, -d <range> Custom date range for export (e.g. 2026-08-01,2026-08-31)"
      echo "  --help, -h               Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

BACKUP_DIR="${IMMICH_BACKUP_LOCATION:-/mnt/nextcloud-backups/immich}"
DAY_OF_MONTH=$(date '+%d')
TODAY=$(date '+%Y-%m-%d')
YESTERDAY=$(date -d '1 day ago' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')

# Ensure host directory exists (requires sudo if path is restricted, or user permissions)
if [ ! -d "$BACKUP_DIR" ]; then
    echo "[*] Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# Determine Backup Strategy (Full vs Incremental)
if [ "$FORCE_FULL" = "true" ] || [ "$DAY_OF_MONTH" = "01" ]; then
    if [ "$FORCE_FULL" = "true" ]; then
        echo "[*] Full backup override requested. Running FULL Immich Backup..."
    else
        echo "[*] Date is 1st of the month. Running FULL Periodic Backup..."
    fi
    SUB_DIR="full/$(date +%Y-%m)"
    ARGS=""
elif [ -n "$CUSTOM_DATE_RANGE" ]; then
    echo "[*] Running custom date range backup ($CUSTOM_DATE_RANGE)..."
    SUB_DIR="custom/$TODAY"
    ARGS="--from-date-range=$CUSTOM_DATE_RANGE"
else
    echo "[*] Running INCREMENTAL Backup (Yesterday: $YESTERDAY to Today: $TODAY)..."
    SUB_DIR="incremental/$TODAY"
    ARGS="--from-date-range=$YESTERDAY,$TODAY"
fi

# Ensure immich_server container is running
if [ -z "$(docker ps -q -f name=immich_server 2>/dev/null)" ]; then
    echo "[ERROR] Immich server container (immich_server) is not running. Skipping export."
    send_ntfy "Immich Backup Failed" "immich_server container is not running. Photo export aborted." "warning,camera,x" "high"
    exit 1
fi

echo "[*] Starting Immich backup to $BACKUP_DIR/$SUB_DIR..."

# Ensure log directory exists on host
IMMICH_LOG_DIR="/var/log/immich-go"
mkdir -p "$IMMICH_LOG_DIR" 2>/dev/null || true

PREV_LOG=$(ls -t "$IMMICH_LOG_DIR"/immich-go_*.log 2>/dev/null | head -1 || true)

# Run immich-go inside an alpine container attached to the immich-network
# We mount the statically linked binary from the host
# Logs are exported to /var/log/immich-go/ for Loki collection
docker run --rm \
    --network immich-network \
    -v /usr/local/bin/immich-go:/usr/local/bin/immich-go:ro \
    -v "$BACKUP_DIR":/backup \
    -v "$IMMICH_LOG_DIR":/root/.cache/immich-go \
    alpine:latest \
    /usr/local/bin/immich-go archive from-immich \
    --from-server=http://immich_server:2283 \
    --from-api-key="$IMMICH_API_KEY" \
    --write-to-folder="/backup/$SUB_DIR" \
    $ARGS
IMMICH_EXIT=$?

# Identify the newly created log file
LATEST_LOG=$(ls -t "$IMMICH_LOG_DIR"/immich-go_*.log 2>/dev/null | head -1 || true)

# Detect failure if docker run exited non-zero OR if log file recorded errors
HAS_LOG_ERRORS=false
if [ -n "$LATEST_LOG" ] && [ "$LATEST_LOG" != "$PREV_LOG" ] && [ -f "$LATEST_LOG" ]; then
    if grep -qE "ERR |level=error|Unauthorized|Invalid credentials|connection refused|failed to connect" "$LATEST_LOG" 2>/dev/null; then
        HAS_LOG_ERRORS=true
    fi
fi

if [ $IMMICH_EXIT -eq 0 ] && [ "$HAS_LOG_ERRORS" = "false" ]; then
    echo "[OK] Immich backup completed successfully."
else
    echo "[ERROR] Immich backup failed."
    if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
        echo "[*] Relevant error logs from $LATEST_LOG:"
        grep -E "ERR |level=error|Unauthorized|Invalid credentials|connection refused|failed to connect" "$LATEST_LOG" 2>/dev/null | tail -n 5 || tail -n 5 "$LATEST_LOG"
    fi
    send_ntfy "Immich Backup Failed" "Immich photo export failed ($SUB_DIR). Check logs in /var/log/immich-go/." "warning,camera,x" "high"
    exit 1
fi
