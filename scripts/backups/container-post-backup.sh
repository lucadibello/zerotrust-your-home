#!/bin/bash
set -uo pipefail

STATUS="$1"

echo "[*] Running POST_COMMANDS inside Restic container with status: $STATUS"

# Copy to Cloud
if [ "$STATUS" = "success" ]; then
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        echo "[*] Copying local snapshot to cloud repository ($CLOUD_RESTIC_REPOSITORY)..."
        export RESTIC_FROM_PASSWORD="$RESTIC_PASSWORD"
        restic -r "$CLOUD_RESTIC_REPOSITORY" copy --from-repo /repos/local/restic
        if [ $? -ne 0 ]; then
             echo "[!] Copy failed! Will notify."
             STATUS="success_but_copy_failed"
        fi
    fi
fi

# Send Ntfy
if [ -n "${NTFY_TOPIC:-}" ]; then
    NTFY_BASE="${NTFY_URL:-https://ntfy.home.lucadibello.ch}"
    NTFY_ENDPOINT="${NTFY_BASE%/}/${NTFY_TOPIC}"
    
    if [ "$STATUS" = "success" ]; then
        curl -s -H "Title: Backup Successful" -H "Tags: white_check_mark,floppy_disk" -d "Local and Cloud backup completed!" "$NTFY_ENDPOINT"
    elif [ "$STATUS" = "success_but_copy_failed" ]; then
        curl -s -H "Title: Backup Warning" -H "Priority: high" -H "Tags: warning,floppy_disk" -d "Local backup success, but Cloud copy failed!" "$NTFY_ENDPOINT"
    else
        curl -s -H "Title: Backup Failed" -H "Priority: high" -H "Tags: warning,x,floppy_disk" -d "Backup failed during local snapshot ($STATUS)!" "$NTFY_ENDPOINT"
    fi
fi
