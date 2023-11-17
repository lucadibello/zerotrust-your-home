# ZeroTrust Smart Space - A safe and private environment for you and your data<!-- omit in toc -->

## Table of contents<!-- omit in toc -->

- [1. Introduction](#1-introduction)
- [2. Technical details](#2-technical-details)
- [3. Six main components](#3-six-main-components)
  - [3.1. Continuous monitoring and alerting system](#31-continuous-monitoring-and-alerting-system)
    - [3.1.1. Alerting rules](#311-alerting-rules)
    - [3.1.2. Service health monitoring](#312-service-health-monitoring)
  - [3.1.2. Log management suite](#312-log-management-suite)
  - [3.1.3. Backup and restore suite](#313-backup-and-restore-suite)
  - [3.1.4. Home automation system](#314-home-automation-system)
    - [3.1.5. ZigBee devices pairing tutorial](#315-zigbee-devices-pairing-tutorial)
    - [3.1.6.  ZigBee automation examples](#316-zigbee-automation-examples)
    - [3.1.7. Automatic updates](#317-automatic-updates)
    - [3.1.8. Network infrastructure](#318-network-infrastructure)
  - [3.2. Docker containers network segmentation](#32-docker-containers-network-segmentation)

## 1. Introduction

This project showcases an autoconfigured home server environment that provides a powerful and secure infrastructure that leverages cutting-edge technologies to ensure security, privacy, and ease of use. It provides the user with a set of pre-configured services and applications that can be easily extended and customized to meet the user's needs.

Employing [Cloudflare SSE & SASE Platform](https://www.cloudflare.com/zero-trust/#zt-features), the server adheres with the Zero Trust security model, in fact, to be able to access the services the user needs to be authenticated, authorized and the device security must be verified through automated posture checks.

The developed infrastructure has been designed to be easily extensible and customizable. In fact, a user can easily extend the server with additional services and applications without any additional configuration.

## 2. Technical details

The server is based on five main components to provide a secure and private environment for the user data. In the following sections, each component will be described in detail to provide a better understanding of the server architecture.

The entire system is based upon [Docker](https://www.docker.com/) containers to leverage application virtualization, aiming to provide a secure and isolated environment for each application.

## 3. Six main components

![System six pillars](./assets/images/system-components.png)

In the following sections, each component will be described in detail to provide a better understanding of the server architecture.

### 3.1. Continuous monitoring and alerting system

With a continuous monitoring solution system administrators can be notified in real-time when an issue is detected, allowing to respond quickly and effectively. For this purpose, the open-source monitoring solution *Prometheus* has been used in pair with *Grafana* to collect and visualize metrics of the operating system and the various *Docker* containers.

To provide real-time notifications, *Prometheus Alerts* have been configured to trigger alerts when specific system metrics exceeds a predefined threshold.

While *Prometheus* is charge of monitoring the status of the system and the running containers, *Uptime Kuma* has been employed to monitor the health of the many applications and services running on the server.

![Monitoring and alerting system](./assets/images/continuous-monitoring-flow.png)

*Note: Grafana has been configured to automatically import the custom dashboards, without any additional configuration.*

#### 3.1.1. Alerting rules

Alerting rules are conditions evaluated periodically by *Prometheus* that whenever are met, it will trigger an alert via *Prometheus Alertmanager*. The alert manager will then notify the system administrators via the configured notification channels (i.e., Telegram, E-Mail, Slack).

The following list outlines the alerting rules configured to monitor the system health:

1. *Instance down*: triggers an alert when one of the core services of the monitoring suite (*Prometheus*, *Node Exporter* or *cAdvisor*) is down for more than 1 minute

2. *High disk usage*: triggers an alert when the disk usage of the host machine on ’/’ exceeds 80% for more than 10 minutes.

3. *High CPU usage*: triggers an alert when the CPU usage of the host machine exceeds 80% for more than 5 minutes.

4. *High network traffic*: triggers an alert when the inbound network traffic of the host machine exceeds 10Mb/s for the last minute.

5. *High CPU temperature*: triggers an alert when the CPU temperature of the host machine exceeds 70 °C for more than 1 minute.

For the particular use case thought for this project, Telegram has been chosen as notification channel as it provides the most convenient solution. The individuals using the services hosted on the system are not expected to have technical skills and is not expected to have business accounts on other platforms such as Slack or WeChat.

The following image shows an example of an alert triggered by the *Instance Down* rule.

![Instance down alert](./assets/images/cadvisor-telegram-alert.jpg)

#### 3.1.2. Service health monitoring

*Uptime Kuma* allows to monitor the status of the applications and services of the system and to receive real-time notifications when a service is down. The uptime check is performed by periodically sending requests (i.e. HTTP, TCP, ICMP) to the monitored targets and alerting the system administrator using the configured Telegram bot in case of failures.

![Uptime Kuma](./assets/images/uptimekuma-dashboard.png)

This is an example of a notification sent by *Uptime Kuma* when one of the monitored services is down.

![Uptime Kuma alert](./assets/images/uptimekuma-alert.png)

### 3.1.2. Log management suite

### 3.1.3. Backup and restore suite

### 3.1.4. Home automation system

WIP: Already implemented but not added to the project yet. The developed home automation system is based on Home Assistant and supports out-of-the-box the following kind of devices:

- ZigBee devices
- Ethernet devices
- Wi-Fi devices
- Bluetooth devices

*Note: to be able to use the ZigBee devices, the user needs to have a ZigBee USB dongle. The recommended one is the [Sonoff ZigBee 3.0 USB Dongle Plus](https://sonoff.tech/product/gateway-and-sensors/sonoff-zigbee-3-0-usb-dongle-plus-p/)*

#### 3.1.5. ZigBee devices pairing tutorial

#### 3.1.6.  ZigBee automation examples

#### 3.1.7. Automatic updates

#### 3.1.8. Network infrastructure

### 3.2. Docker containers network segmentation

The following diagram shows the network segmentation of the Docker containers used by the server.

![Docker containers network segmentation](./images/docker-containers-network-diagram.png)
