#!/bin/bash
# Wrapper to run rclone config interactively using the official rclone image
# This ensures the configuration file is generated in the correct format and location

# Get absolute path to project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config/rclone"

# Create the config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
    echo "[*] Creating config directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
fi

echo "[*] Starting Rclone configuration wizard..."
echo "[*] Config file location: $CONFIG_DIR/rclone.conf"
echo "[*] TIPS FOR GOOGLE DRIVE SETUP:"
echo "     1. Remote Name: Use the name matching RESTIC_REPOSITORY in your .env (e.g. 'gdrive')"
echo "     2. Storage Type: Select 'drive' (Google Drive)"
echo "     3. Headless Authentication: When asked:"
echo "        'Use web browser to automatically authenticate rclone with remote?'"
echo "        Select 'n' (No). Rclone will provide a command to run on your local machine (rclone authorize 'drive' ...)"
echo "        Paste the resulting auth token back here."
echo ""

docker run --rm -it \
  -v "$CONFIG_DIR":/config/rclone \
  rclone/rclone:latest config

echo "[*] Configuration finished."
echo "[*] Your rclone.conf is stored at: $CONFIG_DIR/rclone.conf"
