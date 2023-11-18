#!/bin/bash

# Create custom network for Home Assistant and other dependant containers (ignore if already exists)
docker network create home-network || true