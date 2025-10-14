# n8n Appliance

n8n is a workflow automation tool that allows you to connect different services and automate tasks. This appliance provides n8n running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**n8n capabilities:**
  - Workflow automation
  - Visual workflow editor
  - Self-hosted
  - Extensible with custom nodes
  - REST API
  - Webhook support
**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- n8n container (n8nio/n8n:latest) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)  - Web interface on port 5678

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: n8n-container
   - Port mappings: 5678:5678
   - Environment variables: N8N_HOST=0.0.0.0,N8N_PORT=5678,N8N_PROTOCOL=http,N8N_SECURE_COOKIE=false
   - Volume mounts: /data:/home/node/.n8n
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)  - Web: n8n interface at http://VM_IP:5678

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `5678:5678`

### Environment Variables  
Format: `VAR1=value1,VAR2=value2`
Default: `N8N_HOST=0.0.0.0,N8N_PORT=5678,N8N_PROTOCOL=http,N8N_SECURE_COOKIE=false`

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Default: `/data:/home/node/.n8n`

## Management Commands

```bash
# View running containers
docker ps

# View container logs
docker logs n8n-container

# Access container shell
docker exec -it n8n-container /bin/bash

# Restart container
docker restart n8n-container

# Stop container
docker stop n8n-container

# Start container
docker start n8n-container
```

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: n8nio/n8n:latest
- **Default Ports**: 5678:5678
- **Default Volumes**: /data:/home/node/.n8n
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
