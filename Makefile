COMPOSE = docker compose
ENVFILE = .env

# Dynamically generate compose arguments based on enabled services and custom files
COMPOSE_ARGS := $(shell bash scripts/get_docker_compose_files.sh)

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
	@echo "Starting $* service..."
	@sudo $(COMPOSE) --file composes/$*.docker-compose.yaml --env-file $(ENVFILE) up -d

down-%:
	@echo "Downing $* service..."
	@sudo $(COMPOSE) --file composes/$*.docker-compose.yaml --env-file $(ENVFILE) down

stop-%:
	@echo "Stopping $* service..."
	@sudo $(COMPOSE) --file composes/$*.docker-compose.yaml --env-file $(ENVFILE) stop

logs-%:
	@echo "Logs $* service..."
	@sudo $(COMPOSE) --file composes/$*.docker-compose.yaml --env-file $(ENVFILE) logs

restart-%:
	@echo "Restarting $* service..."
	@sudo $(COMPOSE) --file composes/$*.docker-compose.yaml --env-file $(ENVFILE) restart
