# Docker-Based Appliance Creation Guide for OpenNebula Marketplace

This guide provides a step-by-step process to create OpenNebula marketplace appliances based on Docker containers, using Ubuntu 22.04 LTS as the base system.

## Prerequisites

- OpenNebula 7.0+ environment
- Packer installed for image building
- Docker knowledge
- Git repository access to marketplace-community

## Step 1: Planning Your Appliance

### 1.1 Define Your Appliance
- **Container Image**: What Docker image will you use? (e.g., `nginx:latest`, `postgres:15`, `redis:alpine`)
- **Appliance Name**: Single lowercase word without dashes (e.g., `nginx`, `postgres`, `redis`)
- **Ports**: What ports need to be exposed? (e.g., 80, 443, 5432, 6379)
- **Volumes**: What data needs to persist? (e.g., `/var/lib/postgresql/data`, `/etc/nginx/conf.d`)
- **Environment Variables**: What configuration is needed?

### 1.2 Naming Convention
- **Directory name**: Single lowercase word (e.g., `nginx`, `postgres`, `mongodb`)
- **App name**: Same as directory name for `:app:` field
- **No implementation details**: Avoid suffixes like `-server`, `-db`, `-autologin`

## Step 2: Directory Structure Creation

### 2.1 Create Appliance Directory
```bash
cd marketplace-community
mkdir -p appliances/YOURAPP
mkdir -p appliances/YOURAPP/tests
mkdir -p apps-code/community-apps/packer/YOURAPP
```

### 2.2 Required Files Structure
```
appliances/YOURAPP/
├── UUID.yaml                    # Main appliance metadata
├── metadata.yaml               # Build configuration
├── appliance.sh               # Installation script
├── README.md                  # Documentation
├── CHANGELOG.md              # Version history
├── context.yaml              # Test configuration
├── tests.yaml               # Test file list
└── tests/
    └── 00-YOURAPP_basic.rb   # Test script

apps-code/community-apps/packer/YOURAPP/
├── YOURAPP.pkr.hcl           # Packer build config
├── variables.pkr.hcl         # Packer variables
├── postprocess.sh           # Post-processing script
├── gen_context              # Context generation
└── 82-configure-context.sh  # Context configuration
```

## Step 3: Core Configuration Files

### 3.1 metadata.yaml Template
```yaml
---
:app:
  :name: YOURAPP # Replace with your app name
  :type: service
  :os:
    - Ubuntu
    - '22.04'
  :arch:
    - x86_64
  :format: qcow2
  :hypervisor:
    - KVM
  :opennebula_version:
    - '7.0'
  :opennebula_template:
    context:
      - SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]"
      - SET_HOSTNAME="$USER[SET_HOSTNAME]"
    cpu: '2'
    memory: '2048'
    disk_size: '8192'
    graphics:
      listen: 0.0.0.0
      type: vnc
    inputs_order: ''
    logo: logos/YOURAPP.png # Add your logo
    user_inputs: {}
```

