# Creating OpenNebula Appliances - Manual Method

**Complete control over appliance creation (30-45 minutes)**

---

## 📖 Introduction

This guide shows you how to manually create OpenNebula appliances from Docker containers. This approach gives you full control over every aspect of the appliance and is recommended for advanced users or custom requirements.

**What you'll create:**
- A VM image (QCOW2 format) with Ubuntu 22.04 + Docker
- Automatic Docker container startup on VM boot
- SSH access with password and key authentication
- Console and serial console auto-login
- OpenNebula context integration for runtime configuration

**Time required:** ~30-45 minutes for creation + 15-20 minutes for building

---

## ✅ Prerequisites

- Linux system (Ubuntu 22.04+ recommended)
- Git
- Text editor (nano, vim, or VS Code)
- Basic knowledge of bash scripting and YAML
- Packer (for building the image)
- QEMU/KVM (for building the image)

```bash
sudo apt update
sudo apt install -y git qemu-kvm qemu-utils nano
```

---

## 📁 Step 1: Create Directory Structure

```bash
# Clone the repository
git clone https://github.com/OpenNebula/marketplace-community.git
cd marketplace-community

# Create appliance directory (lowercase, no spaces)
mkdir -p appliances/myapp
cd appliances/myapp
```

---

## 📝 Step 2: Create metadata.yaml

This file configures how Packer builds your appliance.

```bash
nano metadata.yaml
```

**Template:**

```yaml
---
name: 'MyApp'
version: '1.0.0'
publisher: 'Your Name'
description: |-
  MyApp description.
  
  This appliance runs MyApp in a Docker container on Ubuntu 22.04 LTS.
  
  **Access:**
  - SSH: root@<vm-ip> (password: opennebula)
  - Console: Auto-login as root
  - Web UI: http://<vm-ip>:8080 (if applicable)
  
  **Features:**
  - Docker container with automatic startup
  - OpenNebula context integration
  - Configurable via context variables

short_description: 'MyApp - Brief one-line description'
tags:
  - 'docker'
  - 'myapp'
  - 'ubuntu'
format: 'qcow2'
os-id: 'Ubuntu'
os-release: '22.04'
os-arch: 'x86_64'
hypervisor: 'KVM'
opennebula_version: '6.0'
opennebula_template:
  context:
    network: 'YES'
    ssh_public_key: '$USER[SSH_PUBLIC_KEY]'
  cpu: '2'
  memory: '2048'
  graphics:
    listen: '0.0.0.0'
    type: 'VNC'
logo: 'myapp.png'
images:
  - name: 'myapp'
    url: ''
    type: 'OS'
    dev_prefix: 'vd'
    driver: 'qcow2'
    size: 8192
```

**Key fields to customize:**
- `name` - Display name
- `version` - Semantic version (1.0.0)
- `publisher` - Your name
- `description` - Full description with access info
- `short_description` - One-line summary
- `tags` - Searchable keywords
- `cpu` / `memory` - Default VM resources
- `size` - Disk size in MB (8192 = 8GB)

---

## 🔧 Step 3: Create appliance.sh

This is the main installation script that runs during image build. **Use the exact structure from Phoenix RTOS/Node-RED** for proven reliability.

```bash
nano appliance.sh
```

**Template:**

