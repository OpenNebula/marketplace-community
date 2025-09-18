# Redis Docker Appliance

## Overview

redis running in Docker on Ubuntu 22.04 LTS.

This appliance deploys redis:alpine running in a Docker container on Ubuntu 22.04 LTS with Docker Engine CE pre-installed and configured.

## Quick Start

1. Download the appliance from the OpenNebula Community Marketplace
2. Instantiate the template
3. Access via SSH and check container status: `docker ps`
4. Access the service via configured ports (default: 6379:6379)

## Configuration Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `ONEAPP_DOCKER_IMAGE_PORTS` | `6379:6379` | Port mappings for the container |
| `ONEAPP_DOCKER_IMAGE_VOLUMES` | - | Volume mappings for persistent data |
| `ONEAPP_DOCKER_IMAGE_ENV_VARS` | - | Environment variables for the container |

## Usage

```bash
# Check container status
docker ps

# View container logs
docker logs redis-container

# Access container (if supported)
docker exec -it redis-container /bin/bash
```
