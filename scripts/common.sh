#!/bin/bash
# common.sh: Shared functions for confirmation and script execution

# Use HEADLESS_MODE if exported by caller (default is false)
HEADLESS_MODE=${HEADLESS_MODE:-false}

# confirm: Prompts the user for confirmation unless running in headless mode.
confirm() {
  local message="$1"
  if [ "$HEADLESS_MODE" = true ]; then
    echo "[*] $message (auto-confirmed)"
  else
    read -p "$message (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "[!] Aborting..."
      exit 1
    fi
  fi
}

# run_script: Executes a script and aborts if an error occurs.
run_script() {
  local script_path="$1"
  local description="$2"
  shift 2 2>/dev/null || true
  echo "[*] ${description}..."
  sudo bash "$script_path" "$@"
  if [ $? -ne 0 ]; then
    echo "[!] Error occurred during ${description}. Aborting..."
    exit 1
  fi
  echo "[OK] ${description} completed successfully"
}


# Define a portable in‐place sed command
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE="sed -i ''"
else
  SED_INPLACE="sed -i"
fi

# Detect virtualization environment (e.g. qemu, kvm, proxmox, none)
detect_virtualization() {
  local virt="none"
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
  fi
  if [ "$virt" = "none" ] || [ -z "$virt" ]; then
    if [ -f /sys/class/dmi/id/sys_vendor ] && grep -qiE "qemu|kvm|proxmox|bochs" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
      virt="kvm"
    elif [ -f /sys/class/dmi/id/product_name ] && grep -qiE "qemu|kvm|proxmox|virtual" /sys/class/dmi/id/product_name 2>/dev/null; then
      virt="kvm"
    fi
  fi
  echo "$virt"
}

# Detect Linux distribution family for package repository matching (debian or ubuntu)
detect_linux_distro() {
  local distro="debian"
  if [ -f /etc/os-release ]; then
    # Parse in subshell to avoid polluting caller env
    distro=$(
      . /etc/os-release
      if [ "${ID:-}" = "ubuntu" ] || [[ "${ID_LIKE:-}" =~ "ubuntu" ]]; then
        echo "ubuntu"
      else
        echo "debian"
      fi
    )
  fi
  echo "$distro"
}

# Detect primary non-loopback network interface
get_default_network_interface() {
  local iface=""
  if command -v ip >/dev/null 2>&1; then
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
    if [ -z "$iface" ]; then
      iface=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE 'lo|docker|br-|veth|tailscale|wg' | head -n1)
    fi
  fi
  if [ -z "$iface" ] && command -v nmcli >/dev/null 2>&1; then
    iface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep -w "ethernet$" | head -n1 | cut -d: -f1)
  fi
  echo "$iface"
}