### 3.2 UUID.yaml Template (Main Appliance Metadata)
```yaml
---
name: Your App Name
version: 1.0.0-1
one-apps_version: 7.0.0-0
publisher: Your Name
publisher_email: your.email@domain.com
description: |-
  Brief description of your application. This appliance provides [Your App]
  running in a Docker container on Ubuntu 22.04 LTS with VNC access and 
  SSH key authentication.

  **[Your App] features:**
  - Feature 1
  - Feature 2
  - Feature 3

  **This appliance provides:**
  - Ubuntu 22.04 LTS base operating system
  - Docker Engine CE pre-installed and configured
  - [Your App] container ready to run
  - VNC access for desktop environment
  - SSH key authentication from OpenNebula context
  - Web interface on port XXXX (if applicable)

  **Access Methods:**
  - VNC: Direct access to desktop environment
  - SSH: Key-based authentication from OpenNebula
  - Web: [Your App] interface at http://VM_IP:PORT (if applicable)

short_description: [Your App] with VNC access and SSH key auth
tags:
- yourapp
- docker
- ubuntu
- container
- vnc
- ssh-key
format: qcow2
creation_time: 1726747200
os-id: Ubuntu
os-release: '22.04'
os-arch: x86_64
hypervisor: KVM
opennebula_version: 7.0
opennebula_template:
  context:
    network: 'YES'
    ssh_public_key: $USER[SSH_PUBLIC_KEY]
    set_hostname: $USER[SET_HOSTNAME]
  cpu: '2'
  disk:
    image: $FILE[IMAGE_ID]
    image_uname: $USER[IMAGE_UNAME]
  graphics:
    listen: 0.0.0.0
    type: vnc
  memory: '2048'
  name: [Your App]
  user_inputs:
    - CONTAINER_NAME: 'M|text|Container name|yourapp-container|yourapp-container'
    - CONTAINER_PORTS: 'M|text|Container ports (format: host:container)|8080:80|8080:80'
    - CONTAINER_ENV: 'O|text|Environment variables (format: VAR1=value1,VAR2=value2)||'
    - CONTAINER_VOLUMES: 'O|text|Volume mounts (format: /host/path:/container/path)||'
  inputs_order: CONTAINER_NAME,CONTAINER_PORTS,CONTAINER_ENV,CONTAINER_VOLUMES
logo: logos/YOURAPP.png

## Step 4: Installation Script (appliance.sh)

### 4.1 Generic Docker Appliance Script Template

Create `appliances/YOURAPP/appliance.sh` with the following structure. This is a template that you need to customize for your specific Docker container:

```bash
#!/usr/bin/env bash

# [Your App] Appliance Installation Script
# CUSTOMIZE: Replace [Your App] with your application name
# CUSTOMIZE: Update DOCKER_IMAGE variable with your container image
# CUSTOMIZE: Modify default ports, environment variables, and volumes

###############################################################################
# Configuration Variables - CUSTOMIZE THESE FOR YOUR APP
###############################################################################

# Docker image to use (REQUIRED - UPDATE THIS)
DOCKER_IMAGE="your/docker-image:tag"  # e.g., "nginx:latest", "postgres:15"

# Default container configuration (CUSTOMIZE AS NEEDED)
DEFAULT_CONTAINER_NAME="yourapp-container"
DEFAULT_PORTS="8080:80"  # host:container format, comma-separated for multiple
DEFAULT_ENV_VARS=""      # VAR1=value1,VAR2=value2 format
DEFAULT_VOLUMES=""       # /host/path:/container/path format, comma-separated

# Application specific settings (CUSTOMIZE)
APP_NAME="Your App"
APP_PORT="8080"          # Main application port
WEB_INTERFACE="true"     # Set to "false" if no web interface

###############################################################################
# Standard Installation Functions - MINIMAL CHANGES NEEDED
###############################################################################

# Import common functions
source /etc/appliance/lib/functions.sh

# Main installation function
main()
{
    msg info "Starting $APP_NAME appliance installation"

    # Standard system setup
    update_system
    install_docker
    configure_system

    # Application specific setup
    setup_docker_container
    configure_vnc_access
    create_startup_scripts

    # Finalization
    create_one_service_metadata
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"
}

# System update function
update_system()
{
    msg info "Updating system packages"
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl \
        wget \
        unzip \
        vim \
        htop \
        net-tools \
        software-properties-common
}

# Docker installation function
install_docker()
{
    msg info "Installing Docker Engine CE"

    # Install Docker's official GPG key
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker service
    systemctl enable docker
    systemctl start docker

    # Add root to docker group
    usermod -aG docker root

    msg info "✓ Docker installed successfully"
}
```

### 4.2 Container Management Functions

Add these functions to your `appliance.sh` (customize the container startup script):

```bash
# Docker container setup function
setup_docker_container()
{
    msg info "Setting up $APP_NAME Docker container"

    # Pull the Docker image
    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    # Create container startup script
    create_container_script

    msg info "✓ $APP_NAME container setup completed"
}

