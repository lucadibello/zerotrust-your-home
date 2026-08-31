#!/bin/bash
set -uo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

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
      echo "  --full, -f    Force a full export (full Immich photo export + DB dumps)"
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

EXPORT_STATUS=0

# Run Immich backup if enabled (requires Immich to be running)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
    echo "[*] Running Immich export..."
    IMMICH_FLAGS=()
    if [ "$FORCE_FULL" = "true" ]; then
        IMMICH_FLAGS+=("--full")
    fi
    if ! bash "$PROJECT_DIR/scripts/backups/backup-immich.sh" ${IMMICH_FLAGS[@]+"${IMMICH_FLAGS[@]}"}; then
        echo "[WARNING] Immich photo export failed."
        EXPORT_STATUS=1
    fi
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
if ! bash "$PROJECT_DIR/scripts/backups/dump-databases.sh"; then
    echo "[ERROR] Database dumps failed."
    EXPORT_STATUS=1
fi

if [ $EXPORT_STATUS -eq 0 ]; then
    echo "[OK] Backup data exported successfully."
else
    echo "[WARNING] Backup data export finished with errors."
    send_ntfy "Backup Export Warning" "Data export (photos/databases) completed with errors. Check logs." "warning,floppy_disk" "high"
fi

exit $EXPORT_STATUS
