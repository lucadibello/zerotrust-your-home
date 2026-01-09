#!/bin/bash

# Create loki network
sudo docker network create loki-network || true

# Fix permissions for Loki (runs as 10001)
if [ -d "./composes/loki" ]; then
    chown -R 10001:10001 ./composes/loki
fi