# Create the container startup script (CUSTOMIZE THIS SECTION)
create_container_script()
{
    msg info "Creating container management script"

    # Create the startup script that will be executed on VM boot
    cat > /usr/local/bin/start-yourapp-container.sh << 'EOF'
#!/bin/bash

# [Your App] Container Startup Script
# This script reads OpenNebula context variables and starts the container

# Source context variables
if [ -f /var/lib/one-context/one_env ]; then
    source /var/lib/one-context/one_env
fi

# Set defaults if context variables are not provided
CONTAINER_NAME="${CONTAINER_NAME:-DEFAULT_CONTAINER_NAME}"
CONTAINER_PORTS="${CONTAINER_PORTS:-DEFAULT_PORTS}"
CONTAINER_ENV="${CONTAINER_ENV:-DEFAULT_ENV_VARS}"
CONTAINER_VOLUMES="${CONTAINER_VOLUMES:-DEFAULT_VOLUMES}"

# Docker image
DOCKER_IMAGE="DOCKER_IMAGE_PLACEHOLDER"

# Function to parse and format port mappings
parse_ports() {
    local ports="$1"
    local port_args=""

    if [ -n "$ports" ]; then
        IFS=',' read -ra PORT_ARRAY <<< "$ports"
        for port in "${PORT_ARRAY[@]}"; do
            port_args="$port_args -p $port"
        done
    fi

    echo "$port_args"
}

# Function to parse and format environment variables
parse_env() {
    local env_vars="$1"
    local env_args=""

    if [ -n "$env_vars" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "$env_vars"
        for env in "${ENV_ARRAY[@]}"; do
            env_args="$env_args -e $env"
        done
    fi

    echo "$env_args"
}

# Function to parse and format volume mounts
parse_volumes() {
    local volumes="$1"
    local volume_args=""

    if [ -n "$volumes" ]; then
        IFS=',' read -ra VOL_ARRAY <<< "$volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            # Create host directory if it doesn't exist
            host_path=$(echo "$vol" | cut -d':' -f1)
            mkdir -p "$host_path"
            volume_args="$volume_args -v $vol"
        done
    fi

    echo "$volume_args"
}

# Stop existing container if running
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
fi

# Parse configuration
PORT_ARGS=$(parse_ports "$CONTAINER_PORTS")
ENV_ARGS=$(parse_env "$CONTAINER_ENV")
VOLUME_ARGS=$(parse_volumes "$CONTAINER_VOLUMES")

# Start the container (CUSTOMIZE: Add any specific docker run options here)
echo "Starting $CONTAINER_NAME container..."
echo "Image: $DOCKER_IMAGE"
echo "Ports: $CONTAINER_PORTS"
echo "Environment: $CONTAINER_ENV"
echo "Volumes: $CONTAINER_VOLUMES"

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    $PORT_ARGS \
    $ENV_ARGS \
    $VOLUME_ARGS \
    "$DOCKER_IMAGE"

# CUSTOMIZE: Add any post-startup commands here
# Example: docker exec "$CONTAINER_NAME" /setup-script.sh

if [ $? -eq 0 ]; then
    echo "✓ $CONTAINER_NAME started successfully"
    docker ps --filter name="$CONTAINER_NAME"
else
    echo "✗ Failed to start $CONTAINER_NAME"
    exit 1
fi
EOF

    # Replace placeholders with actual values
    sed -i "s/DEFAULT_CONTAINER_NAME/$DEFAULT_CONTAINER_NAME/g" /usr/local/bin/start-yourapp-container.sh
    sed -i "s/DEFAULT_PORTS/$DEFAULT_PORTS/g" /usr/local/bin/start-yourapp-container.sh
    sed -i "s/DEFAULT_ENV_VARS/$DEFAULT_ENV_VARS/g" /usr/local/bin/start-yourapp-container.sh
    sed -i "s/DEFAULT_VOLUMES/$DEFAULT_VOLUMES/g" /usr/local/bin/start-yourapp-container.sh
    sed -i "s|DOCKER_IMAGE_PLACEHOLDER|$DOCKER_IMAGE|g" /usr/local/bin/start-yourapp-container.sh

    chmod +x /usr/local/bin/start-yourapp-container.sh

    msg info "✓ Container startup script created"
}
```

### 4.3 System Configuration Functions

Add these standard functions to complete your `appliance.sh`:

```bash
# VNC access configuration
configure_vnc_access()
{
    msg info "Setting up VNC access for root user"

    # Install required packages for VNC access
    msg info "Installing VNC access packages"
    apt-get update -qq
    apt-get install -y mingetty

    # Configure automatic login on tty1 (console)
    msg info "Configuring automatic console login"
    mkdir -p /etc/systemd/system/getty@tty1.service.d

    # Create override configuration for automatic login
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I $TERM
Type=idle
EOF

    # Configure automatic login on serial console (ttyS0) as well
    msg info "Configuring automatic serial console login"
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d

    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
EOF

    # Set a default password for root to enable SSH access
    msg info "Setting default password for root user (SSH access)"
    echo 'root:opennebula' | chpasswd

    # Enable the services
    systemctl enable getty@tty1.service
    systemctl enable serial-getty@ttyS0.service

    msg info "✓ VNC access configured successfully"
    msg info "  - Console (tty1): Direct login as root"
    msg info "  - Serial (ttyS0): Direct login as root"
    msg info "  - SSH access: Enabled (password: 'opennebula', key authentication)"

    return 0
}

# Create startup scripts and services
create_startup_scripts()
{
    msg info "Creating startup scripts and services"

    # Create systemd service for container startup
    cat > /etc/systemd/system/yourapp-container.service << EOF
[Unit]
Description=$APP_NAME Container Service
After=docker.service
Requires=docker.service
After=one-context.service
Wants=one-context.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/start-yourapp-container.sh
ExecStop=/usr/bin/docker stop $DEFAULT_CONTAINER_NAME
ExecStopPost=/usr/bin/docker rm $DEFAULT_CONTAINER_NAME
TimeoutStartSec=300
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service
    systemctl enable yourapp-container.service

    # Create welcome message script
    create_welcome_message

    msg info "✓ Startup scripts and services created"
}

# Create welcome message for console login
create_welcome_message()
{
    cat > /etc/profile.d/99-yourapp-welcome.sh << 'EOF'
#!/bin/bash

# Only show welcome message on interactive shells
case $- in
    *i*) ;;
      *) return;;
