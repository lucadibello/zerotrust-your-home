#!/bin/bash

# Load .env
set -a
source .env
set +a

# Skip if Nextcloud is not enabled
if [ "$ENABLE_NEXTCLOUD" != "true" ]; then
  echo "[*] Nextcloud is disabled, skipping setup..."
  exit 0
fi

# Create nextcloud volume
sudo docker volume create nextcloud_aio_mastercontainer || true

# Create network for nextcloud
sudo docker network create nextcloud-aio || true

# Create configuration file for traefik using the template
sed "s/<DOMAIN>/$DNS_DOMAIN/g" ./scripts/containers/templates/nextcloud.yml.template | tee ./composes/traefik/nextcloud.yml >/dev/null
