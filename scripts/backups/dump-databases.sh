#!/bin/bash
set -o pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"
mkdir -p "$DUMP_DIR"

echo "[*] Starting database dumps to $DUMP_DIR..."

# --- Immich Database Dump ---
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
    echo "[*] Dumping Immich database..."
    
    # Check if container is running
    if [ "$(docker ps -q -f name=immich_postgres)" ]; then
        docker exec -i immich_postgres pg_dump -c -U "${IMMICH_DB_USERNAME:-postgres}" "${IMMICH_DB_DATABASE_NAME:-immich}" | gzip > "$DUMP_DIR/immich_db_dump.sql.gz"
        
        if [ $? -eq 0 ]; then
            echo "[OK] Immich database dumped successfully."
        else
            echo "[ERROR] Immich database dump failed."
        fi
    else
        echo "[WARNING] Immich database container (immich_postgres) is not running. Skipping dump."
    fi
fi

# --- Nextcloud AIO Database Dump ---
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
    echo "[*] Dumping Nextcloud database..."
    
    # Check if container is running
    if [ "$(docker ps -q -f name=nextcloud-aio-database)" ]; then
        # Retrieve credentials from container environment
        NC_USER=$(docker exec nextcloud-aio-database printenv POSTGRES_USER)
        NC_DB=$(docker exec nextcloud-aio-database printenv POSTGRES_DB)
        NC_PASS=$(docker exec nextcloud-aio-database printenv POSTGRES_PASSWORD)
        
        if [ -n "$NC_USER" ] && [ -n "$NC_DB" ] && [ -n "$NC_PASS" ]; then
             docker exec -i -e PGPASSWORD="$NC_PASS" nextcloud-aio-database pg_dump -c -U "$NC_USER" "$NC_DB" | gzip > "$DUMP_DIR/nextcloud_db_dump.sql.gz"
             
             if [ $? -eq 0 ]; then
                echo "[OK] Nextcloud database dumped successfully."
             else
                echo "[ERROR] Nextcloud database dump failed."
             fi
        else
             echo "[ERROR] Could not retrieve Nextcloud database credentials. Skipping dump."
        fi
    else
        echo "[WARNING] Nextcloud database container (nextcloud-aio-database) is not running. Skipping dump."
    fi
fi

echo "[OK] Database dumps completed."
