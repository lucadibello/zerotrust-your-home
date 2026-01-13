#!/bin/bash
trap "exit" INT

# Load .env
if [ -f .env ]; then
    set -a
    source .env
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
        echo "4) Single Service Restore (Granular)"
        echo "   - Restore ONLY a specific folder (e.g. just vaultwarden)"
        echo "   - Fast! Does not download the whole backup"
        echo "5) Nextcloud Data Info"
        echo "   - Information on restoring Nextcloud files"
        echo "q) Quit"
        echo "-------------------------------------------"
        echo -n "Select an option: "
        read OPTION

        case $OPTION in
            1)
                echo "[*] System Restore selected."
        
        # Source Selection
        echo "-------------------------------------------"
        echo "Select Restore Source:"
        echo "1) Local Disk (Recommended - Fast)"
        echo "2) Google Drive (Cloud - Slow)"
        echo "-------------------------------------------"
        echo -n "Select option [1]: "
        read SOURCE_OPT
        
        REPO_ARGS="" # Default to Cloud (Env vars)
        if [ "$SOURCE_OPT" = "1" ] || [ -z "$SOURCE_OPT" ]; then
            echo "[*] Using Local Repository (/repos/local/restic)"
            REPO_ARGS="-r /repos/local/restic"
        else
            echo "[*] Using Cloud Repository (Google Drive)"
        fi

        # View Backups
        echo "[*] Fetching snapshots..."
        sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
            exec backup restic $REPO_ARGS snapshots -H docker
        
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
        cd composes
        
        # Helper to stop common services
        SERVICES="-f dns.docker-compose.yaml -f traefik.docker-compose.yaml -f prometheus.docker-compose.yaml -f loki.docker-compose.yaml -f uptimekuma.docker-compose.yaml -f watchtower.docker-compose.yaml"
        [ "$ENABLE_HOME_AUTOMATION" = "true" ] && SERVICES="$SERVICES -f home.docker-compose.yaml"
        [ "$ENABLE_IMMICH" = "true" ] && SERVICES="$SERVICES -f immich.docker-compose.yaml"
        [ "$ENABLE_NEXTCLOUD" = "true" ] && SERVICES="$SERVICES -f nextcloud.docker-compose.yaml"
        [ "$ENABLE_VAULTWARDEN" = "true" ] && SERVICES="$SERVICES -f vaultwarden.docker-compose.yaml"
        
        sudo docker compose $SERVICES --env-file ../.env stop
        
        # Restore
        echo "[*] Restoring Snapshot $ID..."
        sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
            exec backup restic $REPO_ARGS restore $ID -H docker --exclude backingFsBlockDev --target / 
            
        # Restart
        echo "[*] Restarting containers..."
        sudo docker compose $SERVICES --env-file ../.env start
        cd ..
        echo "[OK] System Restore completed."
        ;;
    
    2)
        echo "-------------------------------------------"
        echo "Immich Restore Options"
        echo "-------------------------------------------"
        echo "1) Portable Restore (from immich-go backups)"
        echo "   - Uses zip files exported by immich-go"
        echo "   - Re-uploads images (slower, but cleaner)"
        echo "2) Full System Restore"
        echo "   - Use '1) System Restore' in main menu"
        echo "   - Restores raw files + DB dump (exact state recovery)"
        echo "   - Much faster for full recovery"
        echo "-------------------------------------------"
        echo -n "Select an option: "
        read IMMICH_OPT
        if [ "$IMMICH_OPT" = "1" ]; then
             bash ./scripts/backups/restore-immich.sh
        else
             echo "Please use Option 1 in the main menu for Full System Restore."
        fi
        ;;
    
    3)
        bash ./scripts/backups/restore-db.sh
        ;;
        
    4)
        echo "-------------------------------------------"
        echo "Single Service / Granular Restore"
        echo "-------------------------------------------"
        
        # Source Selection (reused logic could be a function, but keeping inline for safety)
        echo "Select Restore Source:"
        echo "1) Local Disk (Recommended - Fast)"
        echo "2) Google Drive (Cloud - Slow)"
        echo -n "Select option [1]: "
        read SOURCE_OPT
        
        REPO_ARGS=""
        if [ "$SOURCE_OPT" = "1" ] || [ -z "$SOURCE_OPT" ]; then
            echo "[*] Using Local Repository"
            REPO_ARGS="-r /repos/local/restic"
        else
            echo "[*] Using Cloud Repository"
        fi

        echo "[*] Fetching snapshots..."
        sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
            exec backup restic $REPO_ARGS snapshots -H docker
        
        echo -n "Enter backup ID to browse: "
        read ID
        
        if [ -z "$ID" ]; then
            echo "No ID entered. Aborting."
            exit 1
        fi

        echo "[*] Listing directories in snapshot $ID..."
        # List top-level directories in /mnt/backup
        sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
            exec backup restic $REPO_ARGS ls $ID /mnt/backup | grep "^d" | awk '{print $NF}'
            
        echo ""
        echo "Enter the full path of the folder to restore (from list above)."
        echo "Example: /mnt/backup/docker/vaultwarden_data"
        echo -n "Path to restore: "
        read TARGET_PATH
        
        if [ -z "$TARGET_PATH" ]; then
            echo "No path entered. Aborting."
            exit 1
        fi

        echo "[!] Restoring ONLY: $TARGET_PATH"
        echo "[!] This will restore it to the original location on this host."
        echo -n "Are you sure? [y/N]: "
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
            echo "Aborted."
            exit 0
        fi

        echo "[*] Restoring..."
        sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
            exec backup restic $REPO_ARGS restore $ID --include "$TARGET_PATH" --target /
            
        if [ $? -eq 0 ]; then
            echo "[OK] Service restore completed successfully."
        else
            echo "[ERROR] Restore failed."
        fi
        ;;

    5)
        echo "-------------------------------------------"
        echo "Nextcloud Data Restore Info"
        echo "-------------------------------------------"
        echo "Nextcloud data (files) are backed up by Restic from ${NEXTCLOUD_DATADIR}."
        echo "You can restore them using the System Restore (Option 1)."
        echo ""
        echo "If you need to manually restore ONLY the Nextcloud data directory:"
        echo "1. Ensure Nextcloud container is stopped."
        echo "2. Run: sudo docker compose -f restic.docker-compose.yaml exec backup restic restore <snapshot-id> --include /mnt/backup/nextcloud --target /"
        echo "   (This will restore to the original location on the host via bind mount)"
        echo ""
        echo "After restoring data and config, run '3) Database Restore' to restore the Nextcloud DB."
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
