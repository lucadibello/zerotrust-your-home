#!/bin/bash
trap "exit" INT

# Create prometheus network
docker network create prometheus-network || true
docker network create alertmanager-network || true
docker network create grafana-network || true