esac

# Welcome message
echo "=================================================="
echo "  [Your App] Appliance"
echo "=================================================="
echo "  Ubuntu 22.04 LTS with Docker pre-installed"
echo "  [Your App] container ready to use"
echo ""
echo "  Commands:"
echo "    docker ps                    - Show running containers"
echo "    docker logs CONTAINER_NAME   - View container logs"
echo "    docker exec -it CONTAINER_NAME /bin/bash - Access container shell"
echo ""
if [ "$WEB_INTERFACE" = "true" ]; then
echo "  Web Interface:"
echo "    http://VM_IP:$APP_PORT"
echo ""
fi
echo "  SSH Access: Enabled with OpenNebula context keys"
echo "  VNC Access: Available through OpenNebula"
echo "=================================================="
EOF

    chmod +x /etc/profile.d/99-yourapp-welcome.sh
}

# Standard system configuration
configure_system()
{
    msg info "Configuring system settings"

    # Configure SSH to allow root login with keys
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

    # Enable password authentication for SSH (fallback)
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # Restart SSH service
    systemctl restart ssh

    msg info "✓ System configuration completed"
}

# Create OpenNebula service metadata
create_one_service_metadata()
{
    msg info "Creating OpenNebula service metadata"

    # This function should create any necessary metadata files
    # for OpenNebula service integration

    msg info "✓ OpenNebula service metadata created"
}

