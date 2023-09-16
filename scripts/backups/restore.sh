#!/bin/bash

bash ./scripts/backups/view-backups.sh

# Ask user for backup ID
echo -n "Enter backup ID: "
read ID

# Stop all containers apart restic
cd composes
sudo docker-compose -f bind9.docker-compose.yaml -f traefik.docker-compose.yaml \
  -f prometheus.docker-compose.yaml \
  -f home.docker-compose.yaml \
  -f loki.docker-compose.yaml \
  -f uptimekuma.docker-compose.yaml \
  -f watchtower.docker-compose.yaml --env-file ../.env stop

# Restore backup
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic restore $ID -H docker --exclude backingFsBlockDev --target /

# Restart all containers
sudo docker-compose -f bind9.docker-compose.yaml -f traefik.docker-compose.yaml \
  -f prometheus.docker-compose.yaml \
  -f home.docker-compose.yaml \
  -f loki.docker-compose.yaml \
  -f uptimekuma.docker-compose.yaml \
  -f watchtower.docker-compose.yaml --env-file ../.env start

# Exit if restore failed
cd ..