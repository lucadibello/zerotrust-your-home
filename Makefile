COMPOSE = docker-compose
ENVFILE = .env

# Use find to list compose files and grep to exclude optional/manual services
# Excluded by default: tunnel (requires manual setup), mcserver (gaming), home (IoT specific)
COMPOSE_FILES := $(shell find composes -maxdepth 1 -name '*.docker-compose.yaml' | grep -Ev 'tunnel|mcserver|home|immich|searxng')
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