```bash
#!/usr/bin/env bash

# MyApp Appliance Installation Script
# Docker Image: your-docker-image:tag

set -o errexit -o pipefail

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_CONTAINER_NAME'     'configure'  'Docker container name'                    'O|text'
    'ONEAPP_CONTAINER_PORTS'    'configure'  'Docker container port mappings'           'O|text'
    'ONEAPP_CONTAINER_ENV'      'configure'  'Docker container environment variables'   'O|text'
    'ONEAPP_CONTAINER_VOLUMES'  'configure'  'Docker container volume mappings'         'O|text'
)

# Configuration - CUSTOMIZE THESE
DOCKER_IMAGE="your-docker-image:tag"
DEFAULT_CONTAINER_NAME="myapp-container"
DEFAULT_PORTS="8080:8080"
DEFAULT_ENV_VARS=""
DEFAULT_VOLUMES="/data:/data"
APP_NAME="MyApp"
APPLIANCE_NAME="myapp"

### Appliance metadata ###############################################

ONE_SERVICE_NAME='MyApp'
ONE_SERVICE_VERSION=   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='MyApp Docker Container Appliance'
ONE_SERVICE_DESCRIPTION='MyApp running in Docker container'
ONE_SERVICE_RECONFIGURABLE=true

### Appliance functions ##############################################

service_cleanup()
{
    :
}

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # Update system
    msg info "Updating system packages"
    apt-get update
    apt-get upgrade -y

    # Install Docker
    msg info "Installing Docker"
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Pull the Docker image
    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    # Configure console auto-login
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true
    apt-get install -y mingetty

    # TTY1 auto-login
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'CONSOLE_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I \$TERM
Type=idle
CONSOLE_EOF

    # Serial console auto-login
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'SERIAL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root -s %I 115200,38400,9600 vt220
SERIAL_EOF

    # Create welcome message
    cat > /etc/motd << 'MOTD_EOF'
###############################################################################
#                                                                             #
#                    Welcome to MyApp Appliance                               #
#                                                                             #
###############################################################################

Docker container: myapp-container
Access: http://<vm-ip>:8080

Useful commands:
  - docker ps                    # Check container status
  - docker logs myapp-container  # View container logs
  - docker restart myapp-container  # Restart container

MOTD_EOF

    # Set root password
    msg info "Setting root password to 'opennebula'"
    echo "root:opennebula" | chpasswd

    # Enable SSH password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

    msg info "${APP_NAME} installation completed"
}

service_configure()
{
    :
}

service_bootstrap()
{
    msg info "Starting ${APP_NAME} container"
    setup_app_container
}

setup_app_container()
{
    # Get configuration from context or use defaults
    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local container_ports="${ONEAPP_CONTAINER_PORTS:-$DEFAULT_PORTS}"
    local container_env="${ONEAPP_CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
    local container_volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

    msg info "Container configuration:"
    msg info "  Name: $container_name"
    msg info "  Ports: $container_ports"
    msg info "  Environment: $container_env"
    msg info "  Volumes: $container_volumes"

    # Stop and remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "Removing existing container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    # Parse port mappings
    local port_args=""
    if [ -n "$container_ports" ]; then
        IFS=',' read -ra PORT_ARRAY <<< "$container_ports"
        for port in "${PORT_ARRAY[@]}"; do
            port_args="$port_args -p $port"
        done
    fi

    # Parse environment variables
    local env_args=""
    if [ -n "$container_env" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "$container_env"
        for env in "${ENV_ARRAY[@]}"; do
            env_args="$env_args -e $env"
        done
    fi

    # Parse volume mounts
    local volume_args=""
    if [ -n "$container_volumes" ]; then
        IFS=',' read -ra VOL_ARRAY <<< "$container_volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            local host_path=$(echo "$vol" | cut -d':' -f1)
            mkdir -p "$host_path"
            # Set ownership to 1000:1000 (common for Docker containers)
            chown -R 1000:1000 "$host_path" 2>/dev/null || true
            volume_args="$volume_args -v $vol"
        done
    fi

    # Start container
    msg info "Starting Docker container: $container_name"
    docker run -d --name "$container_name" --restart unless-stopped $port_args $env_args $volume_args "$DOCKER_IMAGE"

    # Wait for container to start
    sleep 5

    # Verify container is running
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "${APP_NAME} container started successfully"
        msg info "Container status:"
        docker ps --filter "name=${container_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        msg error "${APP_NAME} container failed to start"
        msg error "Container logs:"
        docker logs "$container_name" 2>&1 | tail -20
        return 1
    fi
}

### Main execution ###################################################

msg info "Starting ${APP_NAME} appliance setup"

case "${1:-}" in
    install)
        service_install
        ;;
    configure)
        service_configure
        ;;
    bootstrap)
        service_bootstrap
        ;;
    *)
        echo "Usage: $0 {install|configure|bootstrap}"
        exit 1
        ;;
esac
```

**Make it executable:**

```bash
chmod +x appliance.sh
```

---

## 📄 Step 4: Create Additional Files

### README.md

```bash
nano README.md
```

