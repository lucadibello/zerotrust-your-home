#!/bin/bash
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

echo "==========================================="
echo "      ZeroTrust Home Restore Utility       "
echo "==========================================="
echo "1) System Restore (Docker Volumes & Configs)"
echo "   - Restores Restic snapshot to /"
echo "   - Affects all Docker volumes and Project files"
echo "2) Immich Photos Restore"
echo "   - Restores photos from local backup"
echo "   - Uses immich-go to upload/import"
echo "3) Database Restore"
echo "   - Restore specific SQL dumps (e.g. Immich DB)"
echo "4) Nextcloud Data Info"
echo "   - Information on restoring Nextcloud files"
echo "q) Quit"
echo "-------------------------------------------"
echo -n "Select an option: "
read OPTION

case $OPTION in
    1)
        echo "[*] System Restore selected."
        bash "$SCRIPT_DIR/view-backups.sh"
        
        echo -n "Enter backup ID to restore: "
        read ID
        
        if [ -z "$ID" ]; then
            echo "No ID entered. Aborting."
            exit 1
        fi

        echo "[!] WARNING: This will STOP all services and OVERWRITE Docker volumes."
        echo -n "Are you sure? [y/N]: "
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
            echo "Aborted."
            exit 0
        fi

        # Stop containers
        echo "[*] Stopping containers..."
        cd "$PROJECT_DIR/composes" || exit 1
        
        # Build service list
        SERVICES="-f dns.docker-compose.yaml -f traefik.docker-compose.yaml -f prometheus.docker-compose.yaml -f loki.docker-compose.yaml -f uptimekuma.docker-compose.yaml -f watchtower.docker-compose.yaml"
        [ "$ENABLE_HOME_AUTOMATION" = "true" ] && [ -f home.docker-compose.yaml ] && SERVICES="$SERVICES -f home.docker-compose.yaml"
        [ "$ENABLE_IMMICH" = "true" ] && [ -f immich.docker-compose.yaml ] && SERVICES="$SERVICES -f immich.docker-compose.yaml"
        [ "$ENABLE_NEXTCLOUD" = "true" ] && [ -f nextcloud.docker-compose.yaml ] && SERVICES="$SERVICES -f nextcloud.docker-compose.yaml"
        [ "$ENABLE_VAULTWARDEN" = "true" ] && [ -f vaultwarden.docker-compose.yaml ] && SERVICES="$SERVICES -f vaultwarden.docker-compose.yaml"
        [ "$ENABLE_SEARXNG" = "true" ] && [ -f searxng.docker-compose.yaml ] && SERVICES="$SERVICES -f searxng.docker-compose.yaml"
        [ "$ENABLE_MINECRAFT" = "true" ] && [ -f mcserver.docker-compose.yaml ] && SERVICES="$SERVICES -f mcserver.docker-compose.yaml"
        [ "$ENABLE_PORTAINER" = "true" ] && [ -f portainer.docker-compose.yaml ] && SERVICES="$SERVICES -f portainer.docker-compose.yaml"
        
        sudo docker compose $SERVICES --env-file "$PROJECT_DIR/.env" stop
        
        # Restore
        echo "[*] Restoring Snapshot $ID..."
        sudo docker compose -f restic.docker-compose.yaml --env-file "$PROJECT_DIR/.env" \
            exec backup restic restore $ID -H docker --exclude backingFsBlockDev --target / 
            
        # Restart
        echo "[*] Restarting containers..."
        sudo docker compose $SERVICES --env-file "$PROJECT_DIR/.env" start
        cd "$PROJECT_DIR"
        echo "[OK] System Restore completed."
        ;;
    
    2)
        bash "$SCRIPT_DIR/restore-immich.sh"
        ;;
    
    3)
        bash "$SCRIPT_DIR/restore-db.sh"
        ;;

        
    4)
        echo "-------------------------------------------"
        echo "Nextcloud Data Restore Info"
        echo "-------------------------------------------"
        echo "Your Nextcloud data (files) is stored in a host directory (default: /mnt/nas-data)."
        echo "This data is NOT included in the Restic System Backup (which covers Docker volumes)."
        echo ""
        echo "To restore your files:"
        echo "1. If you used Nextcloud AIO's built-in backup (Borg), use the AIO Interface to restore."
        echo "2. If you manually backed up /mnt/nas-data (e.g. via rsync to external drive):"
        echo "   Run: rsync -av /path/to/backup/ /mnt/nas-data/"
        echo "   Ensure permissions are correct (usually www-data:www-data or root:root depending on setup)."
        echo ""
        echo "Current configuration:"
        echo "NEXTCLOUD_DATADIR=${NEXTCLOUD_DATADIR:-\/mnt\/nas-data}" 
        ;;
        
    q|Q)
        echo "Exiting."
        exit 0
        ;;
        
    *)
        echo "Invalid option."
        exit 1
        ;;
esac
