#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"

case "$PHASE" in
    pre-backup)
        if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
            echo "[*] Enabling Nextcloud Maintenance Mode..."
            docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --on
        fi
        ;;
    dump)
        echo "[*] Dumping Nextcloud database..."
        mkdir -p "$DUMP_DIR"
        if docker ps -q -f name=nextcloud-aio-database 2>/dev/null | grep -q .; then
            NC_USER=$(docker exec nextcloud-aio-database printenv POSTGRES_USER 2>/dev/null || true)
            NC_DB=$(docker exec nextcloud-aio-database printenv POSTGRES_DB 2>/dev/null || true)
            NC_PASS=$(docker exec nextcloud-aio-database printenv POSTGRES_PASSWORD 2>/dev/null || true)
            
            if [ -n "$NC_USER" ] && [ -n "$NC_DB" ] && [ -n "$NC_PASS" ]; then
                if docker exec -i -e PGPASSWORD="$NC_PASS" nextcloud-aio-database pg_dump -c -U "$NC_USER" "$NC_DB" | gzip > "$DUMP_DIR/nextcloud_db_dump.sql.gz"; then
                    echo "[OK] Nextcloud database dumped successfully."
                else
                    echo "[ERROR] Nextcloud database dump failed."
                    exit 1
                fi
            else
                echo "[ERROR] Could not retrieve Nextcloud credentials."
                exit 1
            fi
        fi
        ;;
    resume)
        if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
            echo "[*] Disabling Nextcloud Maintenance Mode..."
            docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off || true
        fi
        ;;
    pre-restore)
        ;;
    post-restore)
        if [ -n "${RESTORE_TARGET_PATH:-}" ] && [[ ! "$RESTORE_TARGET_PATH" == *"nextcloud"* ]] && [[ ! "$RESTORE_TARGET_PATH" == *"project"* ]]; then
            exit 0
        fi
        echo "[*] Restoring Nextcloud database..."
        if [ -f "$DUMP_DIR/nextcloud_db_dump.sql.gz" ] && docker ps -q -f name=nextcloud-aio-database 2>/dev/null | grep -q .; then
            NC_USER=$(docker exec nextcloud-aio-database printenv POSTGRES_USER 2>/dev/null || true)
            NC_DB=$(docker exec nextcloud-aio-database printenv POSTGRES_DB 2>/dev/null || true)
            NC_PASS=$(docker exec nextcloud-aio-database printenv POSTGRES_PASSWORD 2>/dev/null || true)
            
            zcat "$DUMP_DIR/nextcloud_db_dump.sql.gz" | docker exec -i -e PGPASSWORD="$NC_PASS" nextcloud-aio-database psql -U "$NC_USER" -d "$NC_DB"
            echo "[OK] Nextcloud database restored."
        fi
        if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
            echo "[*] Disabling Nextcloud Maintenance Mode and rescanning files..."
            docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off
            docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ files:scan --all
        fi
        ;;
esac