# Post-installation cleanup
postinstall_cleanup()
{
    msg info "Performing post-installation cleanup"

    # Clean package cache
    apt-get autoremove -y -qq
    apt-get autoclean -qq

    # Clear logs
    find /var/log -type f -exec truncate -s 0 {} \;

    # Clear bash history
    history -c
    cat /dev/null > ~/.bash_history

    msg info "✓ Post-installation cleanup completed"
}

# Execute main function
main "$@"
```

**Key Customization Points in appliance.sh:**
1. **DOCKER_IMAGE**: Set your container image
2. **DEFAULT_PORTS**: Configure port mappings
3. **APP_NAME**: Set your application name
4. **WEB_INTERFACE**: Set to "false" if no web UI
5. **Container startup script**: Add any specific docker run options
6. **Welcome message**: Customize the console welcome text

## Step 5: Packer Configuration

### 5.1 Main Packer File (YOURAPP.pkr.hcl)

Create `apps-code/community-apps/packer/YOURAPP/YOURAPP.pkr.hcl`:

```hcl
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "YOURAPP" {
  accelerator      = "kvm"
  boot_command     = ["<enter><wait><f6><esc><wait> ", "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ", "<enter>"]
  boot_wait        = "5s"
  disk_size        = var.disk_size
  format           = "qcow2"
  headless         = var.headless
  http_directory   = var.http_directory
  iso_checksum     = var.iso_checksum
  iso_url          = var.iso_url
  memory           = var.memory
  net_device       = "virtio-net"
  output_directory = "../../appliances/${var.appliance_name}"
  qemuargs = [
    ["-cpu", "host"],
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net,netdev=net0"]
  ]
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  ssh_password     = "packer"
  ssh_timeout      = "20m"
  ssh_username     = "packer"
  vm_name          = "${var.appliance_name}.qcow2"
  vnc_bind_address = "0.0.0.0"
  vnc_port_min     = 5900
  vnc_port_max     = 6000
}

build {
  sources = ["source.qemu.YOURAPP"]

  # Update system and install basic packages
  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "../../one-apps/packer/install_context.sh",
      "../../one-apps/packer/install_opennebula_context.sh"
    ]
  }

  # Install appliance-specific components
  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "../../appliances/${var.appliance_name}/appliance.sh"
    ]
  }

  # Configure context and finalize
  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "packer/${var.appliance_name}/82-configure-context.sh",
      "packer/${var.appliance_name}/postprocess.sh"
    ]
  }
}
```

### 5.2 Variables File (variables.pkr.hcl)

Create `apps-code/community-apps/packer/YOURAPP/variables.pkr.hcl`:

```hcl
variable "appliance_name" {
  type    = string
  default = "YOURAPP"  # Replace with your app name
}

variable "disk_size" {
  type    = string
  default = "8192M"
}

variable "headless" {
  type    = bool
  default = true
}

variable "http_directory" {
  type    = string
  default = "../../one-apps/packer/http"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:5e38b55d57d94ff029719342357325ed3bda38fa80054f9330dc789cd2d43931"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04.2/ubuntu-22.04.2-live-server-amd64.iso"
}

variable "memory" {
  type    = string
  default = "2048"
}
```

### 5.3 Context Configuration (82-configure-context.sh)

Create `apps-code/community-apps/packer/YOURAPP/82-configure-context.sh`:

```bash
#!/bin/bash

# Configure OpenNebula context for [Your App] appliance

# Copy context generation script
cp packer/YOURAPP/gen_context /usr/sbin/gen_context
chmod +x /usr/sbin/gen_context

# Ensure context service is enabled
systemctl enable one-context.service

