# Luca's home server configuration

Welcome to my home server configuration! This setup showcases an impressive array of services, including Traefik, CloudFlare Zero Trust, and several other awesome tools, all running on a self-hosted server. With this configuration, you'll have a powerful and secure infrastructure to meet your hosting needs.

## Services

- [Traefik](https://traefik.io/): A versatile reverse proxy and load balancer designed for HTTP and TCP-based applications. It provides powerful routing and traffic management capabilities.
- [CloudFlare Zero Trust](https://www.cloudflare.com/zero-trust/): An advanced Zero Trust Network Access (ZTNA) solution provided by CloudFlare. It enhances security by allowing access to services based on user identity, regardless of network location.
- [NextCloud](https://nextcloud.com/): A secure and privacy-focused file hosting service with collaborative and communication features. NextCloud empowers you to store, access, and share your files in a controlled and protected environment.
- [Portainer](https://www.portainer.io/): A user-friendly Docker management UI that simplifies the administration of containers, images, networks, and volumes. Portainer offers an intuitive interface for managing your Docker environment.
- [AdGuard Home](https://adguard.com/en/adguard-home/overview.html): A network-wide DNS server that blocks ads and trackers. AdGuard Home protects your devices from unwanted advertisements and improves your browsing experience.
- [UpTime Kuma](https://uptime.kuma.pet/): A self-hosted monitoring tool that helps you keep an eye on the health and availability of your services. UpTime Kuma provides real-time monitoring and alerts for better visibility into your server's performance.
- [Prometheus](https://prometheus.io/): A powerful monitoring system and time series database that collects metrics from various sources. Prometheus enables you to gather and analyze valuable insights about your server and applications.
- [Grafana](https://grafana.com/): A data visualization and monitoring tool that works seamlessly with Prometheus. Grafana allows you to create rich dashboards and visualizations to monitor and analyze your server's metrics effectively. Integrating Grafana with Prometheus gives you a powerful monitoring solution for your server.
  - [Node Exporter](https://github.com/prometheus/node_exporter): Prometheus exporter for hardware and OS metrics

## Docker compose

To simplify the deployment of these services on your server, this repository provides Docker Compose files for each service. You can find them in the [docker-compose](./docker-compose/) folder of this repository. These files serve as a starting point for deploying and configuring the services in your own environment. With Docker Compose, you can easily manage the containers and dependencies required by each service.

Feel free to explore the provided Docker Compose files and adapt them to your specific needs. They will help you get started quickly and ensure a smooth setup process for your home server.

Happy hosting and enjoy your self-hosted server environment!
