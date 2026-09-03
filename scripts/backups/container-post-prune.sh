#!/bin/bash
set -uo pipefail

STATUS="$1"

echo "[*] Running POST_COMMANDS for prune with status: $STATUS"

if [ "$STATUS" = "success" ]; then
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        echo "[*] Pruning cloud repository..."
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}"
        restic -r "${CLOUD_RESTIC_REPOSITORY}" forget --prune ${RESTIC_FORGET_ARGS:---keep-last 3 --keep-daily 3 --keep-weekly 2 --keep-monthly 1}
    fi
    curl -s -H "Title: Prune Successful" -H "Tags: broom,white_check_mark" -d "Local and Cloud repositories pruned successfully." "${NTFY_URL%/}/${NTFY_TOPIC}"
else
    curl -s -H "Title: Prune Failed" -H "Priority: high" -H "Tags: broom,warning" -d "Automated prune failed!" "${NTFY_URL%/}/${NTFY_TOPIC}"
fi
