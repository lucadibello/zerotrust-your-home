#!/bin/bash

# Load .env file
set -a
source .env
set +a

cd composes

echo "[*] Running prune (Local)..."
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic -r /repos/local/restic forget --keep-last 5 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

echo "[*] Running prune (Cloud)..."
# Keep last 5 snapshots, 7 daily, 4 weekly, 12 monthly
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic forget --keep-last 5 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

PRUNE_EXIT_CODE=$?

if [ $PRUNE_EXIT_CODE -eq 0 ]; then
  echo "[OK] Prune completed successfully"
else
  echo "[ERROR] Prune failed with exit code $PRUNE_EXIT_CODE"
fi

cd ..
exit $PRUNE_EXIT_CODE
