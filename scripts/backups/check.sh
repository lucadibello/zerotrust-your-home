#!/bin/bash

# Load .env file
set -a
source .env
set +a

cd composes

echo "[*] Running integrity check (10% of data)..."
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic check --read-data-subset=10%

CHECK_EXIT_CODE=$?

if [ $CHECK_EXIT_CODE -eq 0 ]; then
  echo "[OK] Check completed successfully"
else
  echo "[ERROR] Check failed with exit code $CHECK_EXIT_CODE"
fi

cd ..
exit $CHECK_EXIT_CODE
