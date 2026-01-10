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
else
    echo "Error: .env file not found."
    exit 1
fi

DUMP_DIR="./composes/backups/db-dumps"

if [ ! -d "$DUMP_DIR" ]; then
    echo "Error: Database dump directory $DUMP_DIR not found."
    exit 1
fi

echo "------------------------------------------------"
echo "Database Restore"
echo "------------------------------------------------"
echo "Location: $DUMP_DIR"
echo ""
echo "Available Dumps:"
files=("$DUMP_DIR"/*.sql.gz)
if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
    echo "  No dump files found."
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
    SUGGESTED_CONTAINER="nextcloud-aio-database" # Example
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
    exit 1
fi

# Ask for DB user/name if needed?
# Usually pg_dump -c includes the drop/create commands, but psql needs a user to connect.
# We'll assume the dump includes ownership or we use the root user of the DB.
# For postgres, -U is usually required.

DB_USER=""
if [[ "$CONTAINER_NAME" == "immich_postgres" ]]; then
    DB_USER="$IMMICH_DB_USERNAME"
fi

echo -n "Enter DB User for psql (optional"
if [ -n "$DB_USER" ]; then
    echo -n ", default: $DB_USER"
fi
echo -n "): "
read INPUT_USER

if [ -n "$INPUT_USER" ]; then
    DB_USER="$INPUT_USER"
fi

CMD="docker exec -i $CONTAINER_NAME psql"
if [ -n "$DB_USER" ]; then
    CMD="$CMD -U $DB_USER"
fi
# Note: we don't specify dbname because pg_dump -c usually creates/connects, 
# BUT pg_dump output often assumes it's being piped into a connection to 'postgres' or the target DB.
# If the dump relies on \c command it might fail if not connected initially.
# Safest is usually connecting to 'template1' or 'postgres'.

echo "[*] Restoring $FILENAME to container $CONTAINER_NAME..."
echo "[*] Command: zcat $SELECTED_FILE | $CMD"

confirm() {
    read -p "$1 [y/N]: " response
    if [[ "$response" =~ ^[yY]$ ]]; then
        return 0
    else
        return 1
    fi
}

if confirm "Are you sure? This may overwrite existing data."; then
    zcat "$SELECTED_FILE" | $CMD
    if [ $? -eq 0 ]; then
        echo "[OK] Database restore completed."
    else
        echo "[ERROR] Database restore failed."
        exit 1
    fi
else
    echo "Aborted."
    exit 0
fi
