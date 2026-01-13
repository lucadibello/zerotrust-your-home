#!/bin/bash
# Wrapper to run rclone config interactively using the official rclone image
# This ensures the configuration file is generated in the correct format and location

# Get absolute path to config directory
CONFIG_DIR="$(cd "$(dirname "$0")/../../config/rclone" && pwd)"

echo "[*] Starting Rclone configuration wizard..."
echo "[*] Config file location: $CONFIG_DIR/rclone.conf"
echo "[*] TIP: Since you are running this on a headless server, when asked:"
echo "     'Use web browser to automatically authenticate rclone with remote?'"
echo "     Select 'n' (No). Rclone will give you a command to run on your local machine."

docker run --rm -it \
  -v "$CONFIG_DIR":/config/rclone \
  rclone/rclone:latest config

echo "[*] Configuration finished."
