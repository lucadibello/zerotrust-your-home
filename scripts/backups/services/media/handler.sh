#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

case "$PHASE" in
    pre-backup)
        # Configurations are stored under composes/media/config/
        ;;
    dump)
        log "[*] Media configs are ready for file-level snapshot."
        ;;
    resume)
        ;;
    pre-restore)
        ;;
    post-restore)
        ;;
esac