echo "Context configuration completed for [Your App] appliance"
```

### 5.4 Context Generator (gen_context)

Create `apps-code/community-apps/packer/YOURAPP/gen_context`:

```bash
#!/bin/bash

# OpenNebula context generator for [Your App] appliance

# Read context variables
if [ -f /var/lib/one-context/one_env ]; then
    source /var/lib/one-context/one_env
fi

# Set default hostname if not provided
SET_HOSTNAME=${SET_HOSTNAME:-'YourApp'}

# Generate context script
cat > /var/lib/one-context/context.sh << EOF
#!/bin/bash

# Set hostname
if [ -n "\$SET_HOSTNAME" ]; then
    hostnamectl set-hostname "\$SET_HOSTNAME"
    echo "127.0.1.1 \$SET_HOSTNAME" >> /etc/hosts
fi

# Configure SSH keys
if [ -n "\$SSH_PUBLIC_KEY" ]; then
    mkdir -p /root/.ssh
    echo "\$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
fi

# Start [Your App] container service
systemctl start yourapp-container.service

EOF

chmod +x /var/lib/one-context/context.sh
```

### 5.5 Post-processing Script (postprocess.sh)

Create `apps-code/community-apps/packer/YOURAPP/postprocess.sh`:

```bash
#!/bin/bash

# Post-processing script for [Your App] appliance

echo "Starting post-processing for [Your App] appliance..."

# Clean up temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear logs
find /var/log -type f -exec truncate -s 0 {} \;

# Clear package cache
apt-get clean
apt-get autoremove -y

# Clear bash history
history -c
cat /dev/null > ~/.bash_history

# Remove packer user
userdel -r packer 2>/dev/null || true

# Ensure services are properly configured
systemctl enable docker
systemctl enable yourapp-container.service

echo "Post-processing completed for [Your App] appliance"

## Step 6: Documentation and Testing

### 6.1 README.md Template

Create `appliances/YOURAPP/README.md`:

```markdown
# [Your App] Appliance

[Brief description of your application]. This appliance provides [Your App] running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**[Your App] capabilities:**
- Feature 1
- Feature 2
- Feature 3
- [Add your app-specific features]

**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- [Your App] container ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)
- [Add web interface info if applicable]

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name
   - Port mappings
   - Environment variables
   - Volume mounts
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: `ssh root@VM_IP` (using OpenNebula context keys)
   - Web: `http://VM_IP:PORT` (if applicable)

## Container Configuration

### Port Mappings
Format: `host_port:container_port,host_port2:container_port2`
Example: `8080:80,8443:443`

### Environment Variables
Format: `VAR1=value1,VAR2=value2`
Example: `DB_HOST=localhost,DB_PORT=5432`

### Volume Mounts
Format: `/host/path:/container/path,/host/path2:/container/path2`
Example: `/data:/app/data,/config:/app/config`

## Management Commands

```bash
# View running containers
docker ps

# View container logs
docker logs CONTAINER_NAME

# Access container shell
docker exec -it CONTAINER_NAME /bin/bash

# Restart container
systemctl restart yourapp-container.service

# View container service status
systemctl status yourapp-container.service
```

## Troubleshooting

### Container Not Starting
1. Check service status: `systemctl status yourapp-container.service`
2. Check Docker status: `systemctl status docker`
3. View service logs: `journalctl -u yourapp-container.service`
4. Check container logs: `docker logs CONTAINER_NAME`

### Network Issues
1. Verify port mappings in container configuration
2. Check firewall settings: `ufw status`
3. Verify container is listening: `docker exec CONTAINER_NAME netstat -tlnp`

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Default Ports**: [List your default ports]
- **Default Volumes**: [List any default volume mounts]
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
```

### 6.2 CHANGELOG.md Template

Create `appliances/YOURAPP/CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-1] - YYYY-MM-DD

