#!/bin/bash
set -uo pipefail

STATUS="$1"

echo "[*] Running POST_COMMANDS for check with status: $STATUS"

if [ "$STATUS" = "success" ]; then
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        echo "[*] Checking cloud repository..."
        export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}"
        restic -r "${CLOUD_RESTIC_REPOSITORY}" check --read-data-subset=10%
    fi
    curl -s -H "Title: Integrity Check Passed" -H "Tags: magnifying_glass,white_check_mark" -d "10% cryptographic verification of all Local and Cloud packs succeeded." "${NTFY_URL%/}/${NTFY_TOPIC}"
else
    curl -s -H "Title: Backup Integrity Compromised!" -H "Priority: urgent" -H "Tags: skull,warning" -d "Repository check failed! Disk rot or corruption detected in snapshots." "${NTFY_URL%/}/${NTFY_TOPIC}"
fi
