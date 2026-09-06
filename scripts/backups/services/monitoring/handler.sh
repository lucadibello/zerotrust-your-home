#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

case "$PHASE" in
    pre-backup)
        ;;
    dump)
        ;;
    resume)
        ;;
    pre-restore)
        ;;
    post-restore)
        ;;
esac
