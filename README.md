# Luca's home server configuration <!-- omit in toc -->

My self-hosted server configuration featuring Traefik, CloudFlare Zero Trust and some other awesome services

## Table of contents <!-- omit in toc -->

- [Services](#services)
- [Architecture](#architecture)
- [Docker compose](#docker-compose)

## Services

- [Traefik](https://traefik.io/): Reverse proxy and load balancer for HTTP and TCP-based applications
- [CloudFlare Zero Trust](https://www.cloudflare.com/teams/zero-trust-access/): Zero Trust Network Access (ZTNA) solution
- [NextCloud](https://nextcloud.com/): File hosting service with a focus on security and privacy
- [Portainer](https://www.portainer.io/): Docker management UI
- [AdGuard Home](https://adguard.com/en/adguard-home/overview.html): Network-wide ads & trackers blocking DNS server
- [UpTime Kuma](https://uptime.kuma.pet/): Self-hosted monitoring tool
- [Prometheus](https://prometheus.io/): Monitoring system and time series database
- [Grafana](https://grafana.com/): Data visualization and monitoring tool
  - [Node Exporter](https://github.com/prometheus/node_exporter): Prometheus exporter for hardware and OS metrics
- [Keycloak](https://www.keycloak.org/): Open Source Identity and Access Management For Modern Applications and Services
- [Passbolt](https://www.passbolt.com/): Open source password manager for teams

## Architecture

![Architecture](./architecture.png)

## Docker compose

To simplify the deployment of the services on your server, I created a docker compose file for each service I have installed in my server so that you can use as a starting point. You can find them in the [docker-compose](./docker-compose) folder.
