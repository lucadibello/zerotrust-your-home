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
  echo "[*] ${description}..."
  sudo bash "$script_path"
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
