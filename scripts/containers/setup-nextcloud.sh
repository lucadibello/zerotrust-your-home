#!/bin/bash

# Create nextcloud volume
sudo docker volume create nextcloud_aio_mastercontainer || true

# Create network for nextcloud
sudo docker network create nextcloud-aio || true