#!/bin/bash

# Create prometheus network
docker network create prometheus-network || true
docker network create alertmanager-network || true
docker network create grafana-network || true

