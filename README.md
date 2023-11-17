# ZeroTrust Your Home - A safe and private environment for you and your data<!-- omit in toc -->

![ZeroTrust Your Home](./assets/images/header.jpg)

## Table of contents<!-- omit in toc -->

- [1. Motivation](#1-motivation)
- [2. Project description](#2-project-description)
- [3. System capabilities](#3-system-capabilities)
  - [3.1. Continuous monitoring and alerting system](#31-continuous-monitoring-and-alerting-system)
    - [3.1.1. Alerting rules](#311-alerting-rules)
    - [3.1.2. Service health monitoring](#312-service-health-monitoring)
  - [3.2. Log management suite](#32-log-management-suite)
  - [3.3. Backup and restore suite](#33-backup-and-restore-suite)
    - [3.3.1. Backup retention policies](#331-backup-retention-policies)
    - [3.3.2. Backup notifications](#332-backup-notifications)
    - [3.3.3. Backup and restore operations via CLI](#333-backup-and-restore-operations-via-cli)
  - [3.4. Home automation system](#34-home-automation-system)
  - [3.5. Automatic updates](#35-automatic-updates)
    - [3.5.1. System updates](#351-system-updates)
    - [3.5.2. Docker image updates](#352-docker-image-updates)
  - [3.6. Network infrastructure](#36-network-infrastructure)
    - [3.6.1. DNS Server](#361-dns-server)
    - [3.6.2. Reverse proxy](#362-reverse-proxy)
      - [3.6.2.1. SSL certificate generation and renewal for internal domain names](#3621-ssl-certificate-generation-and-renewal-for-internal-domain-names)
- [4. System extensibility and additional services](#4-system-extensibility-and-additional-services)
- [5. Testing the system](#5-testing-the-system)
  - [5.1. Hardware](#51-hardware)
  - [5.2. Security tests](#52-security-tests)
- [6. Additional resources](#6-additional-resources)
  - [6.1. Docker containers network segmentation](#61-docker-containers-network-segmentation)

## 1. Motivation

Information systems play an increasingly key role in our daily lives, in sectors as diverse as public services, healthcare, finance, industry and more. Ensuring the security and privacy of systems is of critical importance as it protects the data of users and the integrity of the systems themselves.

## 2. Project description

This project showcases an autoconfigured home server environment that provides a powerful and secure infrastructure that leverages cutting-edge technologies to ensure security, privacy, and ease of use. It provides the user with a set of pre-configured services and applications that can be easily extended and customized to meet the user's needs.

Employing [Cloudflare SSE & SASE Platform](https://www.cloudflare.com/zero-trust/#zt-features), the server adheres with the Zero Trust security model, in fact, to be able to access the services the user needs to be authenticated, authorized and the device security must be verified through automated posture checks.

The developed infrastructure has been designed to be easily extensible and customizable. In fact, a user can easily extend the server with additional services and applications without any additional configuration.

## 3. System capabilities

The server is based on six main components to provide a secure and private environment for the user data. In the following sections, each component will be described in detail to provide a better understanding of the server architecture.

The entire system is based upon [Docker](https://www.docker.com/) containers to leverage application virtualization, aiming to provide a secure and isolated environment for each application.

![System six pillars](./assets/images/system-components.png)

In the following sections, each component will be described in detail to provide a better understanding of the server architecture.

### 3.1. Continuous monitoring and alerting system

With a continuous monitoring solution system administrators can be notified in real-time when an issue is detected, allowing to respond quickly and effectively. For this purpose, the open-source monitoring solution [Prometheus](https://prometheus.io/) has been used in pair with [Grafana](https://grafana.com/) to collect and visualize metrics of the operating system and the various *Docker* containers.

To provide real-time notifications, [Prometheus Alerts](https://prometheus.io/docs/alerting/latest/alertmanager/) have been configured to trigger alerts when specific system metrics exceeds a predefined threshold.

While *Prometheus* is charge of monitoring the status of the system and the running containers, [Uptime Kuma](https://github.com/louislam/uptime-kuma) has been employed to monitor the health of the many applications and services running on the server.

![Monitoring and alerting system](./assets/images/continuous-monitoring-flow.png)

*Note: Grafana has been configured to ship two custom dashboards via [provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/), out-of-the-box, without any additional configuration.*

#### 3.1.1. Alerting rules

For the purpose of this project, five alerting rules have been configured to monitor the health of the system and the running containers. Refer to the [Prometheus Alerting Rules](./doc/prometheus-alerting-rules.md) document for more details.

*Note: For the particular use case thought for this project, Telegram has been chosen as notification channel as it provides the most convenient solution. The individuals using the services hosted on the system are not expected to have technical skills and is not expected to have business accounts on other platforms such as Slack or WeChat.*

#### 3.1.2. Service health monitoring

*Uptime Kuma* allows to monitor the status of the applications and services of the system and to receive real-time notifications when a service is down. The uptime check is performed by periodically sending requests (i.e. HTTP, TCP, ICMP) to the monitored targets and alerting the system administrator using the configured Telegram bot in case of failures.

![Uptime Kuma](./assets/images/uptimekuma-dashboard.png)

To learn more about how *Uptime Kuma* has been configured to perform its purpose, please refer to the file [Uptime Kuma service health monitoring](./doc/uptime-kuma-monitoring.md). On the other hand, an example of the notifications sent by *Uptime Kuma* can be found in the dedicated document [Monitoring suite - Telegram alerts examples](./doc/monitoring-telegram-alerts.md).

### 3.2. Log management suite

A log management solution has been implemented to centralize the collection, storage, and visualization of logs of the system services and Docker containers. The centralization of logs enables system administrators to access, query and visualize logs of different components of the system from a single interface, simplifying the process of troubleshooting and debugging of the system.

The following image illustrates the architecture of the log management suite.

![Log management suite](./assets/images/log-management-flow.png)

[Grafana Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) is configured to collect logs from the system and the running *Docker* containers and to send them to *Loki* for storage and indexing. Stored logs can be queried via the *Explore* section of the Grafana web interface (yes, all out-of-the-box!). This is a sample screenshot of the result of a query:

![Grafana Explore](./assets/images/loki-grafana.png)

### 3.3. Backup and restore suite

To ensure data integrity in case of disasters such as hardware failures or physical damage, a robust backup solution has been implemented to periodically backup critical data stored in the system.

The use of a cloud storage solution like Amazon S3 (the one configured by default) is recommended as it provides a cheap and reliable solution to archive backups without incurring in disk capacity issues. It is important to highlight that the user can easily configure the backup solution to use a different cloud storage provider (i.e., Google Cloud Storage, Azure Blob Storage, etc.) or a local storage solution (i.e., NAS, external hard drive, etc.) (read official documentation [here](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html)).

The following image illustrates the architecture of the backup and restore suite.

![Backup and restore suite](./assets/images/backup-restore-flow.png)

In the figure is possible to notice that are present three different instances of *Restic* running at the same time. Each instance has a different purpose and is configured to perform specific tasks at specific times:

1. The *backup* instance: configured to perform daily backups of the Docker volumes (every day at midnight). To guarantee data confidentiality, backups are encrypted before being sent to the cloud storage.

2. The *restore* instance: in charge of cleaning up the S3 bucket by removing old backups based on the configured retention policies (refer to the next section for more details).

3. The *check* instance: is responsible for verifying the integrity of the backup repository stored in the S3 bucket. This operation is executed on a daily basis (every day at 5:15 AM, 1h15m after the prune operation). The check process consists in analyzing 10% of the total data stored in the cloud storage, ensuring the reliability and integrity of the backups.

#### 3.3.1. Backup retention policies

Retention policies ensure the retention of a specific number of backups, while removing the oldest one as the limit is reached. These are the configured retention policies:

- Keep last seven daily backups
- Keep last four weekly backups
- Keep last twelve monthly backups

#### 3.3.2. Backup notifications

Leveraging Telegram APIs, the *Restic* is able to notify administrators when a backup operation is completed, when it fails (i.e., S3 bucket unavailable) and when it has been interrupted (i.e., one or more files are unreadable).

The following image shows all the possible notifications sent by the backup instance.

<img src="./assets/images/restic-backup-notification.jpeg" width="400">

#### 3.3.3. Backup and restore operations via CLI

To simplify the backup and restore operations, a Makefile script has been developed to automate the backup and restore procedures as much as possible.

The following commands are available:

- **make backup**: creates a new incremental backup of the *Docker* volumes and sends it to the S3 bucket.

- **make restore**: wizard to restore the system from a backup selected by the user from the list of available backups. After the backup is performed, it will check the integrity of the restored data to ensure the integrity of the restored data.

*Note: it is important to note that the restore command first shuts down all running Docker containers, then restores the selected backup, and finally restarts all containers to ensure the integrity of the data.*

### 3.4. Home automation system

$\textcolor{RED}{\text{WIP: Already implemented but not added to the project yet.}}$

The developed home automation system is based on [Home Assistant](https://www.home-assistant.io/) thus supporting out-of-the-box the following IoT devices:

- ZigBee devices
- Ethernet devices
- Wi-Fi devices
- Bluetooth devices

The following image shows the architecture of the implemented home automation system:

![Home automation system](./assets/images/home-automation-flow.png)

To support ZigBee devices, additional two software components have been added to the system:

- **ZigBee2Mqtt**: is a software bridge that allows to integrate ZigBee devices with MQTT. It implements a ZigBee to MQTT bridge, which allows ZigBee devices to communicate with MQTT. The bridge automatically maps physical devices to MQTT topics. It also supports per-device settings, allowing to set a friendly name for each device.

- **Mosquitto**: is an open-source message broker that implements the MQTT protocol. It is responsible for receiving messages from Zigbee2MQTT and forwarding them to Home Assistant via MQTT.

*Note: to be able to use the ZigBee devices, the user needs to have a ZigBee USB dongle. The recommended one is the [Sonoff ZigBee 3.0 USB Dongle Plus](https://sonoff.tech/product/gateway-and-sensors/sonoff-zigbee-3-0-usb-dongle-plus-p/)*

Since connecting ZigBee devices to Home Assistant requires some additional configuration, a dedicated document has been created to guide the user through the process. Refer to the [ZigBee devices pairing tutorial](./doc/zigbee-pairing-tutorial.md) for more details.

### 3.5. Automatic updates

In a production environment, it is critical to keep the system and all the installed packages up to date with the latest security patches and updates to ensure the security and availability of the infrastructure. In the following section is presented the approach used to automate the update process of the system and the Docker containers running on the system.

#### 3.5.1. System updates

To ensure the security of the system, it is critical to keep the operating system and all the installed packages up to date with the latest security patches. This operation is usually done manually by the system administrator(s), requiring extra time and effort to keep the system up to date.

To solve this problem, the system configuration script installs and configure the [unattended-upgrades](https://wiki.debian.org/UnattendedUpgrades) package, a tool that allows to systematically install security patches and updates without the need for user intervention. This approach guarantees the security and stability of the system, while reducing the time and effort required to keep the system up to date.

#### 3.5.2. Docker image updates

Given the virtualized nature of the system infrastructure, it is critical to keep Docker containers up to date with the latest security patches and updates. Similar to system updates, this can be done either manually by administrators or autonomously using dedicated tools that periodically check for new image versions and update running containers.

To automate this process, the tool [Watchtower](https://github.com/containrrr/watchtower) has been selected due to its simplicity to deploy and use. This containerized tool periodically scans the running containers for out- dated images and based on the specified configuration, updates containers with the latest available image version (if any).

Notably, this tool automatically restarts updated containers using the new image, ensuring the latest version of the image is always running. This is a critical feature as it allows to maintain the previous container configuration to prevent breaking changes.

The *Watchtower* container has been configured to check for new versions of the images every 24 hours. After every cycle, a full report is generated and sent to the system administrator via Telegram. This is a screenshot of the update report sent by *Watchtower*:

<img src="./assets/images/watchtower-notification.jpg" width="400">

### 3.6. Network infrastructure

#### 3.6.1. DNS Server

As exposed services are behind a reverse proxy, it is necessary to configure a DNS server to resolve the domain names of the services hosted on the server. To address these requirements, the open-source DNS server [BIND9](https://www.isc.org/bind/) has been used. BIND9 is the most widely used DNS server software, that provides a robust and stable platform on top of which organizations can build distributed computing systems fully compliant with published DNS standards.

Based on the domain name specified in the configuration file prior to the deployment of the system, the DNS server will be configured with a specific zone file that maps the domain name to the IP address of the server via a wildcard record. This allows to easily add new services to the system without the need to manually configure the DNS server.

To enhance security, the DNS server has been configured to only accept queries from the internal network, thus preventing external users from querying the DNS server. To limit even more the attack-surface DNSSEC enabled to provide authentication and integrity to the DNS responses.

#### 3.6.2. Reverse proxy

To provide an additional layer of security to the system and to simplify the exposure of internal services to the LAN (i.e., Home Assistant dashboard), the reverse proxy [Traefik](https://traefik.io/traefik/) has been implemented.

Traefik is a modern HTTP reverse proxy and load balancer written in Go, designed specifically for *dockerized* environments. It is a lightweight and easy to use solution that provides advanced features such as automatic SSL certificate generation and renewal, HTTP/2 sup- port, load balancing and circuit breakers.

The choice of Traefik is motivated by its key feature: its ability to automatically discover containers and dynamically update its configuration, allowing to easily expose securely new system services without ever touching configuration files. This enhances the extensibility of the system, allowing to easily add new services without breaking the existing ones.

##### 3.6.2.1. SSL certificate generation and renewal for internal domain names

If the user has a domain name registered on Cloudflare, it is possible to leverage the Cloudflare API to automatically generate and renew SSL certificates for the internal domain names used by the system without exposing them to the internet. This approach allows to easily add new services to the system without the need to manually generate and renew SSL certificates.

This process is fully automated and requires no user intervention. For more details about the implementation of this feature, please refer to the official Traefik documentation [here](https://doc.traefik.io/traefik/https/acme/#dnschallenge).

## 4. System extensibility and additional services

To showcase the extensibility of the implemented system, the following services have been added to the system:

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden), a self-hosted password manager compatible with the Bitwarden clients.
- [Nextcloud](https://nextcloud.com/), a self-hosted cloud storage solution that allows to store and share files, manage calendars, contacts, and more.
- [Personal website](https://lucadibello.ch/) to showcase how to host custom services on the server.

## 5. Testing the system

### 5.1. Hardware

### 5.2. Security tests

## 6. Additional resources

### 6.1. Docker containers network segmentation

The following diagram shows the network segmentation of the Docker containers used by the server.

![Docker containers network segmentation](./images/docker-containers-network-diagram.png)