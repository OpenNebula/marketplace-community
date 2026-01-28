# Prowler Appliance

Open-source cloud security platform for AWS, Azure, GCP, Kubernetes, and multi-cloud compliance scanning. This appliance provides Prowler running in a Docker container on Ubuntu 24.04 LTS (Minimal) with VNC access and SSH key authentication.

## Key Features

**Prowler capabilities:**
  - Cloud security assessments
  - 500+ security checks
  - Compliance frameworks (CIS
  - NIST
  - PCI-DSS
  - GDPR
  - HIPAA
  - SOC2)
  - Multi-cloud support (AWS/Azure/GCP/K8s)
  - Security reports and dashboard
**This appliance provides:**
- Ubuntu 24.04 LTS (Minimal) base operating system
- Docker Engine CE pre-installed and configured
- Prowler container (prowlercloud/prowler:latest-amd64) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)  - Web interface on port 3000:3000

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: prowler
   - Port mappings: 3000:3000,8080:8080
   - Environment variables: 
   - Volume mounts: /data:/app/output
3. **Access the VM**:
   - VNC: Direct desktop access via OpenNebula Sunstone
   - SSH: `ssh root@VM_IP` (password: opennebula)  - Web: Prowler interface at http://VM_IP:3000:3000

## Web Interface Access (SSH Port Forwarding)

If your VM is on a private network, use SSH port forwarding to access the web interface:

```bash
# From your local machine (replace with your values):
ssh -L 3000:3000:VM_IP:3000:3000 user@opennebula-host

# Then open in browser:
# http://localhost:3000:3000
# Note: Some apps like Nextcloud AIO require HTTPS:
# https://localhost:3000:3000
```

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Default: `3000:3000,8080:8080`

### Environment Variables  
Format: `VAR1=value1,VAR2=value2`
Default: ``

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Default: `/data:/app/output`

## Management Commands

```bash
# View running containers
docker ps

# View container logs
docker logs prowler

# Access container shell
docker exec -it prowler /bin/bash

# Restart container
docker restart prowler

# Stop container
docker stop prowler

# Start container
docker start prowler
```

## Technical Details

- **Base OS**: Ubuntu 24.04 LTS (Minimal)
- **Container Runtime**: Docker Engine CE
- **Container Image**: prowlercloud/prowler:latest-amd64
- **Default Ports**: 3000:3000,8080:8080
- **Default Volumes**: /data:/app/output
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
