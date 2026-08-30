COMPOSE = docker compose
ENVFILE = .env

# Dynamically generate compose arguments based on enabled services and custom files
COMPOSE_ARGS := $(shell bash scripts/get_docker_compose_files.sh)

# Helper function to find the docker compose file for a given service name or alias
FIND_COMPOSE = $(firstword $(wildcard \
	composes/$(1)/docker-compose.yaml \
	composes/$(1)/$(1).docker-compose.yaml \
	composes/$(1).docker-compose.yaml \
	$(if $(filter home,$(1)),composes/home-assistant/docker-compose.yaml) \
	$(if $(filter home-assistant,$(1)),composes/home-assistant/docker-compose.yaml) \
	$(if $(filter prometheus,$(1)),composes/monitoring/docker-compose.yaml) \
	$(if $(filter monitoring,$(1)),composes/monitoring/docker-compose.yaml) \
	$(if $(filter loki,$(1)),composes/logging/docker-compose.yaml) \
	$(if $(filter logging,$(1)),composes/logging/docker-compose.yaml) \
	$(if $(filter restic,$(1)),composes/backup/docker-compose.yaml) \
	$(if $(filter backup,$(1)),composes/backup/docker-compose.yaml) \
	$(if $(filter bind9,$(1)),composes/dns/docker-compose.yaml) \
	$(if $(filter dns,$(1)),composes/dns/docker-compose.yaml) \
	$(if $(filter mcserver,$(1)),composes/minecraft/docker-compose.yaml) \
	$(if $(filter minecraft,$(1)),composes/minecraft/docker-compose.yaml) \
	$(if $(filter gatus,$(1)),composes/gatus/docker-compose.yaml) \
	$(if $(filter ntfy,$(1)),composes/ntfy/docker-compose.yaml) \
))

start:  # Start all docker containers
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) up -d

restart:  # Restart all docker containers
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) restart

logs:  # View all docker containers logs
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) logs -f --tail=50

status:  # View the status of the current ZeroTrust Your Home services
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"

stop:  # Stop all docker containers
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) stop

view-backups: # View all backups
	@bash scripts/backups/view-backups.sh

configure-backup: # Configure Rclone for Google Drive
	@bash scripts/backups/configure-rclone.sh

backup: # Create a system backup
	@bash scripts/backups/backup.sh

backup-export: # Export data only (Immich photos, DB dumps). Used by cronjob before restic's automatic run.
	@bash scripts/backups/backup-export.sh

prune: # Prune old backups to free up space
	@bash scripts/backups/prune.sh

check: # Verify backup integrity
	@bash scripts/backups/check.sh

restore: # Restore from backup
	@bash scripts/backups/restore.sh

backup-cron-enable: # Enable automatic daily backup export at 23:30
	@bash scripts/backups/setup-backup-cron.sh enable

backup-cron-disable: # Disable automatic daily backup export
	@bash scripts/backups/setup-backup-cron.sh disable

backup-cron-status: # Show backup cronjob status
	@bash scripts/backups/setup-backup-cron.sh status

generate: # Regenerate configuration files for all services based on .env configuration
	@sudo bash scripts/generate.sh --headless

update-security: # Update security posture (hardening + firewall) on existing instances
	@sudo bash scripts/update-security.sh

update-security-headless: # Update security posture without prompts
	@sudo bash scripts/update-security.sh -y

update-firewall: # Update only firewall rules
	@sudo bash scripts/update-security.sh -y --firewall-only

update-hardening: # Update only system hardening settings
	@sudo bash scripts/update-security.sh -y --hardening-only


# Specific commands to control each part of the system
start-%:
	@file="$(call FIND_COMPOSE,$*)"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$*' not found."; exit 1; fi; \
	echo "Starting $* service (using $$file)..."; \
	sudo $(COMPOSE) --file "$$file" --env-file $(ENVFILE) up -d

down-%:
	@file="$(call FIND_COMPOSE,$*)"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$*' not found."; exit 1; fi; \
	echo "Downing $* service (using $$file)..."; \
	sudo $(COMPOSE) --file "$$file" --env-file $(ENVFILE) down

stop-%:
	@file="$(call FIND_COMPOSE,$*)"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$*' not found."; exit 1; fi; \
	echo "Stopping $* service (using $$file)..."; \
	sudo $(COMPOSE) --file "$$file" --env-file $(ENVFILE) stop

logs-%:
	@file="$(call FIND_COMPOSE,$*)"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$*' not found."; exit 1; fi; \
	echo "Logs for $* service (using $$file)..."; \
	sudo $(COMPOSE) --file "$$file" --env-file $(ENVFILE) logs

restart-%:
	@file="$(call FIND_COMPOSE,$*)"; \
	if [ -z "$$file" ]; then echo "Error: Compose file for service '$*' not found."; exit 1; fi; \
	echo "Restarting $* service (using $$file)..."; \
	sudo $(COMPOSE) --file "$$file" --env-file $(ENVFILE) restart
