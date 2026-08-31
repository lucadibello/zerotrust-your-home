.PHONY: check-env check-services help start restart logs status stop down \
	backup backup-full backup-export backup-export-full backup-restore backup-view \
	backup-check backup-prune backup-unlock backup-configure \
	backup-cron-enable backup-cron-disable backup-cron-status \
	backup-prune-cron-enable backup-prune-cron-disable \
	backup-cron-enable-all backup-cron-disable-all \
	restore view-backups check prune unlock configure-backup \
	generate update-security update-security-headless update-firewall update-hardening

COMPOSE = docker compose --project-name zerotrust-your-home --project-directory .
ENVFILE = .env

# Dynamically generate compose arguments based on enabled services and custom files
COMPOSE_ARGS := $(shell bash scripts/get_docker_compose_files.sh $(ENVFILE))

# Helper function to find the docker compose file for a given service name or alias
FIND_COMPOSE = $(firstword $(wildcard \
	composes/$(1)/docker-compose.yaml \
	composes/$(1)/$(1).docker-compose.yaml \
	composes/$(1).docker-compose.yaml \
	composes/extras/$(1)/docker-compose.yml \
	composes/extras/$(1)/docker-compose.yaml \
	$(if $(filter home homeassistant hass,$(1)),composes/home-assistant/docker-compose.yaml) \
	$(if $(filter home-assistant,$(1)),composes/home-assistant/docker-compose.yaml) \
	$(if $(filter prometheus grafana alertmanager,$(1)),composes/monitoring/docker-compose.yaml) \
	$(if $(filter monitoring,$(1)),composes/monitoring/docker-compose.yaml) \
	$(if $(filter loki promtail,$(1)),composes/logging/docker-compose.yaml) \
	$(if $(filter logging,$(1)),composes/logging/docker-compose.yaml) \
	$(if $(filter restic,$(1)),composes/backup/docker-compose.yaml) \
	$(if $(filter backup,$(1)),composes/backup/docker-compose.yaml) \
	$(if $(filter bind9,$(1)),composes/dns/docker-compose.yaml) \
	$(if $(filter dns,$(1)),composes/dns/docker-compose.yaml) \
	$(if $(filter mcserver,$(1)),composes/minecraft/docker-compose.yaml) \
	$(if $(filter minecraft,$(1)),composes/minecraft/docker-compose.yaml) \
	$(if $(filter gatus uptime-kuma uptimekuma,$(1)),composes/gatus/docker-compose.yaml) \
	$(if $(filter ntfy,$(1)),composes/ntfy/docker-compose.yaml) \
	$(if $(filter traefik reverse-proxy proxy,$(1)),composes/traefik/docker-compose.yaml) \
	$(if $(filter tunnel cloudflare cloudflared,$(1)),composes/tunnel/docker-compose.yaml) \
	$(if $(filter vaultwarden bitwarden,$(1)),composes/vaultwarden/docker-compose.yaml) \
	$(if $(filter homepage dashboard,$(1)),composes/homepage/docker-compose.yaml) \
	$(if $(filter diun,$(1)),composes/diun/docker-compose.yaml) \
))

# Macro for running single-service compose commands
define RUN_SERVICE_COMPOSE
	@file="$(call FIND_COMPOSE,$(1))"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$(1)' not found."; exit 1; fi; \
	echo "$(2) $(1) service (using $$file)..."; \
	$(COMPOSE) --file "$$file" --env-file $(ENVFILE) $(3)
endef

# Common prerequisite targets for validation
check-env:
	@if [ ! -f $(ENVFILE) ]; then echo "Error: $(ENVFILE) file not found. Please create one by copying .env.example."; exit 1; fi

check-services: check-env
	@if [ -z "$(COMPOSE_ARGS)" ]; then echo "Error: No enabled service compose files found. Check your $(ENVFILE) configuration."; exit 1; fi

