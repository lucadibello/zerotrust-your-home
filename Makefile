COMPOSE = docker-compose
ENVFILE = .env

# Use find to list compose files and grep to exclude files containing "home"
COMPOSE_FILES := $(shell find composes -maxdepth 1 -name '*.docker-compose.yaml' | grep -v 'home')
# Prepend "-f" to each file for docker-compose
COMPOSE_ARGS := $(foreach file,$(COMPOSE_FILES),-f $(file))

start:  # Start all docker containers
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) up -d

logs:  # View all docker containers logs
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) logs -f --tail=50

stop:  # Stop all docker containers
	@sudo $(COMPOSE) $(COMPOSE_ARGS) --env-file $(ENVFILE) stop

view-backups: # View all backups
	@bash scripts/backups/view-backups.sh

backup: # Create a system backup
	@bash scripts/backups/backup.sh

restore: # Restore from backup
	@bash scripts/backups/restore.sh

generate: # Regenerate configuration files for all services based on .env configuration
	@sudo bash scripts/generate.sh --headless

