# ZeroTrust Smart Space - A safe and private environment for you and your data

> NOTE: THIS TEXT IS A DRAFT AND IT IS STILL UNDER DEVELOPMENT. I WILL UPDATE THE REPOSITORY AS SOON I HAVE SOME TIME 🥳

This project showcases an autoconfigured home server environment that provides a powerful and secure infrastructure that leverages cutting-edge technologies to ensure security, privacy, and ease of use. It provides the user with a set of pre-configured services and applications that can be easily extended and customized to meet the user's needs.

The server adheres with the Zero Trust security model, in fact, to be able to access the services the user needs to be authenticated, authorized and the device security must be verified through automated posture checks.

The developed infrastructure has been designed to be easily extensible and customizable. In fact, a user can easily extend the server with additional services and applications without any additional configuration.

## Technical details

The server is based on five main components to provide a secure and private environment for the user data. In the following sections, each component will be described in detail to provide a better understanding of the server architecture.

The entire system leverages the [Docker](https://www.docker.com/) containerization technology to leverage application virtualization with the aim of providing a secure and isolated environment for each application.

### Six main components

#### 1. Continuous monitoring and alerting system

*Note: thanks to the provisioning feature, Grafana has out-of-the-box two configured dashboards to display data collected from Node Exporter and cAdvisor (yes, no configuration needed)*

#### Notification examples

#### 2. Log management suite

#### 3. Backup and restore suite

#### 4. Home automation system

WIP: Already implemented but not added to the project yet. The developed home automation system is based on Home Assistant and supports out-of-the-box the following kind of devices:

- ZigBee devices
- Ethernet devices
- Wi-Fi devices
- Bluetooth devices

*Note: to be able to use the ZigBee devices, the user needs to have a ZigBee USB dongle. The recommended one is the [Sonoff ZigBee 3.0 USB Dongle Plus](https://sonoff.tech/product/gateway-and-sensors/sonoff-zigbee-3-0-usb-dongle-plus-p/)*

#### ZigBee devices pairing tutorial

#### ZigBee automation examples

#### 5. Automatic updates
#### 6. Network infrastructure