### Added
- Initial release of [Your App] appliance
- Docker Engine CE pre-installed and configured
- [Your App] container with version X.X.X
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters through OpenNebula context
- Automatic container startup and management
- Comprehensive test suite
- [Add other initial features]

### Technical Details
- Ubuntu 22.04 LTS base system
- Docker Engine CE latest stable version
- [Your App] container image: your/image:tag
- OpenNebula context integration
- Systemd service for container management

### 6.3 Test Configuration

Create `appliances/YOURAPP/tests.yaml`:
```yaml
---
- '00-YOURAPP_basic.rb'
```

Create `appliances/YOURAPP/tests/00-YOURAPP_basic.rb`:
```ruby
require_relative '../../../lib/community/app_handler'

# [Your App] Docker Appliance Certification Tests
describe 'Appliance Certification' do
    include_context('vm_handler')

    it 'docker is installed' do
        cmd = 'which docker'
        @info[:vm].ssh(cmd).expect_success
    end

    it 'docker service is running' do
        cmd = 'systemctl is-active docker'
        start_time = Time.now
        timeout = 60

        loop do
            result = @info[:vm].ssh(cmd)
            break if result.success?

            elapsed = Time.now - start_time
            if elapsed > timeout
                fail "Docker service not running after #{timeout} seconds"
            end

            sleep 5
        end
    end

    it '[Your App] container service is enabled' do
        cmd = 'systemctl is-enabled yourapp-container.service'
        @info[:vm].ssh(cmd).expect_success
    end

    it '[Your App] container is running' do
        cmd = 'docker ps --filter name=CONTAINER_NAME --format "{{.Status}}"'
        start_time = Time.now
        timeout = 120

        loop do
            result = @info[:vm].ssh(cmd)
            if result.success? && result.stdout.include?('Up')
                break
            end

            elapsed = Time.now - start_time
            if elapsed > timeout
                fail "[Your App] container not running after #{timeout} seconds"
            end

            sleep 10
        end
    end

    it '[Your App] container is responsive' do
        # CUSTOMIZE: Add your app-specific health check
        # Example for web applications:
        # cmd = 'curl -f http://localhost:8080/health || curl -f http://localhost:8080/'
        # @info[:vm].ssh(cmd).expect_success

        # Example for database applications:
        # cmd = 'docker exec CONTAINER_NAME pg_isready' # for PostgreSQL
        # @info[:vm].ssh(cmd).expect_success

        # Generic container health check:
        cmd = 'docker exec CONTAINER_NAME echo "Container is responsive"'
        @info[:vm].ssh(cmd).expect_success
    end

    it 'container logs show no errors' do
        cmd = 'docker logs CONTAINER_NAME 2>&1 | grep -i error | wc -l'
        result = @info[:vm].ssh(cmd)
        expect(result.stdout.to_i).to eq(0)
    end
end
```

Create `appliances/YOURAPP/context.yaml`:
```yaml
---
'YOURAPP':
  :image_name: YOURAPP.qcow2
  :wait_timeout: 300
  :test_timeout: 600
```

## Step 7: Build and Test

### 7.1 Build the Appliance

```bash
# Navigate to the apps-code directory
cd marketplace-community/apps-code

# Build your appliance
make YOURAPP

# The built image will be in appliances/YOURAPP/YOURAPP.qcow2
```

### 7.2 Test the Appliance

```bash
# Run the test suite
cd marketplace-community
ruby -I lib appliances/YOURAPP/tests/00-YOURAPP_basic.rb
```

### 7.3 Manual Testing Checklist

- [ ] VM boots successfully
- [ ] VNC access works
- [ ] SSH access works with OpenNebula context keys
- [ ] Docker service is running
- [ ] Container starts automatically
- [ ] Container is accessible on configured ports
- [ ] Container persists data in configured volumes
- [ ] Container respects environment variables
- [ ] Web interface accessible (if applicable)
- [ ] Container logs show no critical errors

