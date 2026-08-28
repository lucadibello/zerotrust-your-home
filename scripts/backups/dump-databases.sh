#!/bin/bash

trap "exit" INT

# Load .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
elif [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
elif [ -f ../../.env ]; then
    set -a
    source ../../.env
    set +a
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

DUMP_DIR="$PROJECT_DIR/composes/backups/db-dumps"
mkdir -p "$DUMP_DIR"


echo "[*] Starting database dumps to $DUMP_DIR..."


# --- Immich Database Dump ---
if [ "$ENABLE_IMMICH" = "true" ]; then
    echo "[*] Dumping Immich database..."
    
    # Check if container is running
    if [ "$(docker ps -q -f name=immich_postgres)" ]; then
        docker exec -t immich_postgres pg_dump -c -U "${IMMICH_DB_USERNAME}" "${IMMICH_DB_DATABASE_NAME}" | gzip > "$DUMP_DIR/immich_db_dump.sql.gz"
        
        if [ $? -eq 0 ]; then
            echo "[OK] Immich database dumped successfully."
        else
            echo "[ERROR] Immich database dump failed."
        fi
    else
        echo "[WARNING] Immich database container (immich_postgres) is not running. Skipping dump."
    fi
fi

# Add other database dumps here in the future
# e.g. Vaultwarden, Nextcloud (if not AIO), Home Assistant (if MariaDB)

echo "[OK] Database dumps completed."
