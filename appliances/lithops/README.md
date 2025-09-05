# Release Notes

Based on Ubuntu 22.04 LTS (for x86-64).

| Component | Version |
| --------- | ------- |
| Lithops   | v3.4.0  |
| Python    | 3.10.12 |
| Docker    | 5:26.1.3-1\~ubuntu.22.04~jammy |

# Overview

[Lithops](https://lithops-cloud.github.io/docs/) is a Python multi-cloud serverless computing framework. It allows to run unmodified local python code at massive scale in the main serverless computing platforms.

This appliance deploys an Ubuntu instance with preinstalled Lithops, ready to run code against the defined backends.

## Download

The latest version of Lithops appliance can be downloaded from the OpenNebula public Marketplace:

* [Service Lithops](https://community-marketplace.opennebula.io/appliance/695ab19e-23dc-11ef-a2b8-59beec9fdf86)

## Components

| Component                 | Version   |
| ------------------------- | --------- |
| Ubuntu                    | 22.04 LTS |
| Lithops                   | v3.4.0    |
| Python                    | 3.10.12   |
| Docker                    | 5:26.1.3-1\~ubuntu.22.04\~jammy |
| Contextualization package | 6.10.0    |


## Requirements

* OpenNebula version: >= 6.4
* Minimum RAM: 768MB
* Minimum storage: 3GB

# Quick Start

After downloading the appliance from Marketplace, follow this steps to have a basic Lithops instance with localhost compute and storage backends.

Steps to deploy a Lithops instance:
1. Download the Lithops appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.
   ```
   $ onemarketapp export 'Service Lithops' Lithops --datastore default
   ```

2. Adjust the VM template as desired (i.e. CPU, MEMORY, number of disks). It should look similar to this:
   ```
    CONTEXT = [
        NETWORK = "YES",
        ONEAPP_LITHOPS_BACKEND = "$ONEAPP_LITHOPS_BACKEND",
        ONEAPP_LITHOPS_STORAGE = "$ONEAPP_LITHOPS_STORAGE",
        ONEAPP_MINIO_ACCESS_KEY_ID = "$ONEAPP_MINIO_ACCESS_KEY_ID",
        ONEAPP_MINIO_BUCKETT = "$ONEAPP_MINIO_BUCKETT",
        ONEAPP_MINIO_ENDPOINT = "$ONEAPP_MINIO_ENDPOINT",
        ONEAPP_MINIO_ENDPOINT_CERT = "$ONEAPP_MINIO_ENDPOINT_CERT",
        ONEAPP_MINIO_SECRET_ACCESS_KEY = "$ONEAPP_MINIO_SECRET_ACCESS_KEY",
        SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]" ]
    CPU = "1"
    DISK = [
        IMAGE = "service-Lithops" ]
    GRAPHICS = [
        LISTEN = "0.0.0.0",
        TYPE = "VNC" ]
    HYPERVISOR = "kvm"
    INPUTS_ORDER = "ONEAPP_LITHOPS_BACKEND,ONEAPP_LITHOPS_STORAGE,ONEAPP_MINIO_ENDPOINT,ONEAPP_MINIO_ACCESS_KEY_ID,ONEAPP_MINIO_SECRET_ACCESS_KEY,ONEAPP_MINIO_BUCKETT,ONEAPP_MINIO_ENDPOINT_CERT"
    LOGO = "images/logos/lithops.png"
    MEMORY = "768"
    MEMORY_UNIT_COST = "MB"
    USER_INPUTS = [
        ONEAPP_LITHOPS_BACKEND = "O|text|Compute backend| |localhost",
        ONEAPP_LITHOPS_STORAGE = "O|text|Storage backend| |localhost",
        ONEAPP_MINIO_ACCESS_KEY_ID = "O|text|MinIO account user access key| |",
        ONEAPP_MINIO_BUCKETT = "O|text|MinIO bucket name| |",
        ONEAPP_MINIO_ENDPOINT = "O|text|MinIO endpoint URL| |",
        ONEAPP_MINIO_ENDPOINT_CERT = "O|text64|CA certificate for MinIO connection| |",
        ONEAPP_MINIO_SECRET_ACCESS_KEY = "O|text|MinIO account user secret access key| |" ]
   ```
3. Instantiate Lithops template:
   ```
   $ onetemplate instantiate Lithops
   ```
   This will prompt the user for the contextualization parameters, set the defaults for localhost compute and storage backends.
4. Attach a new NIC to the VM:
   ```
   $ onevm nic-atttach VM_ID --network VNET_ID
   ```
5. Access your new Lithops instance and check Lithops is working:
   ```
   $ onevm ssh VM_ID

   root@localhost:~# lithops hello
   ```

# Features

This appliance comes with Lithops installed globally with pip3, following Lithops [official install guide](https://lithops-cloud.github.io/docs/source/install_lithops.html), including the following features:

- Based on the latest Lithops release (v3.4.0) on Ubuntu 22.04 LTS
- Configuration file in ``/etc/lithops/config``
- Default compute and storage backend: localhost
- Supported additional storage backend: MinIO

## Contextualization
The contextualization parameters ([CONTEXT section](https://docs.opennebula.io/stable/management_and_operations)) in the VM template controls the configuration of the service, see the table below

| Parameter                          | Default       | Description                                                                                          |
| ---------------------------------- | ------------- | ---------------------------------------------------------------------------------------------------- |
| ``ONEAPP_BACKEND``                 | ``localhost`` | Lithops compute backend. Supported modes: ``localhost``                                              |
| ``ONEAPP_STORAGE``                 | ``localhost`` | Lithops storage backend. Supported modes: ``localhost``, ``minio``                                   |
| ``ONEAPP_MINIO_ENDPOINT``          |               | MinIO storage backend endpoint URL. Mandatory if ``ONEAPP_STORAGE=minio``                            |
| ``ONEAPP_MINIO_ACCESS_KEY_ID``     |               | MinIO account user access key. Mandatory if ``ONEAPP_STORAGE=minio``                                 |
| ``ONEAPP_MINIO_SECRET_ACCESS_KEY`` |               | MinIO account user secret access key. Mandatory if ``ONEAPP_STORAGE=minio``                          |
| ``ONEAPP_MINIO_BUCKET``           |               | MinIO existing bucket for Lithops. Lithops will automatically create a new one if it is not provided |
| ``ONEAPP_MINIO_ENDPOINT_CERT``     |               | CA certificate for HTTPS connection with MinIO endpoint                                              |

## MinIO Storage Backend

To configure MinIO as Storage Backend use the parameter ``ONEAPP_STORAGE=minio`` in conjunction with ``ONEAPP_MINIO_ENDPOINT``, ``ONEAPP_MINIO_ACCESS_KEY_ID`` and ``ONEAPP_MINIO_SECRET_ACCESS_KEY``. These parameters have to point to a valid and reachable MinIO server endpoint.

The parameter ``ONEAPP_MINIO_BUCKET`` is optional, and it points to a bucket in the MinIO server. If the bucket does not exist or if the parameter is empty, the MinIO server will generate a bucket automatically.

### TLS MinIO backend

When using a MinIO backend with TLS enabled, with self-signed certificates, it is necessary to provide a valid CA certificate in ``ONEAPP_MINIO_ENDPOINT_CERT``. Also note that the MinIO endpoint URL should match the certificate's subject alt name, and it may be needed to add the appropiate entry to the ``/etc/hosts`` file on the Lithops instance.
