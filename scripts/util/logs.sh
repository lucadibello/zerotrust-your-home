#!/bin/bash
cd composes

sudo docker-compose \
	-f dns.docker-compose.yaml \
	-f loki.docker-compose.yaml \
	-f nextcloud.docker-compose.yaml \
	-f prometheus.docker-compose.yaml \
	-f restic.docker-compose.yaml \
	-f traefik.docker-compose.yaml \
	-f tunnel.docker-compose.yaml \
	-f uptimekuma.docker-compose.yaml \
	-f vaultwarden.docker-compose.yaml \
	-f watchtower.docker-compose.yaml \
	-f website.docker-compose.yaml \
	--env-file ../.env \
	logs -f --tail=50

cd ..
