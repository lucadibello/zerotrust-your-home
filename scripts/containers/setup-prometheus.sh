#!/bin/bash

# Create prometheus network
docker network create prometheus-network || true
docker network create alertmanager-network || true
docker network create grafana-network || true

# Fix permissions for Prometheus (runs as nobody: 65534)
if [ -d "./composes/prometheus" ]; then
    chown -R 65534:65534 ./composes/prometheus
fi

