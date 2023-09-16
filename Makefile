start: # Start all docker containers
	@bash scripts/util/start.sh

logs: # View all docker containers logs
	@bash scripts/util/logs.sh

stop: # Stop all docker containers
	@bash scripts/util/stop.sh

view-backups: # View all backups
	@bash scripts/backups/view-backups.sh

backup: # Create a system backup
	@bash scripts/backups/backup.sh

restore: # Restore from backup
	@bash scripts/backups/restore.sh