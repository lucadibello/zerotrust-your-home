#!/bin/bash
trap "exit" INT

# Create loki network
sudo docker network create loki-network || true