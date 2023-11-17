# Uptime Kuma service health monitoring

As cited in the README, *Uptime Kuma* has been configured to monitor the status of the internal services running on system (i.e., Home Assistant, Prometheus, Grafana). These are the configured monitor groups with their relative targets and monitoring approach:

- Group 1 - System monitoring
  - *Prometheus Alertmanager*: HTTP health check (*<http://alertmanager:9093/-/healthy>*)
  - *cAdvisor*: HTTP health check (*<http://cadvisor:8080/healthz>*)
  - *Grafana*: HTTP health check (*<http://grafana:3000/api/health>*)
  - *Node exporter*: HTTP health check (*<http://node_exporter:9100/health>*)
  - *Prometheus*: HTTP health check (*<http://prometheus:9090/-/healthy>*)

- Group 2 - Network infrastructure
  - *Traefik*: HTTP health check (*<http://traefik:80/ping>*)
  - *BIND9*: DNS request to resolve SOA record (the one specified during system setup)
  - *Cloudflare Tunnel*: Docker container health check

- Group 3 - Log management suite
  - *Loki*: HTTP health check (*<http://loki:3100/ready>*)
  - *Promtail*: Docker container health check

- Group 4 - Home automation system
  - *Zigbee2MQTT*: Docker container health monitoring
  - *Mosquito*: Docker container health monitoring
  - *Home Assistant*: Docker container health monitoring

- Group 5 - Backup & restore suite
  - *Restic (Backup)*: Docker container health monitoring
  - *Restic (Check)*: Docker container health monitoring
  - *Restic (Prune)*: Docker container health monitoring

- Group 6 - Automatic updates
  - *Watchtower*: Docker container health monitoring