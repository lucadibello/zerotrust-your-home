#!/bin/bash
# setup.sh: Full system setup including OS configuration.
#
# Usage: ./setup.sh [options]
# Options:
#   -y, --yes, --headless    Run in headless mode (auto-confirm prompts)
#   --skip-config            Skip configuration tasks (only perform OS setup)
#   --no-reboot              Do not reboot after setup
#   -h, --help               Display this help message

# Default options
HEADLESS_MODE=false
SKIP_CONFIG=false
REBOOT_AFTER_SETUP=true

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -y, --yes, --headless    Run in headless mode"
  echo "  --skip-config            Skip configuration tasks (only perform OS setup)"
  echo "  --no-reboot              Do not reboot after setup"
  echo "  -h, --help               Display this help message"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -y | --yes | --headless)
    HEADLESS_MODE=true
    ;;
  --skip-config)
    SKIP_CONFIG=true
    ;;
  --no-reboot)
    REBOOT_AFTER_SETUP=false
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# Export HEADLESS_MODE for use by other scripts
export HEADLESS_MODE

# Source common functions
source ./scripts/common.sh

# Check if .env file exists
if [ ! -f .env ]; then
  echo "[!] .env file not found. Please create one by copying .env.example and filling in the required variables."
  exit 1
fi

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root"
  exit 1
fi

# === OS Setup (only run once) ===
confirm "[!] This will configure your OS. Proceed with OS setup?"
run_script "./scripts/os/setup-os.sh" "Operating system setup"

# === Configuration Tasks ===
if [ "$SKIP_CONFIG" = false ]; then
  echo "[*] Proceeding with configuration tasks..."
  # Call the configuration task script (which can be re-run later independently)
  sudo bash ./regenerate-config.sh "$@"
else
  echo "[*] Skipping configuration tasks as per user request."
fi

# === Apply Network Settings ===
echo "----------------------------------"
echo "Network settings will be applied and may interrupt your SSH connection."
echo "WARNING: Reboot is required to apply new network settings."
echo "----------------------------------"
confirm "[!] Apply network settings?"
run_script "./scripts/armbian/setup-network.sh" "Applying network settings"

# === Firewall Configuration ===
if [ "$SKIP_FIREWALL" = true ]; then
  echo "[*] Skipping firewall configuration as per user request."
else
  run_script "./scripts/firewall/zero-trust-firewall.sh" "Setting up Zero Trust firewall rules"
fi

# === System Hardening ===
run_script "./scripts/system-hardening/system-hardening.sh" "Hardening system"

echo "----------------------------------------------"
echo "----    OS setup completed successfully   ----"
echo "----------------------------------------------"

if [ "$REBOOT_AFTER_SETUP" = true ]; then
  echo "[*] Rebooting system..."
  reboot
else
  echo "[*] Setup completed. Reboot has been disabled. Please reboot manually if required."
fi
