# Redis Cache Appliance

Redis is an in-memory data structure store used as a database, cache, and message broker. This appliance provides Redis Cache running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**Redis Cache capabilities:**
  - In-memory data storage
  - High performance caching
  - Pub/Sub messaging
  - Data persistence
  - Atomic operations
  - Lua scripting
**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- Redis Cache container (redis:alpine) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: redis-cache
   - Port mappings: 6379:6379
   - Environment variables: 
   - Volume mounts: /data:/data
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `6379:6379`

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
docker logs redis-cache

# Access container shell
docker exec -it redis-cache /bin/bash

# Restart container
systemctl restart redis-container.service

# View container service status
systemctl status redis-container.service
```

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: redis:alpine
- **Default Ports**: 6379:6379
- **Default Volumes**: /data:/data
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