```markdown
# MyApp Appliance

MyApp description and features.

## Quick Start

1. Deploy the appliance from OpenNebula Marketplace
2. Access via SSH: `ssh root@<vm-ip>` (password: opennebula)
3. Access web interface: `http://<vm-ip>:8080`

## Configuration

Configure the container via OpenNebula context variables:

- `ONEAPP_CONTAINER_NAME` - Container name (default: myapp-container)
- `ONEAPP_CONTAINER_PORTS` - Port mappings (default: 8080:8080)
- `ONEAPP_CONTAINER_ENV` - Environment variables (comma-separated)
- `ONEAPP_CONTAINER_VOLUMES` - Volume mappings (comma-separated)

## Support

For issues, visit: https://github.com/OpenNebula/marketplace-community
```

### CHANGELOG.md

```bash
nano CHANGELOG.md
```

```markdown
# Changelog

## [1.0.0] - 2025-10-02

### Added
- Initial release
- Docker container with automatic startup
- OpenNebula context integration
- SSH and console access
```

### tests/tests.yaml

```bash
mkdir -p tests
nano tests/tests.yaml
```

```yaml
---
tests:
  - name: "Container Running"
    command: "docker ps --filter name=myapp-container --format '{{.Status}}' | grep -q Up"
    expected_exit_code: 0
  
  - name: "SSH Access"
    command: "systemctl is-active ssh"
    expected_output: "active"
  
  - name: "Docker Service"
    command: "systemctl is-active docker"
    expected_output: "active"
```

---

## 🏗️ Step 5: Create Packer Configuration

```bash
cd ../../apps-code/community-apps
mkdir -p packer/myapp
cd packer/myapp
```

### myapp.pkr.hcl

```bash
nano myapp.pkr.hcl
```

```hcl
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "myapp" {
  vm_name          = "myapp"
  iso_url          = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
  iso_checksum     = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
  output_directory = "../../export"
  disk_size        = "8G"
  format           = "qcow2"
  accelerator      = "kvm"
  headless         = true
  
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "30m"
  
  boot_wait        = "5s"
  boot_command     = [
    "<esc><wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]
  
  http_directory   = "http"
  shutdown_command = "shutdown -P now"
}

build {
  sources = ["source.qemu.myapp"]
  
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y cloud-init"
    ]
  }
  
  provisioner "file" {
    source      = "../../../../appliances/myapp/appliance.sh"
    destination = "/tmp/appliance.sh"
  }
  
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/appliance.sh",
      "/tmp/appliance.sh install",
      "/tmp/appliance.sh configure"
    ]
  }
}
```

### myapp.auto.pkrvars.hcl

```bash
nano myapp.auto.pkrvars.hcl
```

```hcl
# MyApp Packer Variables
```

---

## 🎨 Step 6: Add Logo

Create a 256x256 PNG logo:

```bash
cd ../../../../logos
# Add your myapp.png file here (256x256 pixels)
```

---

## 🔨 Step 7: Build the Appliance

```bash
cd ../apps-code/community-apps
make myapp
```

**Build time:** 15-20 minutes

**Output:** `export/myapp.qcow2`

---

## 🧪 Step 8: Test Locally

```bash
cd export

# Start VM with QEMU
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -smp 2 \
  -drive file=myapp.qcow2,format=qcow2 \
  -net nic -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080 \
  -vnc :0
```

Connect via VNC to `localhost:5900` and verify:
- Console auto-login works
- Docker container is running: `docker ps`
- Application is accessible

---

## 🚀 Step 9: Deploy to OpenNebula

### Upload Image

```bash
# Copy to OpenNebula frontend
scp myapp.qcow2 root@opennebula-frontend:/var/tmp/

# SSH to frontend
ssh root@opennebula-frontend

# Create image in OpenNebula
oneimage create --name "MyApp" \
  --path /var/tmp/myapp.qcow2 \
  --type OS \
  --datastore default \
  --description "MyApp Docker Container Appliance"
```

### Create VM Template

```bash
cat > myapp-template.txt << 'EOF'
NAME = "MyApp"
CPU = "2"
MEMORY = "2048"

DISK = [
  IMAGE = "MyApp"
]

