#!/bin/bash
cd composes

sudo docker-compose \
		-f traefik.docker-compose.yaml \
		-f prometheus.docker-compose.yaml \
		-f home.docker-compose.yaml \
		-f loki.docker-compose.yaml \
		-f tunnel.docker-compose.yaml \
		-f uptimekuma.docker-compose.yaml \
		-f watchtower.docker-compose.yaml \
		-f restic.docker-compose.yaml \
		--env-file ../.env \
    logs -f --tail=1000

cd ..