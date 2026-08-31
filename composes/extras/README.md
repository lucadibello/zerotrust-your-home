# Extra Services

This directory allows you to add **custom services** that are automatically discovered and managed alongside the core homelab stack.

## Directory Structure

Each extra service lives in its own subdirectory with at least a `docker-compose.yml` file:

```text
composes/extras/
└── my-app/
    ├── docker-compose.yml          # Required: Docker Compose service definition
    ├── gatus.yaml                  # Optional: Gatus health-check endpoint(s)
    └── config/                     # Optional: Service-specific configuration files
```

## How It Works

1. **Automatic Compose Discovery**: When you run `make start`, `make stop`, etc., every `docker-compose.yml` (or `.yaml`) found under `composes/extras/<service>/` is automatically included.
2. **Per-Service Control**: You can target individual extra services with `make start-<service>`, `make logs-<service>`, `make restart-<service>`, `make stop-<service>`, and `make down-<service>`.
3. **Gatus Health Monitoring**: If you include a `gatus.yaml` (or `gatus.yml`) file, its endpoint definitions are automatically merged into the Gatus configuration during `make generate`.

## Example: Adding a Custom Service

### 1. Create the service directory

```bash
mkdir -p composes/extras/whoami
```

### 2. Create `docker-compose.yml`

```yaml
services:
  whoami:
    image: traefik/whoami:latest
    container_name: whoami
    restart: unless-stopped
    networks:
      - traefik-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.${DNS_DOMAIN}`)"
      - "traefik.http.routers.whoami.entrypoints=websecure"
      - "traefik.http.routers.whoami.tls.certresolver=letsencrypt"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
      - "traefik.docker.network=traefik-network"

networks:
  traefik-network:
    external: true
```

### 3. (Optional) Create `gatus.yaml`

Define one or more Gatus endpoint entries. Use standard YAML list format—the system handles indentation automatically.

You can use template placeholders (e.g., `<DNS_DOMAIN>`, `<NTFY_URL>`, `<NTFY_TOPIC>`, `<NTFY_TOKEN>`) and they will be substituted with values from your `.env` file during `make generate`.

```yaml
- name: Whoami
  group: Extras
  url: "http://whoami:80/health"
  interval: 60s
  conditions:
    - "[STATUS] == 200"
  alerts:
    - type: ntfy
      enabled: true
```

### 4. Regenerate and start

```bash
make generate   # Regenerate configs (including Gatus endpoints)
make start      # Start all services including extras
```

Or start only your extra service:

```bash
make start-whoami
make logs-whoami
```

## Template Placeholders

The following placeholders are available in `gatus.yaml` files and are substituted during `make generate`:

| Placeholder     | Source                         | Default                                  |
|:--------------- |:------------------------------ |:---------------------------------------- |
| `<DNS_DOMAIN>`  | `DNS_DOMAIN` from `.env`       | `example.com`                            |
| `<NTFY_URL>`    | `NTFY_URL` from `.env`         | `https://ntfy.home.lucadibello.ch`       |
| `<NTFY_TOPIC>`  | `NTFY_TOPIC` from `.env`       | `lucadibello-homelab-status`             |
| `<NTFY_TOKEN>`  | `NTFY_TOKEN` from `.env`       | *(empty)*                                |

## Notes

- Extra services are **always enabled**—there is no `ENABLE_*` flag. If the directory and compose file exist, they are included.
- To disable an extra service temporarily, rename or remove its `docker-compose.yml` file.
- The `.env` file from the project root is passed to all compose files, so environment variables like `${DNS_DOMAIN}` work as expected.
