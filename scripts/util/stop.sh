#!/bin/bash
cd composes

# Stop all services
sudo docker-compose \
  -f bind9.docker-compose.yaml \
  -f traefik.docker-compose.yaml \
  -f prometheus.docker-compose.yaml \
  -f home.docker-compose.yaml \
  -f loki.docker-compose.yaml \
  -f uptimekuma.docker-compose.yaml \
  -f watchtower.docker-compose.yaml \
  -f restic.docker-compose.yaml \
  --env-file ../.env \
  stop --remove-orphans

cd ..