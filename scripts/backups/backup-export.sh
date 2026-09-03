#!/bin/bash
set -uo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

export FORCE_FULL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|-f)
      export FORCE_FULL=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--full|-f]"
      echo ""
      echo "Options:"
      echo "  --full, -f    Force a full export (full photo export + DB dumps)"
      echo "  --help, -h    Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

EXPORT_STATUS=0

COMPOSE_ARGS=$(bash "$PROJECT_DIR/scripts/get_docker_compose_files.sh")
HANDLERS=()
for handler in "$PROJECT_DIR/scripts/backups/services"/*/handler.sh; do
    if [ -f "$handler" ]; then
        svc="$(basename "$(dirname "$handler")")"
        FLAG="ENABLE_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
        if [ "${!FLAG:-false}" = "true" ] || [[ "$COMPOSE_ARGS" == *"composes/$svc/"* ]] || [[ "$COMPOSE_ARGS" == *"composes/$svc.docker-compose.yaml"* ]]; then
            HANDLERS+=("$handler")
        fi
    fi
done

for handler in "${HANDLERS[@]}"; do
    echo "[*] [dump] $(basename "$(dirname "$handler")")..."
    if ! bash "$handler" "dump"; then
        echo "[WARNING] Handler $handler failed in dump phase."
        EXPORT_STATUS=1
    fi
done

if [ $EXPORT_STATUS -eq 0 ]; then
    echo "[OK] Backup data exported successfully."
else
    echo "[WARNING] Backup data export finished with errors."
    send_ntfy "Backup Export Warning" "Data export (photos/databases) completed with errors. Check logs." "warning,floppy_disk" "high"
fi

exit $EXPORT_STATUS
