# Nextcloud All-in-One Appliance

A self-hosted productivity platform providing file sync, collaboration, and communication tools.

## Key Features

**Nextcloud capabilities:**
- File sync and sharing across devices
- Collaborative document editing (Office suite)
- Calendar, contacts, and email
- Talk (video conferencing)
- Notes, tasks, and more

**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- Nextcloud AIO container (nextcloud/all-in-one:latest)
- Nginx reverse proxy with self-signed SSL on port 9999
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: nextcloud-aio-mastercontainer
   - Port mappings: 80:80,8080:8080,8443:8443
   - Environment variables: SKIP_DOMAIN_VALIDATION=true
   - Volume mounts: /var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)
   - Web: See "Accessing Nextcloud" section below

## Accessing Nextcloud

Nextcloud AIO runs inside the VM and requires SSH tunneling for secure access from your local machine.

### Step 1: Create SSH Tunnel

From your local machine, create an SSH tunnel to the VM:

```bash
# Replace <VM_IP> with your VM's IP address and <FRONTEND_IP> with your OpenNebula frontend IP
ssh -L 9999:<VM_IP>:9999 -L 9080:<VM_IP>:8080 root@<FRONTEND_IP>
```

### Step 2: Access Nextcloud

- **Nextcloud Web Interface**: https://localhost:9999
- **AIO Admin Interface**: https://localhost:9080

**Note**: Your browser will show a certificate warning for the self-signed SSL certificate. Click "Advanced" and "Proceed" to continue.

### Step 3: Login

The initial admin credentials are displayed in the AIO interface (https://localhost:9080).
Default username is `admin` and the password is auto-generated during setup.

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `80:80,8080:8080,8443:8443`

### Environment Variables  
Format: `VAR1=value1,VAR2=value2`
Default: ``

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Default: `/var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config`

## Management Commands

```bash
# View running containers
docker ps

# View Nextcloud container logs
docker logs nextcloud-aio-nextcloud

# View all AIO containers
docker ps --filter "name=nextcloud-aio"

# Access Nextcloud container shell
docker exec -it nextcloud-aio-nextcloud /bin/bash

# Restart all Nextcloud containers (via mastercontainer)
docker restart nextcloud-aio-mastercontainer

# Check nginx proxy status
systemctl status nginx
```

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: nextcloud/all-in-one:latest
- **Default Ports**: 80:80,8080:8080,8443:8443
- **Default Volumes**: /var/run/docker.sock:/var/run/docker.sock:ro,nextcloud_aio_mastercontainer:/mnt/docker-aio-config
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
