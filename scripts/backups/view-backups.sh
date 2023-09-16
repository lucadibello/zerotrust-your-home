#!/bin/bash
cd composes
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env exec backup restic snapshots -H docker
cd ..