#!/bin/bash
trap "exit" INT

# update-security.sh: Update security posture on existing instances
# This script applies the latest hardening and firewall settings without
# requiring a full system setup or reboot.
#
# Usage: ./scripts/update-security.sh [options]
# Options:
#   -y, --yes         Run without confirmation prompts
#   --force-update    Force refresh of external resources (e.g., audit rules)
#   --firewall-only   Only update firewall rules
#   --hardening-only  Only run system hardening
#   -h, --help        Display this help message

set -e

# Default options
AUTO_CONFIRM=false
FORCE_UPDATE=""
FIREWALL_ONLY=false
HARDENING_ONLY=false

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Update security posture on existing instances."
  echo "This script applies the latest hardening and firewall settings."
  echo ""
  echo "Options:"
  echo "  -y, --yes         Run without confirmation prompts"
  echo "  --force-update    Force refresh of external resources (e.g., audit rules)"
  echo "  --firewall-only   Only update firewall rules"
  echo "  --hardening-only  Only run system hardening"
  echo "  -h, --help        Display this help message"
  echo ""
  echo "Examples:"
  echo "  $0                  # Run interactively"
  echo "  $0 -y               # Run without prompts"
  echo "  $0 --firewall-only  # Only update firewall"
  echo "  $0 --force-update   # Force refresh audit rules"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -y | --yes)
    AUTO_CONFIRM=true
    ;;
  --force-update)
    FORCE_UPDATE="--force-update"
    ;;
  --firewall-only)
    FIREWALL_ONLY=true
    ;;
  --hardening-only)
    HARDENING_ONLY=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo -e "${RED}[!] Unknown option: $1${NC}"
    usage
    exit 1
    ;;
  esac
  shift
done

# Validate mutually exclusive options
if [ "$FIREWALL_ONLY" = true ] && [ "$HARDENING_ONLY" = true ]; then
  echo -e "${RED}[!] Cannot use --firewall-only and --hardening-only together${NC}"
  exit 1
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

# Check if .env file exists
if [ ! -f .env ]; then
  echo -e "${RED}[!] .env file not found. Please run from project root or create .env file.${NC}"
  exit 1
fi

# Load .env file
set -a
source .env
set +a

echo "=============================================="
echo "       Security Update Script                 "
echo "=============================================="
echo ""
echo "This script will update the security settings"
echo "on your existing system installation."
echo ""

if [ "$FIREWALL_ONLY" = true ]; then
  echo "Mode: Firewall rules only"
elif [ "$HARDENING_ONLY" = true ]; then
  echo "Mode: System hardening only"
else
  echo "Mode: Full security update (hardening + firewall)"
fi

if [ -n "$FORCE_UPDATE" ]; then
  echo "Option: Force refresh external resources"
fi

echo ""

# Confirmation prompt
if [ "$AUTO_CONFIRM" != true ]; then
  echo -e "${YELLOW}[!] This will modify system security settings.${NC}"
  read -p "Do you wish to continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting..."
    exit 0
  fi
fi

echo ""

# Export variables for child scripts
export HEADLESS_MODE=true

# Run system hardening
if [ "$FIREWALL_ONLY" != true ]; then
  echo -e "${GREEN}[*] Running system hardening...${NC}"
  echo ""

  if [ -f "$SCRIPT_DIR/system-hardening/system-hardening.sh" ]; then
    sudo bash "$SCRIPT_DIR/system-hardening/system-hardening.sh" $FORCE_UPDATE
  else
    echo -e "${RED}[!] system-hardening.sh not found${NC}"
    exit 1
  fi

  echo ""
fi

# Run firewall configuration
if [ "$HARDENING_ONLY" != true ]; then
  echo -e "${GREEN}[*] Updating firewall rules...${NC}"
  echo ""

  if [ -f "$SCRIPT_DIR/firewall/zero-trust-firewall.sh" ]; then
    sudo bash "$SCRIPT_DIR/firewall/zero-trust-firewall.sh" --yes
  else
    echo -e "${RED}[!] zero-trust-firewall.sh not found${NC}"
    exit 1
  fi

  echo ""
fi

echo "=============================================="
echo "       Security Update Complete!              "
echo "=============================================="
echo ""
echo "Your system security settings have been updated."
echo ""

if [ "$HARDENING_ONLY" != true ]; then
  echo "Firewall rules have been saved and will persist across reboots."
fi

if [ "$FIREWALL_ONLY" != true ]; then
  echo "Some hardening changes may require a reboot to take full effect."
fi

echo ""
echo "To verify the changes:"
echo "  - Check firewall rules: sudo iptables -L -n"
echo "  - Check audit rules: sudo auditctl -l"
echo "  - Check sysctl settings: sudo sysctl -a | grep -E 'kernel\.(dmesg|sysrq)|net\.ipv4'"
