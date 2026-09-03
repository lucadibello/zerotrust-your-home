#!/bin/bash
set -o pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
if [ -f "$PROJECT_DIR/.env" ]; then
    load_env "$PROJECT_DIR/.env"
elif [ -f .env ]; then
    load_env .env
fi

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"

echo "------------------------------------------------"
echo "Database Restore"
echo "------------------------------------------------"
echo "1) Restore from current files on host (Latest dump)"
echo "2) Restore from a specific Restic Snapshot (Time travel)"
echo -n "Select option [1]: "
read DB_SOURCE_OPT

DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"
TMP_RESTORE_DIR=""

if [ "$DB_SOURCE_OPT" = "2" ]; then
    echo "-------------------------------------------"
    echo "Select Restic Source:"
    echo "1) Local Disk (Recommended - Fast)"
    echo "2) Cloud Storage"
    echo -n "Select option [1]: "
    read RESTIC_SOURCE_OPT
    
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

    REPO_ARGS=""
    if [ "$RESTIC_SOURCE_OPT" = "1" ] || [ -z "$RESTIC_SOURCE_OPT" ]; then
        LOCAL_REPO="/repos/local/restic"
        if docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
          exec -T backup test -f /repos/local/config 2>/dev/null; then
            LOCAL_REPO="/repos/local"
        fi
        REPO_ARGS="-r $LOCAL_REPO"
    fi

    echo "[*] Fetching snapshots..."
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
        exec backup restic $REPO_ARGS snapshots -H docker
    
    echo -n "Enter backup ID to extract databases from: "
    read ID
    
    if [ -z "$ID" ]; then
        echo "No ID entered. Aborting."
        exit 1
    fi
    
    TMP_RESTORE_DIR=$(mktemp -d)
    echo "[*] Extracting database dumps from snapshot $ID to temporary directory..."
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" \
        exec backup restic $REPO_ARGS restore $ID --include /mnt/backup/project/composes/backup/db-dumps --target /tmp/restic-db-restore
        
    # Copy from the container's tmp to host's tmp (if running natively, it's the same, but wait, restic runs in container)
    # Actually, if we restore to /tmp/restic-db-restore INSIDE the container, we can't easily read it from the host script!
    # Let's restore to a mapped host volume. /mnt/backup/project/composes/backup/tmp-restore
    
    # Let's redefine TMP_RESTORE_DIR to be inside the project folder so it's accessible to both host and container
    TMP_RESTORE_DIR="$PROJECT_DIR/composes/backup/tmp-restore"
    mkdir -p "$TMP_RESTORE_DIR"
    
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" -f "$PROJECT_DIR/composes/backup/docker-compose.restore.yaml" --env-file "$PROJECT_DIR/.env" \
        exec backup restic $REPO_ARGS restore $ID --include /mnt/backup/project/composes/backup/db-dumps --target /mnt/backup/project/composes/backup/tmp-restore
        
    DUMP_DIR="$TMP_RESTORE_DIR/mnt/backup/project/composes/backup/db-dumps"
fi

if [ ! -d "$DUMP_DIR" ] || [ -z "$(ls -A "$DUMP_DIR" 2>/dev/null)" ]; then
    echo "Error: Database dump directory not found or empty ($DUMP_DIR)."
    if [ -n "$TMP_RESTORE_DIR" ]; then rm -rf "$TMP_RESTORE_DIR"; fi
    exit 1
fi

