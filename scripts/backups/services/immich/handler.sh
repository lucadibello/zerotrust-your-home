#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

DUMP_DIR="$PROJECT_DIR/composes/backup/db-dumps"

IMMICH_GO_VERSION="v0.32.0"
IMMICH_GO_BIN="$PROJECT_DIR/scripts/backups/services/immich/bin/immich-go"

download_immich_go() {
    mkdir -p "$(dirname "$IMMICH_GO_BIN")"
    if [ ! -x "$IMMICH_GO_BIN" ] || ! "$IMMICH_GO_BIN" --version 2>&1 | grep -q "${IMMICH_GO_VERSION#v}"; then
        echo "[*] Downloading immich-go $IMMICH_GO_VERSION..."
        ARCH="$(uname -m)"
        case "$ARCH" in
            x86_64) GO_ARCH="Linux_x86_64" ;;
            aarch64|arm64) GO_ARCH="Linux_arm64" ;;
            armv7l|armhf) GO_ARCH="Linux_armv7" ;;
            *) GO_ARCH="Linux_x86_64" ;;
        esac
        # Download in alpine container or using curl directly if available
        docker run --rm -v "$(dirname "$IMMICH_GO_BIN"):/workspace" alpine sh -c "
            apk add --no-cache curl tar gzip && \
            curl -fsSL https://github.com/simulot/immich-go/releases/download/${IMMICH_GO_VERSION}/immich-go_${GO_ARCH}.tar.gz | tar -xz -C /workspace && \
            chmod +x /workspace/immich-go
        "
    fi
}

case "$PHASE" in
    pre-backup)
        # Nothing specific needed before backup for immich
        ;;
    dump)
        echo "[*] Dumping Immich database..."
        mkdir -p "$DUMP_DIR"
        if docker ps -q -f name=immich_postgres 2>/dev/null | grep -q .; then
            if docker exec -i immich_postgres pg_dump -c -U "${IMMICH_DB_USERNAME:-postgres}" "${IMMICH_DB_DATABASE_NAME:-immich}" | gzip > "$DUMP_DIR/immich_db_dump.sql.gz"; then
                echo "[OK] Immich database dumped successfully."
            else
                echo "[ERROR] Immich database dump failed."
                exit 1
            fi
        else
            echo "[WARNING] Immich database container (immich_postgres) is not running. Skipping dump."
        fi

        # Photo export
        if [ -z "${IMMICH_API_KEY:-}" ] || [ "$IMMICH_API_KEY" = "your-api-key" ]; then
            echo "[WARNING] IMMICH_API_KEY is not set. Skipping photo export."
            exit 0
        fi

        download_immich_go
        
        BACKUP_DIR="${IMMICH_BACKUP_LOCATION:-/mnt/nextcloud-backups/immich}"
        DAY_OF_MONTH=$(date '+%d')
        TODAY=$(date '+%Y-%m-%d')
        YESTERDAY=$(date -d '1 day ago' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
        
        FORCE_FULL=${FORCE_FULL:-false}
        if [ "$FORCE_FULL" = "true" ] || [ "$DAY_OF_MONTH" = "01" ]; then
            SUB_DIR="full/$(date +%Y-%m)"
            ARGS=""
        else
            SUB_DIR="incremental/$TODAY"
            ARGS="--from-date-range=$YESTERDAY,$TODAY"
        fi
        
        mkdir -p "$BACKUP_DIR"
        
        if [ -z "$(docker ps -q -f name=immich_server 2>/dev/null)" ]; then
            echo "[ERROR] Immich server is not running. Skipping export."
            exit 1
        fi
        
        IMMICH_LOG_DIR="/var/log/immich-go"
        mkdir -p "$IMMICH_LOG_DIR" 2>/dev/null || true
        
        docker run --rm \
            --network immich-network \
            -v "$BACKUP_DIR":/backup \
            -v "$IMMICH_LOG_DIR":/root/.cache/immich-go \
            -v "$IMMICH_GO_BIN":/usr/local/bin/immich-go:ro \
            alpine:latest \
            /bin/sh -c "
                /usr/local/bin/immich-go archive from-immich \
                --from-server=http://immich_server:2283 \
                --from-api-key='${IMMICH_API_KEY}' \
                --write-to-folder='/backup/${SUB_DIR}' \
                $ARGS
            "
        IMMICH_EXIT=$?
        
        LATEST_LOG=$(ls -t "$IMMICH_LOG_DIR"/immich-go_*.log 2>/dev/null | head -1 || true)
        if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
            if grep -qE "ERR |level=error|Unauthorized|Invalid credentials|connection refused|failed to connect" "$LATEST_LOG" 2>/dev/null; then
                echo "[ERROR] Immich backup failed according to log $LATEST_LOG."
                exit 1
            fi
        fi
        
        if [ $IMMICH_EXIT -ne 0 ]; then
            echo "[ERROR] immich-go exit code $IMMICH_EXIT"
            exit 1
        fi
        ;;
    resume)
        ;;
    pre-restore)
        ;;
    post-restore)
        if [ -n "${RESTORE_TARGET_PATH:-}" ] && [[ ! "$RESTORE_TARGET_PATH" == *"immich"* ]] && [[ ! "$RESTORE_TARGET_PATH" == *"project"* ]]; then
            exit 0
        fi
        echo "[*] Restoring Immich database..."
        if [ -f "$DUMP_DIR/immich_db_dump.sql.gz" ] && docker ps -q -f name=immich_postgres 2>/dev/null | grep -q .; then
            zcat "$DUMP_DIR/immich_db_dump.sql.gz" | docker exec -i immich_postgres psql -U "${IMMICH_DB_USERNAME:-postgres}" -d "${IMMICH_DB_DATABASE_NAME:-immich}"
            echo "[OK] Immich database restored."
        fi
        ;;
esac
