#!/bin/bash
cd composes

# Stop all containers apart restic
sudo docker-compose -f bind9.docker-compose.yaml -f traefik.docker-compose.yaml \
  -f prometheus.docker-compose.yaml \
  -f home.docker-compose.yaml \
  -f loki.docker-compose.yaml \
  -f uptimekuma.docker-compose.yaml \
  -f watchtower.docker-compose.yaml --env-file ../.env stop

# Execute backup
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic backup /mnt/backup --host docker --tag backup

# Restart all containers
sudo docker-compose -f bind9.docker-compose.yaml -f traefik.docker-compose.yaml \
  -f prometheus.docker-compose.yaml \
  -f home.docker-compose.yaml \
  -f loki.docker-compose.yaml \
  -f uptimekuma.docker-compose.yaml \
  -f watchtower.docker-compose.yaml --env-file ../.env start

# Exit
cd ..