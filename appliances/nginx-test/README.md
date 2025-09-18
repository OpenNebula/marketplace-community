# Nginx Docker Appliance

## Overview

nginx running in Docker on Ubuntu 22.04 LTS

This appliance deploys nginx:latest running in a Docker container on Ubuntu 22.04 LTS with Docker Engine CE pre-installed and configured.

## Download

The latest version can be downloaded from the OpenNebula Community Marketplace.

## Requirements

* OpenNebula version: >= 6.10
* Recommended Specs: 1vCPU, 2048MB RAM, 8GB Disk
* Network connectivity for Docker image downloads

## Quick Start

1. Download the appliance from the OpenNebula Community Marketplace
2. Adjust the VM template as desired (CPU, MEMORY, disk, network)
3. Instantiate the template
4. Access via SSH and check container status: `docker ps`

## Configuration Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `ONEAPP_DOCKER_IMAGE_PORTS` | `80:80,443:443` | Port mappings for the container |
| `ONEAPP_DOCKER_IMAGE_VOLUMES` | - | Volume mappings for persistent data |
| `ONEAPP_DOCKER_IMAGE_ENV_VARS` | - | Environment variables for the container |

## Usage Examples

```bash
# Check container status
docker ps

# View container logs
docker logs nginx-container

# Access container shell (if supported)
docker exec -it nginx-container /bin/bash
```

## Troubleshooting

### Check Docker Service Status
```bash
systemctl status docker
```

### View Container Logs
```bash
docker logs nginx-container
```
