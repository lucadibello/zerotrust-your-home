#!/bin/bash
trap "exit" INT

# Create loki network
sudo docker network create loki-network || true

echo "[OK] Loki setup completed"
