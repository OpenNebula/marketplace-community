# Node-Red Appliance

Node-RED is a low-code, flow-based programming tool for wiring together devices, APIs, and services. This appliance provides Node-Red running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**Node-Red capabilities:**
  - Visual flow editor
  - Integrations with devices/APIs
  - Real-time data transformation
  - Dashboard & UI building
  - Extensible via nodes
**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- Node-Red container (nodered/node-red:latest) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)  - Web interface on port 1880

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: nodered-app
   - Port mappings: 1880:1880
   - Environment variables: 
   - Volume mounts: /data:/data
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)  - Web: Node-Red interface at http://VM_IP:1880

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `1880:1880`

### Environment Variables  
Format: `VAR1=value1,VAR2=value2`
Default: ``

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Default: `/data:/data`

## Management Commands

```bash
# View running containers
docker ps

# View container logs
docker logs nodered-app

# Access container shell
docker exec -it nodered-app /bin/bash

# Restart container
systemctl restart nodered-container.service

# View container service status
systemctl status nodered-container.service
```

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: nodered/node-red:latest
- **Default Ports**: 1880:1880
- **Default Volumes**: /data:/data
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
