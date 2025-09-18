# Overview

[Phoenix RTOS](https://phoenix-rtos.org/) is a scalable real-time operating system for IoT. This appliance provides an easy way to run and experiment with Phoenix RTOS using Docker containerization on OpenNebula.

This appliance deploys Phoenix RTOS running in a Docker container on Ubuntu 22.04 LTS with Docker Engine CE pre-installed and configured. The Phoenix RTOS container (`pablodelarco/phoenix-rtos-one:latest`) is automatically pulled and started during the appliance configuration.

## Download

The latest version of the Phoenix RTOS Docker appliance can be downloaded from the OpenNebula Community Marketplace:

* [Phoenix RTOS Docker](http://community-marketplace.opennebula.io/appliance/a5550f73-2b03-43b5-9723-235d403e3146)

## Requirements

* OpenNebula version: >= 6.10
* Recommended Specs: 1vCPU, 2GB RAM, 8GB Disk
* Network connectivity for Docker image downloads

# Release Notes

The Phoenix RTOS Docker appliance is based on Ubuntu 22.04 LTS (for x86-64).

| Component | Version |
| --------- | ------- |
| Ubuntu | 22.04 LTS |
| Docker Engine CE | 26.1.3 |
| Docker Compose | 2.24.0+ (plugin) |
| Docker Buildx | Latest (plugin) |
| Phoenix RTOS | pablodelarco/phoenix-rtos-one:latest |

# Quick Start

The default template will instantiate a VM with Ubuntu 22.04 LTS, Docker pre-installed, and Phoenix RTOS running in a container.

Steps to deploy a Phoenix RTOS Docker instance:

1. Download the Phoenix RTOS Docker appliance from the OpenNebula Community Marketplace. This will download the VM template and the image for the OS.

   ```bash
   $ onemarketapp export 'Phoenix RTOS Docker' PhoenixRTOSDocker --datastore default
   ```

2. Adjust the VM template as desired (i.e. CPU, MEMORY, disk, network).

3. Instantiate Phoenix RTOS Docker template:
   ```bash
   $ onetemplate instantiate PhoenixRTOSDocker
   ```

   This will prompt the user for the contextualization parameters.

4. Access your new environment via SSH and check Phoenix RTOS status:
   ```bash
   $ ssh root@vm-ip-address
   $ docker ps
   $ docker logs phoenix-rtos-one
   ```

5. Access Phoenix RTOS via the configured ports (default: 8080):
   ```bash
   $ curl http://vm-ip-address:8080
   ```

# Features and Usage

This appliance comes with Docker pre-installed and Phoenix RTOS running in a container, including the following features:

- **Ubuntu 22.04 LTS** - Stable and secure base operating system
- **Docker Engine CE** - Latest stable Docker engine with specific version pinning
- **Phoenix RTOS Container** - Pre-configured Phoenix RTOS container ready to use
- **Configurable Port Mappings** - Expose Phoenix RTOS services on custom ports
- **Volume Mounting** - Persistent data storage for Phoenix RTOS
- **Environment Variables** - Custom environment configuration for Phoenix RTOS
- **Docker Compose** - Container orchestration via Docker Compose plugin
- **Docker Buildx** - Advanced build features and multi-platform support
- **Registry Authentication** - Optional configuration for private Docker registries
- **Configurable Logging** - Customizable Docker daemon logging settings
- **Security Hardened** - Proper SSH configuration and security settings

## Contextualization

The [contextualization](https://docs.opennebula.io/7.0/product/virtual_machines_operation/guest_operating_systems/kvm_contextualization/) parameters in the VM template control the configuration of Phoenix RTOS and Docker services, see the table below:

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `ONEAPP_PHOENIXRTOS_PORTS` | `8080:8080` | Port mappings for Phoenix RTOS (e.g., 8080:8080,9090:9090) |
| `ONEAPP_PHOENIXRTOS_VOLUMES` | - | Volume mappings for Phoenix RTOS (e.g., /host/data:/app/data) |
| `ONEAPP_PHOENIXRTOS_ENV_VARS` | - | Environment variables for Phoenix RTOS container (e.g., VAR1=value1,VAR2=value2) |
| `ONEAPP_PHOENIXRTOS_COMMAND` | - | Custom command to run in Phoenix RTOS container |
| `ONEAPP_DOCKER_REGISTRY_URL` | - | Custom Docker registry URL (optional) |
| `ONEAPP_DOCKER_REGISTRY_USER` | - | Docker registry username (optional) |
| `ONEAPP_DOCKER_REGISTRY_PASSWORD` | - | Docker registry password (optional) |
| `ONEAPP_DOCKER_COMPOSE_VERSION` | `2.24.0` | Docker Compose version to install |
| `ONEAPP_DOCKER_DAEMON_CONFIG` | - | Custom Docker daemon configuration (JSON) |
| `ONEAPP_ENABLE_DOCKER_BUILDX` | `yes` | Enable Docker Buildx plugin |
| `ONEAPP_DOCKER_LOG_DRIVER` | `json-file` | Docker logging driver |
| `ONEAPP_DOCKER_LOG_MAX_SIZE` | `10m` | Maximum size of log files |
| `ONEAPP_DOCKER_LOG_MAX_FILE` | `3` | Maximum number of log files |

## Docker Registry Authentication

If you need to authenticate with a private Docker registry, provide the following parameters:

```bash
ONEAPP_DOCKER_REGISTRY_URL="https://your-registry.com"
ONEAPP_DOCKER_REGISTRY_USER="your-username"
ONEAPP_DOCKER_REGISTRY_PASSWORD="your-password"
```

The appliance will automatically configure Docker to authenticate with the specified registry during the configuration phase.

## Custom Docker Daemon Configuration

You can provide a custom Docker daemon configuration in JSON format:

```bash
ONEAPP_DOCKER_DAEMON_CONFIG='{"log-driver": "syslog", "storage-driver": "overlay2", "live-restore": true}'
```

## Usage Examples

### Basic Docker Commands

```bash
# Check Docker version and info
docker --version
docker info

# Run a simple container
docker run hello-world

# Run an interactive container
docker run -it ubuntu:22.04 /bin/bash

# List running containers
docker ps

# List all containers
docker ps -a

# List images
docker images
```

### Docker Compose Example

```bash
# Create a simple docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
EOF

# Start the services
docker compose up -d

# Check status
docker compose ps

# Stop the services
docker compose down
```

## Troubleshooting

### Check Docker Service Status

```bash
systemctl status docker
```

### View Docker Logs

```bash
journalctl -u docker -f
```

### Check Docker Configuration

```bash
docker info
cat /etc/docker/daemon.json
```

### Test Docker Functionality

```bash
docker run --rm hello-world
```