## Step 8: Real-World Examples

### 8.1 NGINX Web Server Example

**Configuration for NGINX appliance:**
```bash
# In appliance.sh
DOCKER_IMAGE="nginx:alpine"
DEFAULT_CONTAINER_NAME="nginx-server"
DEFAULT_PORTS="80:80,443:443"
DEFAULT_VOLUMES="/etc/nginx/conf.d:/etc/nginx/conf.d,/var/www/html:/usr/share/nginx/html"
APP_NAME="NGINX Web Server"
APP_PORT="80"
WEB_INTERFACE="true"
```

### 8.2 PostgreSQL Database Example

**Configuration for PostgreSQL appliance:**
```bash
# In appliance.sh
DOCKER_IMAGE="postgres:15"
DEFAULT_CONTAINER_NAME="postgres-db"
DEFAULT_PORTS="5432:5432"
DEFAULT_ENV_VARS="POSTGRES_PASSWORD=opennebula,POSTGRES_DB=appdb"
DEFAULT_VOLUMES="/var/lib/postgresql/data:/var/lib/postgresql/data"
APP_NAME="PostgreSQL Database"
APP_PORT="5432"
WEB_INTERFACE="false"
```

### 8.3 Redis Cache Example

**Configuration for Redis appliance:**
```bash
# In appliance.sh
DOCKER_IMAGE="redis:alpine"
DEFAULT_CONTAINER_NAME="redis-cache"
DEFAULT_PORTS="6379:6379"
DEFAULT_VOLUMES="/data:/data"
APP_NAME="Redis Cache"
APP_PORT="6379"
WEB_INTERFACE="false"
```

## Step 9: Submission Process

### 9.1 Prepare for Submission

1. **Test thoroughly** on OpenNebula 7.0+
2. **Validate all YAML files** with yamllint
3. **Run the test suite** and ensure all tests pass
4. **Create a logo** (PNG format, place in `logos/YOURAPP.png`)
5. **Review documentation** for accuracy and completeness

### 9.2 Create Pull Request

1. **Fork** the marketplace-community repository
2. **Create a branch** with clean naming: `YOURAPP-appliance`
3. **Commit your changes** with descriptive messages
4. **Push to your fork** and create a pull request
5. **Use the PR template** with proper information:
   - `:app: YOURAPP`
   - Mark as "New Appliance"
   - Provide detailed description
   - Complete the contributor checklist

### 9.3 PR Description Template

Use this template for your pull request:

```markdown
### Appliance
New appliance submission for [Your App Description].

### Appliance Name
:app: YOURAPP

### Type of Contribution
- [x] New Appliance
- [ ] Update to an Existing Appliance

### Description of Changes
This PR adds a new [Your App] appliance to the OpenNebula Community Marketplace.

**[Your App]** is [brief description]. This appliance provides:
- [Key features list]
- Docker container running on Ubuntu 22.04 LTS
- VNC and SSH access
- Configurable container parameters

### Contributor Checklist
- [x] The submission follows the Contribution Guidelines
- [x] My submission is based on the latest version of the master branch
- [x] For a new appliance, this Pull Request follows the naming convention
```

## Troubleshooting Common Issues

### Build Issues
- **Packer fails**: Check ISO URL and checksum in variables.pkr.hcl
- **Docker installation fails**: Verify internet connectivity during build
- **Container pull fails**: Check Docker image name and availability

### Runtime Issues
- **Container won't start**: Check Docker logs and service status
- **Port conflicts**: Verify port mappings don't conflict with system services
- **Permission issues**: Ensure proper volume mount permissions

### Testing Issues
- **Tests timeout**: Increase timeout values in test configuration
- **SSH connection fails**: Verify OpenNebula context key injection
- **Container health checks fail**: Customize health check commands for your app

This guide provides a complete framework for creating Docker-based OpenNebula marketplace appliances. Customize the templates according to your specific application requirements!
```
```
```
```
