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

# render_template: Safely renders a template file to a target destination.
# Replaces <KEY> placeholders using explicit KEY=VALUE arguments, falling back to environment variables.
# Handles special characters (slashes, quotes, ampersands, newlines) safely.
# Automatically creates the destination directory and performs atomic file writes.
#
# Usage: render_template <template_file> <output_file> [KEY=VALUE ...]
render_template() {
  local template_path="$1"
  local output_path="$2"
  shift 2 || true

  if [ ! -f "$template_path" ]; then
    echo "[!] Error: Template file not found: $template_path"
    return 1
  fi

  local target_dir
  target_dir="$(dirname "$output_path")"
  mkdir -p "$target_dir"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$template_path" "$output_path" "$@" <<'EOF'
import sys
import os
import re

template_file = sys.argv[1]
output_file = sys.argv[2]
explicit_args = sys.argv[3:]

replacements = {}
for arg in explicit_args:
    if '=' in arg:
        k, v = arg.split('=', 1)
        replacements[k] = v

with open(template_file, 'r', encoding='utf-8') as f:
    content = f.read()

def replacer(match):
    key = match.group(1)
    if key in replacements:
        return str(replacements[key])
    if key in os.environ:
        return str(os.environ[key])
    return match.group(0)

rendered = re.sub(r'<([A-Za-z0-9_]+)>', replacer, content)

tmp_file = output_file + '.tmp'
with open(tmp_file, 'w', encoding='utf-8') as f:
    f.write(rendered)

os.replace(tmp_file, output_file)
EOF
  else
    # Fallback using portable temporary file and sed escaping
    local tmp_file="${output_path}.tmp"
    cp "$template_path" "$tmp_file"
    for pair in "$@"; do
      local k="${pair%%=*}"
      local v="${pair#*=}"
      local safe_v
      safe_v=$(printf '%s\n' "$v" | sed -e 's/[\/&]/\\&/g')
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/<$k>/$safe_v/g" "$tmp_file"
      else
        sed -i "s/<$k>/$safe_v/g" "$tmp_file"
      fi
    done
    mv "$tmp_file" "$output_path"
  fi
}

# load_env: Loads key-value pairs from .env without overriding variables already set in environment
load_env() {
  local env_file="${1:-.env}"
  if [ -f "$env_file" ]; then
    local dq_re='^"(([^"\\]|\\.)*)"'
    local sq_re="^'([^']*)'"
    while IFS= read -r line || [ -n "$line" ]; do
      # Remove leading whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      # Skip comments and empty lines
      [[ "$line" =~ ^# ]] && continue
      [[ -z "$line" ]] && continue
      # Strip optional export prefix
      if [[ "$line" =~ ^export[[:space:]]+ ]]; then
        line="${line#export }"
        line="${line#"${line%%[![:space:]]*}"}"
      fi
      # Check if line contains =
      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        # Strip leading whitespace from val
        val="${val#"${val%%[![:space:]]*}"}"
        if [[ "$val" =~ $dq_re ]]; then
          val="${BASH_REMATCH[1]}"
        elif [[ "$val" =~ $sq_re ]]; then
          val="${BASH_REMATCH[1]}"
        else
          # Strip trailing comments (starting with #)
          val="${val%%#*}"
          # Strip trailing whitespace
          val="${val%"${val##*[![:space:]]}"}"
        fi
        # Only set if not already set in environment
        if [ -z "${!key+x}" ]; then
          export "$key"="$val"
        fi
      fi
    done < "$env_file"
  fi
}

# send_ntfy: Sends a push notification to ntfy if NTFY_TOPIC is configured
send_ntfy() {
  local title="$1"
  local message="$2"
  local tags="${3:-floppy_disk}"
  local priority="${4:-default}"
  
  if [ -n "${NTFY_TOPIC:-}" ]; then
    local ntfy_base="${NTFY_URL:-https://ntfy.home.lucadibello.ch}"
    ntfy_base="${ntfy_base%/}"
    local ntfy_endpoint="${ntfy_base}/${NTFY_TOPIC}"
    local auth_header=()
    if [ -n "${NTFY_TOKEN:-}" ]; then
      auth_header=(-H "Authorization: Bearer ${NTFY_TOKEN}")
    fi
    curl -s -H "Title: ${title}" -H "Tags: ${tags}" -H "Priority: ${priority}" "${auth_header[@]}" -d "${message}" "${ntfy_endpoint}" >/dev/null 2>&1 || true
  fi
}
