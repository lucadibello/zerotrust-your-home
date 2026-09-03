#!/bin/bash

echo "==========================================="
echo "       ZeroTrust Backup Cron Status        "
echo "==========================================="
echo "[*] Cron is now natively managed by the Restic Docker container."
echo "[*] Configuration is defined in composes/backup/docker-compose.yaml"
echo "    using the BACKUP_CRON and PRUNE_CRON environment variables."
echo ""
echo "To change the schedule, edit the variables in docker-compose.yaml and restart the service:"
echo "  docker compose -f composes/backup/docker-compose.yaml up -d"
echo "==========================================="
