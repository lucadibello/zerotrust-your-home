#!/bin/bash
trap "exit" INT
# setup.sh: Full system setup including OS configuration.
#
# Usage: ./setup.sh [options]
# Options:
#   -y, --yes, --headless    Run in headless mode (auto-confirm prompts)
#   --skip-os-setup          Skip OS setup (for re-running on existing instances)
#   --skip-config            Skip configuration tasks (only perform OS setup)
#   --skip-network           Skip network configuration
#   --skip-firewall          Skip firewall configuration
#   --security-only          Only run security hardening and firewall (for updates)
#   --no-reboot              Do not reboot after setup
#   -h, --help               Display this help message

# Default options
HEADLESS_MODE=false
SKIP_OS_SETUP=false
SKIP_CONFIG=false
SKIP_NETWORK=false
SKIP_FIREWALL=false
SECURITY_ONLY=false
REBOOT_AFTER_SETUP=true

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Full system setup including OS configuration."
  echo "Can be safely re-run on existing instances with appropriate options."
  echo ""
  echo "Options:"
  echo "  -y, --yes, --headless    Run in headless mode"
  echo "  --skip-os-setup          Skip OS setup (for re-running on existing instances)"
  echo "  --skip-config            Skip configuration tasks (only perform OS setup)"
  echo "  --skip-network           Skip network configuration"
  echo "  --skip-firewall          Skip firewall configuration"
  echo "  --security-only          Only run security hardening and firewall (for updates)"
  echo "  --no-reboot              Do not reboot after setup"
  echo "  -h, --help               Display this help message"
  echo ""
  echo "Examples:"
  echo "  $0                       # Full setup (first time installation)"
  echo "  $0 --skip-os-setup       # Re-run setup without OS changes"
  echo "  $0 --security-only       # Only update security posture"
  echo "  $0 -y --no-reboot        # Headless mode without reboot"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -y | --yes | --headless)
    HEADLESS_MODE=true
    ;;
  --skip-os-setup)
    SKIP_OS_SETUP=true
    ;;
  --skip-config)
    SKIP_CONFIG=true
    ;;
  --skip-network)
    SKIP_NETWORK=true
    ;;
  --skip-firewall)
    SKIP_FIREWALL=true
    ;;
  --security-only)
    SECURITY_ONLY=true
    SKIP_OS_SETUP=true
    SKIP_CONFIG=true
    SKIP_NETWORK=true
    REBOOT_AFTER_SETUP=false
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
if [ "$SKIP_OS_SETUP" = true ]; then
  echo "[*] Skipping OS setup as per user request."
else
  confirm "[!] This will configure your OS. Proceed with OS setup?"
  run_script "./scripts/os/setup-os.sh" "Operating system setup"
fi

# === Configuration Tasks ===
if [ "$SKIP_CONFIG" = false ]; then
  echo "[*] Proceeding with configuration tasks..."
  # Call the configuration task script (which can be re-run later independently)
  sudo bash ./scripts/generate.sh "$@"
else
  echo "[*] Skipping configuration tasks as per user request."
fi

# === Apply Network Settings ===
if [ "$SKIP_NETWORK" = true ]; then
  echo "[*] Skipping network configuration as per user request."
else
  echo "----------------------------------"
  echo "Network settings will be applied and may interrupt your SSH connection."
  echo "WARNING: Reboot is required to apply new network settings."
  echo "----------------------------------"
  confirm "[!] Apply network settings?"
  run_script "./scripts/os/setup-network.sh" "Applying network settings"
fi

# === Firewall Configuration ===
if [ "$SKIP_FIREWALL" = true ]; then
  echo "[*] Skipping firewall configuration as per user request."
else
  run_script "./scripts/firewall/zero-trust-firewall.sh" "Setting up Zero Trust firewall rules"
fi

# === System Hardening ===
run_script "./scripts/system-hardening/system-hardening.sh" "Hardening system"

echo "----------------------------------------------"
if [ "$SECURITY_ONLY" = true ]; then
  echo "----  Security update completed successfully ----"
else
  echo "----    OS setup completed successfully   ----"
fi
echo "----------------------------------------------"

if [ "$REBOOT_AFTER_SETUP" = true ]; then
  echo "[*] Rebooting system..."
  reboot
else
  if [ "$SECURITY_ONLY" = true ]; then
    echo "[*] Security update completed. Some changes may require a reboot to take full effect."
  else
    echo "[*] Setup completed. Reboot has been disabled. Please reboot manually if required."
  fi
fi
