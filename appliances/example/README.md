# Overview

[Example](https://www.example.com/documentation/current/en/manual) application is an open source example application.

This appliance deploys an Example instance running on Ubuntu 24.04 with Nginx configured to serve the web interface.

## Download

The latest version of the Example appliance can be downloaded from the OpenNebula Community Marketplace:

* [Example](http://community-marketplace.opennebula.io/appliance/<UUID>)

## Requirements

* OpenNebula version: >= 6.10
* [Recommended Specs](https://www.example.com/documentation/en/manual/requirements): 2vCPU, 8GB RAM

# Release Notes

The Example appliance is based on Ubuntu 24.04 LTS (for x86-64).

| Component | Version                         |
| --------- | ------------------------------- |
| Example    | 1.0.0 |
| Nginx     | 8 |


# Quick Start

The default template will instantiate an Example instance and expose the web interface in port 8080, configuring the Nginx web server.

Steps to deploy a Single-Node instance:

1. Download the Example appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.
   ```
   $ onemarketapp export 'Example' Example --datastore default
   ```
2. Adjust the VM template as desired (i.e. CPU, MEMORY, disk, network).
3. Instantiate Example template:
   ```
   $ onetemplate instantiate Example
   ```
   This will prompt the user for the contextualization parameters.
4. Access your new Example instance on https://vm-ip-address:8080.

# Features and usage

This appliance comes with a preinstalled Example server, including the following features:

- Based on Example release 1.0.0 on Ubuntu 24.04 LTS
- Example options
- Example feature

## Contextualization
The [contextualization](https://docs.opennebula.io/7.0/product/virtual_machines_operation/guest_operating_systems/kvm_contextualization/) parameters  in the VM template control the configuration of the appliance, see the table below:

| Parameter            | Default          | Description    |
| -------------------- | ---------------- | -------------- |
| ``ONEAPP_EXAMPLE_DB_USER`` | ``exampledb`` | User for the Example database |
| ``ONEAPP_EXAMPLE_DB_PASSWORD`` |  | Password for Example database user |
