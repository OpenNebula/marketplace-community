# Overview

[Zabbix](https://www.zabbix.com/documentation/current/en/manual) is an open source distributed monitoring system that monitors network, servers, virtual machines, applications, databases and more.

This appliance deploys a Zabbix instance running on Ubuntu 24.04 with Nginx configured to serve the web interface.

## Download

The latest version of the Zabbix appliance can be downloaded from the OpenNebula Community Marketplace:

* [Zabbix](http://community-marketplace.opennebula.io/appliance/d36cd66f-31ea-465e-a481-bc1de22f27d7)

## Requirements

* OpenNebula version: >= 6.10
* [Recommended Specs](https://www.zabbix.com/documentation/7.0/en/manual/installation/requirements): 2vCPU, 8GB RAM

# Release Notes

The Zabbix appliance is based on Ubuntu 24.04 LTS (for x86-64).

| Component | Version                         |
| --------- | ------------------------------- |
| Zabbix    | [7.0 LTS](https://www.zabbix.com/rn/rn7.0.17rc1) |
| Nginx     | 8 |
| PostgreSQL | 16.9 |
| PHP | 8.3 |


# Quick Start

The default template will instantiate a Zabbix instance and expose the web interface in port 8080, configuring the PostgreSQL database and the Nginx web server.

Steps to deploy a Single-Node instance:

1. Download the Zabbix appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.
   ```
   $ onemarketapp export 'Zabbix' Zabbix --datastore default
   ```
2. Adjust the VM template as desired (i.e. CPU, MEMORY, disk, network).
3. Instantiate Zabbix template:
   ```
   $ onetemplate instantiate Zabbix
   ```
   This will prompt the user for the contextualization parameters.
4. Access your new Zabbix instance on https://vm-ip-address:8080 and finish the installation in the web interface.

# Features and usage

This appliance comes with a preinstalled Zabbix server, including the following features:

- Based on Zabbix release on Ubuntu 24.04 LTS
- Option to configure the server name and exposed port
- Option to configure database settings: database name, user name and password

## Contextualization
The [contextualization](https://docs.opennebula.io/7.0/product/virtual_machines_operation/guest_operating_systems/kvm_contextualization/) parameters  in the VM template control the configuration of the service, see the table below:

| Parameter            | Default          | Description    |
| -------------------- | ---------------- | -------------- |
| ``ONEAPP_ZABBIX_DB_USER`` | ``zabbix`` | User for the Zabbix database |
| ``ONEAPP_ZABBIX_DB_PASSWORD`` |  | Password for Zabbix database user |
| ``ONEAPP_ZABBIX_DB_NAME`` | ``zabbix`` | Name for the Zabbix database |
| ``ONEAPP_ZABBIX_PORT`` | ``8080`` | Listen port for Nginx configuration |
| ``ONEAPP_ZABBIX_SERVER_NAME``   | ``example.com`` | Enable TLS configuration |