echo ""
echo "Location: $DUMP_DIR"
echo "Available Dumps:"
files=("$DUMP_DIR"/*.sql.gz)
if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
    echo "  No dump files found."
    if [ -n "$TMP_RESTORE_DIR" ]; then rm -rf "$TMP_RESTORE_DIR"; fi
    exit 1
fi

i=1
for file in "${files[@]}"; do
    echo "  [$i] $(basename "$file")"
    i=$((i+1))
done
echo ""
echo -n "Select file number to restore: "
read FILE_NUM

if [[ ! "$FILE_NUM" =~ ^[0-9]+$ ]] || [ "$FILE_NUM" -lt 1 ] || [ "$FILE_NUM" -gt ${#files[@]} ]; then
    echo "Invalid selection."
    if [ -n "$TMP_RESTORE_DIR" ]; then rm -rf "$TMP_RESTORE_DIR"; fi
    exit 1
fi

SELECTED_FILE="${files[$((FILE_NUM-1))]}"
FILENAME=$(basename "$SELECTED_FILE")
echo "Selected: $FILENAME"

# Suggest container name
SUGGESTED_CONTAINER=""
if [[ "$FILENAME" == *"immich"* ]]; then
    SUGGESTED_CONTAINER="immich_postgres"
elif [[ "$FILENAME" == *"nextcloud"* ]]; then
    SUGGESTED_CONTAINER="nextcloud-aio-database"
fi

echo -n "Enter target Docker container name"
if [ -n "$SUGGESTED_CONTAINER" ]; then
    echo -n " [default: $SUGGESTED_CONTAINER]"
fi
echo -n ": "
read CONTAINER_NAME

if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME="$SUGGESTED_CONTAINER"
fi

if [ -z "$CONTAINER_NAME" ]; then
    echo "Error: Container name is required."
    if [ -n "$TMP_RESTORE_DIR" ]; then rm -rf "$TMP_RESTORE_DIR"; fi
    exit 1
fi

DB_USER=""
DB_NAME=""
DB_PASS_ENV=""
if [[ "$CONTAINER_NAME" == "immich_postgres" ]]; then
    DB_USER="${IMMICH_DB_USERNAME:-postgres}"
    DB_NAME="${IMMICH_DB_DATABASE_NAME:-immich}"
elif [[ "$CONTAINER_NAME" == "nextcloud-aio-database" ]]; then
    if docker ps -q -f name=nextcloud-aio-database 2>/dev/null | grep -q .; then
        DB_USER=$(docker exec nextcloud-aio-database printenv POSTGRES_USER 2>/dev/null)
        DB_NAME=$(docker exec nextcloud-aio-database printenv POSTGRES_DB 2>/dev/null)
        DB_PASS=$(docker exec nextcloud-aio-database printenv POSTGRES_PASSWORD 2>/dev/null)
        if [ -n "$DB_PASS" ]; then
            DB_PASS_ENV="-e PGPASSWORD=$DB_PASS"
        fi
    fi
fi

echo -n "Enter DB User for psql (optional"
if [ -n "$DB_USER" ]; then
    echo -n ", default: $DB_USER"
fi
echo -n "): "
read INPUT_USER
if [ -n "$INPUT_USER" ]; then DB_USER="$INPUT_USER"; fi

echo -n "Enter DB Name for psql (optional"
if [ -n "$DB_NAME" ]; then
    echo -n ", default: $DB_NAME"
fi
echo -n "): "
read INPUT_DBNAME
if [ -n "$INPUT_DBNAME" ]; then DB_NAME="$INPUT_DBNAME"; fi

CMD="docker exec -i $DB_PASS_ENV $CONTAINER_NAME psql"
if [ -n "$DB_USER" ]; then CMD="$CMD -U $DB_USER"; fi
if [ -n "$DB_NAME" ]; then CMD="$CMD -d $DB_NAME"; fi

echo "[*] Restoring $FILENAME to container $CONTAINER_NAME..."

confirm() {
    read -p "$1 [y/N]: " response
    if [[ "$response" =~ ^[yY]$ ]]; then return 0; else return 1; fi
}

if confirm "Are you sure? This may overwrite existing database data."; then
    gzip -dc "$SELECTED_FILE" | eval "$CMD"
    if [ $? -eq 0 ]; then
        echo "[OK] Database restore completed."
    else
        echo "[ERROR] Database restore failed."
    fi
else
    echo "Aborted."
fi

if [ -n "$TMP_RESTORE_DIR" ]; then 
    echo "[*] Cleaning up temporary extracted files..."
    rm -rf "$TMP_RESTORE_DIR"
fi
