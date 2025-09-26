# NGINX Web Server Appliance

NGINX is a high-performance web server, reverse proxy, and load balancer. This appliance provides NGINX Web Server running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**NGINX Web Server capabilities:**
  - High performance web server
  - Reverse proxy capabilities
  - Load balancing
  - SSL/TLS termination
  - Static content serving
**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- NGINX Web Server container (nginx:alpine) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)  - Web interface on port 80

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: nginx-server
   - Port mappings: 80:80,443:443
   - Environment variables: 
   - Volume mounts: /etc/nginx/conf.d:/etc/nginx/conf.d,/var/www/html:/usr/share/nginx/html
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)  - Web: NGINX Web Server interface at http://VM_IP:80

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `80:80,443:443`

### Environment Variables  
Format: `VAR1=value1,VAR2=value2`
Default: ``

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Default: `/etc/nginx/conf.d:/etc/nginx/conf.d,/var/www/html:/usr/share/nginx/html`

## Management Commands

```bash
# View running containers
docker ps

# View container logs
docker logs nginx-server

# Access container shell
docker exec -it nginx-server /bin/bash

# Restart container
systemctl restart nginx-container.service

# View container service status
systemctl status nginx-container.service
```

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: nginx:alpine
- **Default Ports**: 80:80,443:443
- **Default Volumes**: /etc/nginx/conf.d:/etc/nginx/conf.d,/var/www/html:/usr/share/nginx/html
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