help:  # Show available commands
	@echo "ZeroTrust Your Home - Available Make targets:"
	@echo ""
	@echo "Management targets:"
	@echo "  make start                      Start all enabled services"
	@echo "  make stop                       Stop all running services"
	@echo "  make restart                    Restart all enabled services"
	@echo "  make status                     View status of all services"
	@echo "  make logs                       View live tail of all logs"
	@echo "  make down                       Stop and remove all containers"
	@echo "  make generate                   Regenerate configurations from .env"
	@echo ""
	@echo "Service-specific targets (<service> = traefik, nextcloud, immich, etc.):"
	@echo "  make start-<service>            Start a specific service"
	@echo "  make stop-<service>             Stop a specific service"
	@echo "  make restart-<service>          Restart a specific service"
	@echo "  make logs-<service>             View logs for a specific service"
	@echo "  make down-<service>             Stop and remove a specific service"
	@echo ""
	@echo "Backup & restore targets:"
	@echo "  make backup                     Create a system backup (incremental by default)"
	@echo "  make backup-full                Create a full system backup (full Immich export)"
	@echo "  make backup-export              Export DB dumps and Immich photos (incremental)"
	@echo "  make backup-export-full         Export DB dumps and Immich photos (full)"
	@echo "  make backup-restore             Interactive restore menu"
	@echo "  make backup-view                View backup snapshots"
	@echo "  make backup-check               Verify backup integrity"
	@echo "  make backup-prune               Prune old backups"
	@echo "  make backup-unlock              Remove stale locks from backup repositories"
	@echo "  make backup-configure           Configure Rclone remote (Google Drive/S3)"
	@echo "  make backup-cron-enable         Enable daily automatic backup cron"
	@echo "  make backup-cron-disable        Disable daily automatic backup cron"
	@echo "  make backup-prune-cron-enable   Enable weekly automatic prune cron (Sunday 03:00)"
	@echo "  make backup-prune-cron-disable  Disable weekly automatic prune cron"
	@echo "  make backup-cron-enable-all     Enable both daily backup & weekly prune crons"
	@echo "  make backup-cron-status         Show all backup and prune cronjob statuses"
	@echo ""
	@echo "Security targets:"
	@echo "  make update-security            Update hardening and firewall interactively"
	@echo "  make update-security-headless   Update hardening and firewall without prompts"
	@echo "  make update-firewall            Update firewall rules only"
	@echo "  make update-hardening           Update system hardening only"

start: check-services  # Start all docker containers
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) up -d

restart: check-services  # Restart all docker containers
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) restart

logs: check-services  # View all docker containers logs
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) logs -f --tail=50

status: check-services  # View the status of the current ZeroTrust Your Home services
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"

stop: check-services  # Stop all docker containers
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) stop

down: check-services  # Stop and remove all docker containers
	@$(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) down

backup-view: # View all backups
	@bash scripts/backups/view-backups.sh

view-backups: backup-view

backup-configure: # Configure Rclone for Google Drive/S3
	@bash scripts/backups/configure-rclone.sh

configure-backup: backup-configure

backup: # Create a system backup (pass ARGS="--full" or use 'make backup-full')
	@bash scripts/backups/backup.sh $(ARGS)

backup-full: # Force a full system backup (full Immich photo export + Restic snapshot)
	@bash scripts/backups/backup.sh --full

backup-export: # Export data only (Immich photos, DB dumps) without Restic snapshot
	@bash scripts/backups/backup-export.sh $(ARGS)

backup-export-full: # Force full export of data (all Immich photos + DB dumps)
	@bash scripts/backups/backup-export.sh --full

backup-prune: # Prune old backups to free up space
	@bash scripts/backups/prune.sh

prune: backup-prune

backup-check: # Verify backup integrity
	@bash scripts/backups/check.sh

check: backup-check

backup-unlock: # Remove stale repository locks
	@bash scripts/backups/unlock.sh

unlock: backup-unlock

backup-restore: # Restore from backup
	@bash scripts/backups/restore.sh

restore: backup-restore

backup-cron-enable: # Enable automatic daily system backup at 00:00
	@bash scripts/backups/setup-backup-cron.sh enable

backup-cron-disable: # Disable automatic daily system backup
	@bash scripts/backups/setup-backup-cron.sh disable

backup-prune-cron-enable: # Enable automatic weekly backup prune (Sunday at 03:00)
	@bash scripts/backups/setup-backup-cron.sh enable-prune

backup-prune-cron-disable: # Disable automatic weekly backup prune
	@bash scripts/backups/setup-backup-cron.sh disable-prune

backup-cron-enable-all: # Enable both daily backup and weekly prune cronjobs
	@bash scripts/backups/setup-backup-cron.sh enable-all

backup-cron-disable-all: # Disable all backup and prune cronjobs
	@bash scripts/backups/setup-backup-cron.sh disable-all

backup-cron-status: # Show all backup and prune cronjob statuses
	@bash scripts/backups/setup-backup-cron.sh status

generate: # Regenerate configuration files for all services based on .env configuration
	@bash scripts/generate.sh --headless

update-security: # Update security posture (hardening + firewall) on existing instances
	@bash scripts/update-security.sh

update-security-headless: # Update security posture without prompts
	@bash scripts/update-security.sh -y

update-firewall: # Update only firewall rules
	@bash scripts/update-security.sh -y --firewall-only

update-hardening: # Update only system hardening settings
	@bash scripts/update-security.sh -y --hardening-only


# Specific commands to control each part of the system
start-%: check-env
	$(call RUN_SERVICE_COMPOSE,$*,Starting,up -d)

down-%: check-env
	$(call RUN_SERVICE_COMPOSE,$*,Downing,down)

stop-%: check-env
	$(call RUN_SERVICE_COMPOSE,$*,Stopping,stop)

logs-%: check-env
	$(call RUN_SERVICE_COMPOSE,$*,Showing logs for,logs -f --tail=50)

restart-%: check-env
	$(call RUN_SERVICE_COMPOSE,$*,Restarting,restart)
