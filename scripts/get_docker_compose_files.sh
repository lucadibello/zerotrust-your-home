#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-}"

if [ -z "$ENV_FILE" ]; then
  if [ -f "$PROJECT_DIR/.env" ]; then
    ENV_FILE="$PROJECT_DIR/.env"
  elif [ -f .env ]; then
    ENV_FILE=".env"
  fi
fi

if [ -f "$SCRIPT_DIR/common.sh" ]; then
  source "$SCRIPT_DIR/common.sh"
  if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    load_env "$ENV_FILE"
  fi
elif [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

FILES=""

# Helper function to find and add service compose file
add_service() {
  local service="$1"
  local target=""
  # Search subfolder first, then direct file
  if [ -f "composes/$service/docker-compose.yaml" ]; then
    target="composes/$service/docker-compose.yaml"
  elif [ -f "composes/$service/docker-compose.yml" ]; then
    target="composes/$service/docker-compose.yml"
  elif [ -f "composes/$service/$service.docker-compose.yaml" ]; then
    target="composes/$service/$service.docker-compose.yaml"
  elif [ -f "composes/$service.docker-compose.yaml" ]; then
    target="composes/$service.docker-compose.yaml"
  fi

  if [ -n "$target" ]; then
    if [[ " $FILES " != *" -f $target "* ]]; then
      FILES="$FILES -f $target"
    fi
  fi
}

# 1. Discover and add built-in services from composes/<service>/
for service_dir in composes/*/; do
  if [ -d "$service_dir" ]; then
    service_name=$(basename "$service_dir")
    # Skip extras directory
    if [ "$service_name" = "extras" ]; then
      continue
    fi

    if is_service_enabled "$service_name" false; then
      add_service "$service_name"
    fi
  fi
done

# 2. Discover and add user-defined extra services from composes/extras/<service>/
if [ -d "composes/extras" ]; then
  for extra_dir in composes/extras/*/; do
    if [ -d "$extra_dir" ]; then
      service_name=$(basename "$extra_dir")
      if is_service_enabled "$service_name" true; then
        if [ -f "${extra_dir}docker-compose.yml" ]; then
          if [[ " $FILES " != *" -f ${extra_dir}docker-compose.yml "* ]]; then
            FILES="$FILES -f ${extra_dir}docker-compose.yml"
          fi
        elif [ -f "${extra_dir}docker-compose.yaml" ]; then
          if [[ " $FILES " != *" -f ${extra_dir}docker-compose.yaml "* ]]; then
            FILES="$FILES -f ${extra_dir}docker-compose.yaml"
          fi
        fi
      fi
    fi
  done
fi

# 3. Discover optional standalone custom compose files
for custom in composes/*.custom.docker-compose.yaml composes/*/*.custom.docker-compose.yaml; do
  if [ -e "$custom" ]; then
    FILES="$FILES -f $custom"
  fi
done

echo "$FILES"
