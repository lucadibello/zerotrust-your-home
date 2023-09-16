#!/bin/bash

# Create required directories (ignore if already exists)
mkdir -p ./composes/alertmanager ./.tmp/alertmanager || true

# Load environment variables
set -a
source .env
set +a

# Replace variables in configuration file
sed "s/<BOT_TOKEN>/$TELEGRAM_BOT_TOKEN/g" ./scripts/containers/templates/alertmanager.yml.template | tee ./.tmp/alertmanager/alertmanager.yml > /dev/null
sed -i "s/<CHAT_ID>/$TELEGRAM_CHAT_ID/g" ./.tmp/alertmanager/alertmanager.yml

# Move configuration file to composes directory
mv ./.tmp/alertmanager/alertmanager.yml ./composes/alertmanager/alertmanager.yml

# Remove temporary directory
rm -rf ./.tmp/alertmanager