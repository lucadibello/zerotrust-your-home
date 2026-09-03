#!/bin/bash
set -uo pipefail

PHASE="$1"

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