NIC = [
  NETWORK = "default",
  NETWORK_UNAME = "oneadmin"
]

GRAPHICS = [
  LISTEN = "0.0.0.0",
  TYPE = "VNC"
]

CONTEXT = [
  NETWORK = "YES",
  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]"
]

USER_INPUTS = [
  ONEAPP_CONTAINER_NAME = "O|text|Container name||myapp-container",
  ONEAPP_CONTAINER_PORTS = "O|text|Port mappings||8080:8080",
  ONEAPP_CONTAINER_ENV = "O|text|Environment variables||",
  ONEAPP_CONTAINER_VOLUMES = "O|text|Volume mappings||/data:/data"
]

INPUTS_ORDER = "ONEAPP_CONTAINER_NAME,ONEAPP_CONTAINER_PORTS,ONEAPP_CONTAINER_ENV,ONEAPP_CONTAINER_VOLUMES"
EOF

onetemplate create myapp-template.txt
```

### Instantiate VM

```bash
onetemplate instantiate "MyApp" --name "myapp-test"

# Check status
onevm list

# Get IP address
onevm show myapp-test | grep ETH0_IP
```

### Test Access

```bash
# SSH access
ssh root@<vm-ip>  # password: opennebula

# Check container
docker ps

# Check logs
docker logs myapp-container
```

---

## 📤 Step 10: Submit to Marketplace

### Create Fork and Branch

```bash
# Fork the repository on GitHub first
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/marketplace-community.git
cd marketplace-community

# Create feature branch
git checkout -b feature/add-myapp-appliance
```

### Add Your Files

```bash
git add appliances/myapp/
git add apps-code/community-apps/packer/myapp/
git add logos/myapp.png

git commit -m "Add MyApp appliance

- Docker container with automatic startup
- OpenNebula context integration
- SSH and console access
- Web interface on port 8080"
```

### Push and Create PR

```bash
git push origin feature/add-myapp-appliance
```

Go to GitHub and create a Pull Request with:

**Title:** `Add MyApp appliance`

**Description:**
```markdown
## Description

This PR adds a new appliance for MyApp, a [brief description].

## Features

- Docker container with automatic startup
- OpenNebula context integration
- Configurable via context variables:
  - Container name
  - Port mappings
  - Environment variables
  - Volume mappings

## Testing

- ✅ Built successfully with Packer
- ✅ Deployed to OpenNebula
- ✅ Container starts automatically
- ✅ SSH access works (password + keys)
- ✅ Console auto-login works
- ✅ Application accessible on configured ports

## Files Added

- `appliances/myapp/` - Appliance definition files
- `apps-code/community-apps/packer/myapp/` - Packer build configuration
- `logos/myapp.png` - Appliance logo

## Checklist

- [x] Appliance builds successfully
- [x] Appliance tested on OpenNebula
- [x] Documentation included (README.md)
- [x] Logo added (256x256 PNG)
- [x] Follows Phoenix RTOS/Node-RED structure
- [x] No sensitive information in files
```

---

## 🐛 Troubleshooting

**Problem:** appliance.sh fails during build  
**Solution:** Test script manually on Ubuntu 22.04 VM

**Problem:** Container doesn't start  
**Solution:** Check Docker logs: `docker logs container-name`

**Problem:** SSH fails  
**Solution:** Recreate VM template (OpenNebula context issue)

**Problem:** Build takes too long  
**Solution:** Use local Ubuntu ISO mirror

---

## 💡 Tips

- **Follow the pattern** - Use the Phoenix RTOS/Node-RED structure (proven in production)
- **Test locally first** - Test appliance.sh on a VM before building
- **Use logging** - Add `msg info` statements for debugging
- **Volume permissions** - Set correct ownership for non-root containers
- **Keep it simple** - Start with minimal features, add incrementally

---

## 📖 Additional Resources

- [Automatic Appliance Guide](AUTOMATIC_APPLIANCE_GUIDE.md) - For quick generation
- [OpenNebula Documentation](https://docs.opennebula.io/)
- [Docker Hub](https://hub.docker.com/)
- [Packer Documentation](https://www.packer.io/docs)
- [OpenNebula Marketplace](https://marketplace.opennebula.io/)

