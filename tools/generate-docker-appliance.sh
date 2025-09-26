#!/bin/bash

# Ultimate OpenNebula Docker Appliance Generator
# Creates ALL files needed for a Docker appliance from a simple config file

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
🚀 Ultimate OpenNebula Docker Appliance Generator

Usage: $0 <config-file>

Creates ALL necessary files for a complete Docker-based OpenNebula appliance.

Example config file (nginx.env):
    DOCKER_IMAGE="nginx:alpine"
    APPLIANCE_NAME="nginx"
    APP_NAME="NGINX Web Server"
    PUBLISHER_NAME="Your Name"
    PUBLISHER_EMAIL="your.email@domain.com"
    APP_DESCRIPTION="NGINX is a high-performance web server and reverse proxy"
    APP_FEATURES="High performance web server,Reverse proxy,Load balancing"
    DEFAULT_CONTAINER_NAME="nginx-server"
    DEFAULT_PORTS="80:80,443:443"
    DEFAULT_ENV_VARS=""
    DEFAULT_VOLUMES="/etc/nginx/conf.d:/etc/nginx/conf.d"
    APP_PORT="80"
    WEB_INTERFACE="true"

This will generate:
✅ All appliance files (metadata, appliance.sh, README, CHANGELOG)
✅ All Packer configuration files
✅ All test files
✅ Complete directory structure
✅ Ready-to-build appliance

EOF
}

if [ $# -ne 1 ]; then show_usage; exit 1; fi

CONFIG_FILE="$1"
if [ ! -f "$CONFIG_FILE" ]; then print_error "Config file '$CONFIG_FILE' not found!"; exit 1; fi

print_info "🚀 Loading configuration from $CONFIG_FILE"
source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=("DOCKER_IMAGE" "APPLIANCE_NAME" "APP_NAME" "PUBLISHER_NAME" "PUBLISHER_EMAIL")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then print_error "Required variable $var is not set"; exit 1; fi
done

# Set defaults
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-${APPLIANCE_NAME}-container}"
DEFAULT_PORTS="${DEFAULT_PORTS:-8080:80}"
DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS:-}"
DEFAULT_VOLUMES="${DEFAULT_VOLUMES:-}"
APP_PORT="${APP_PORT:-8080}"
WEB_INTERFACE="${WEB_INTERFACE:-true}"
APP_DESCRIPTION="${APP_DESCRIPTION:-Docker-based appliance for ${APP_NAME}}"
APP_FEATURES="${APP_FEATURES:-Containerized application,Easy deployment,Configurable parameters}"

# Validate appliance name
if [[ ! "$APPLIANCE_NAME" =~ ^[a-z][a-z0-9]*$ ]]; then
    print_error "APPLIANCE_NAME must be a single lowercase word"; exit 1
fi

print_info "🎯 Generating complete appliance: $APPLIANCE_NAME ($APP_NAME)"

# Create directories (relative to repository root, not tools directory)
print_info "📁 Creating directory structure..."
mkdir -p "../appliances/$APPLIANCE_NAME/tests"
mkdir -p "../apps-code/community-apps/packer/$APPLIANCE_NAME"

APPLIANCE_UUID=$(uuidgen)
CREATION_TIME=$(date +%s)
CURRENT_DATE=$(date +%Y-%m-%d)

print_success "Directory structure created"

# Generate metadata.yaml
print_info "📝 Generating metadata.yaml..."
cat > "../appliances/$APPLIANCE_NAME/metadata.yaml" << EOF
---
:app:
  :name: $APPLIANCE_NAME
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
      - SSH_PUBLIC_KEY="\$USER[SSH_PUBLIC_KEY]"
      - SET_HOSTNAME="\$USER[SET_HOSTNAME]"
    cpu: '2'
    memory: '2048'
    disk_size: '8192'
    graphics:
      listen: 0.0.0.0
      type: vnc
    inputs_order: 'CONTAINER_NAME,CONTAINER_PORTS,CONTAINER_ENV,CONTAINER_VOLUMES'
    logo: logos/$APPLIANCE_NAME.png
    user_inputs:
      CONTAINER_NAME: 'M|text|Container name|$DEFAULT_CONTAINER_NAME|$DEFAULT_CONTAINER_NAME'
      CONTAINER_PORTS: 'M|text|Container ports (format: host:container)|$DEFAULT_PORTS|$DEFAULT_PORTS'
      CONTAINER_ENV: 'O|text|Environment variables (format: VAR1=value1,VAR2=value2)|$DEFAULT_ENV_VARS|'
      CONTAINER_VOLUMES: 'O|text|Volume mounts (format: /host/path:/container/path)|$DEFAULT_VOLUMES|'
EOF

# Generate UUID.yaml (main appliance metadata)
print_info "📝 Generating ${APPLIANCE_UUID}.yaml..."
IFS=',' read -ra FEATURES_ARRAY <<< "$APP_FEATURES"
FEATURES_YAML=""
for feature in "${FEATURES_ARRAY[@]}"; do
    FEATURES_YAML="$FEATURES_YAML  - $(echo "$feature" | xargs)\n"
done

if [ "$WEB_INTERFACE" = "true" ]; then
    WEB_ACCESS="  - Web: $APP_NAME interface at http://VM_IP:$APP_PORT"
    WEB_FEATURE="  - Web interface on port $APP_PORT"
else
    WEB_ACCESS=""
    WEB_FEATURE=""
fi

cat > "../appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml" << EOF
---
name: $APP_NAME
version: 1.0.0-1
one-apps_version: 7.0.0-0
publisher: $PUBLISHER_NAME
publisher_email: $PUBLISHER_EMAIL
description: |-
  $APP_DESCRIPTION. This appliance provides $APP_NAME
  running in a Docker container on Ubuntu 22.04 LTS with VNC access and 
  SSH key authentication.

  **$APP_NAME features:**
$(echo -e "$FEATURES_YAML")
  **This appliance provides:**
  - Ubuntu 22.04 LTS base operating system
  - Docker Engine CE pre-installed and configured
  - $APP_NAME container ($DOCKER_IMAGE) ready to run
  - VNC access for desktop environment
  - SSH key authentication from OpenNebula context$WEB_FEATURE
  - Configurable container parameters (ports, volumes, environment variables)

  **Access Methods:**
  - VNC: Direct access to desktop environment
  - SSH: Key-based authentication from OpenNebula$WEB_ACCESS

short_description: $APP_NAME with VNC access and SSH key auth
tags:
- $APPLIANCE_NAME
- docker
- ubuntu
- container
- vnc
- ssh-key
format: qcow2
creation_time: $CREATION_TIME
os-id: Ubuntu
os-release: '22.04'
os-arch: x86_64
hypervisor: KVM
opennebula_version: 7.0
opennebula_template:
  context:
    network: 'YES'
    ssh_public_key: \$USER[SSH_PUBLIC_KEY]
    set_hostname: \$USER[SET_HOSTNAME]
  cpu: '2'
  disk:
    image: \$FILE[IMAGE_ID]
    image_uname: \$USER[IMAGE_UNAME]
  graphics:
    listen: 0.0.0.0
    type: vnc
  memory: '2048'
  name: $APP_NAME
  user_inputs:
    - CONTAINER_NAME: 'M|text|Container name|$DEFAULT_CONTAINER_NAME|$DEFAULT_CONTAINER_NAME'
    - CONTAINER_PORTS: 'M|text|Container ports (format: host:container)|$DEFAULT_PORTS|$DEFAULT_PORTS'
    - CONTAINER_ENV: 'O|text|Environment variables (format: VAR1=value1,VAR2=value2)|$DEFAULT_ENV_VARS|'
    - CONTAINER_VOLUMES: 'O|text|Volume mounts (format: /host/path:/container/path)|$DEFAULT_VOLUMES|'
  inputs_order: CONTAINER_NAME,CONTAINER_PORTS,CONTAINER_ENV,CONTAINER_VOLUMES
logo: logos/$APPLIANCE_NAME.png
EOF

print_success "Metadata files generated"

# Generate README.md
print_info "📝 Generating README.md..."
cat > "../appliances/$APPLIANCE_NAME/README.md" << EOF
# $APP_NAME Appliance

$APP_DESCRIPTION. This appliance provides $APP_NAME running in a Docker container on Ubuntu 22.04 LTS with VNC access and SSH key authentication.

## Key Features

**$APP_NAME capabilities:**
$(echo -e "$FEATURES_YAML")
**This appliance provides:**
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- $APP_NAME container ($DOCKER_IMAGE) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)$WEB_FEATURE

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: $DEFAULT_CONTAINER_NAME
   - Port mappings: $DEFAULT_PORTS
   - Environment variables: $DEFAULT_ENV_VARS
   - Volume mounts: $DEFAULT_VOLUMES
3. **Access the VM**:
   - VNC: Direct desktop access
   - SSH: \`ssh root@VM_IP\` (using OpenNebula context keys)$WEB_ACCESS

## Container Configuration

### Port Mappings
Format: \`host_port:container_port,host_port2:container_port2\`
Default: \`$DEFAULT_PORTS\`

### Environment Variables  
Format: \`VAR1=value1,VAR2=value2\`
Default: \`$DEFAULT_ENV_VARS\`

### Volume Mounts
Format: \`/host/path:/container/path,/host/path2:/container/path2\`
Default: \`$DEFAULT_VOLUMES\`

## Management Commands

\`\`\`bash
# View running containers
docker ps

# View container logs
docker logs $DEFAULT_CONTAINER_NAME

# Access container shell
docker exec -it $DEFAULT_CONTAINER_NAME /bin/bash

# Restart container
systemctl restart $APPLIANCE_NAME-container.service

# View container service status
systemctl status $APPLIANCE_NAME-container.service
\`\`\`

## Technical Details

- **Base OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine CE
- **Container Image**: $DOCKER_IMAGE
- **Default Ports**: $DEFAULT_PORTS
- **Default Volumes**: $DEFAULT_VOLUMES
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
EOF

print_success "README.md generated"

# Generate appliance.sh installation script with user's Docker configuration
print_info "📝 Generating appliance.sh installation script..."
cat > "../appliances/$APPLIANCE_NAME/appliance.sh" << EOF
#!/usr/bin/env bash

# $APP_NAME Appliance Installation Script
# Auto-generated by OpenNebula Docker Appliance Generator
# Docker Image: $DOCKER_IMAGE

exec 1>&2
set -eux -o pipefail

export DEBIAN_FRONTEND=noninteractive

# Configuration from user input
DOCKER_IMAGE="$DOCKER_IMAGE"
DEFAULT_CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
DEFAULT_PORTS="$DEFAULT_PORTS"
DEFAULT_ENV_VARS="$DEFAULT_ENV_VARS"
DEFAULT_VOLUMES="$DEFAULT_VOLUMES"
APP_NAME="$APP_NAME"

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Pull the user's Docker image
echo "Pulling Docker image: \$DOCKER_IMAGE"
docker pull "\$DOCKER_IMAGE"

# Create container startup script
cat > /usr/local/bin/start-$APPLIANCE_NAME-container.sh << 'CONTAINER_SCRIPT'
#!/bin/bash

# Load OpenNebula context variables if available
if [ -f /var/lib/one-context/one_env ]; then
    source /var/lib/one-context/one_env
fi

# Use context variables or defaults
CONTAINER_NAME="\${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
CONTAINER_PORTS="\${CONTAINER_PORTS:-$DEFAULT_PORTS}"
CONTAINER_ENV="\${CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
CONTAINER_VOLUMES="\${CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

# Parse port mappings
parse_ports() {
    local ports="\$1"
    local port_args=""
    if [ -n "\$ports" ]; then
        IFS=',' read -ra PORT_ARRAY <<< "\$ports"
        for port in "\${PORT_ARRAY[@]}"; do
            port_args="\$port_args -p \$port"
        done
    fi
    echo "\$port_args"
}

# Parse environment variables
parse_env() {
    local env_vars="\$1"
    local env_args=""
    if [ -n "\$env_vars" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "\$env_vars"
        for env in "\${ENV_ARRAY[@]}"; do
            env_args="\$env_args -e \$env"
        done
    fi
    echo "\$env_args"
}

# Parse volume mounts
parse_volumes() {
    local volumes="\$1"
    local volume_args=""
    if [ -n "\$volumes" ]; then
        IFS=',' read -ra VOL_ARRAY <<< "\$volumes"
        for vol in "\${VOL_ARRAY[@]}"; do
            host_path=\$(echo "\$vol" | cut -d':' -f1)
            mkdir -p "\$host_path"
            volume_args="\$volume_args -v \$vol"
        done
    fi
    echo "\$volume_args"
}

# Stop existing container if running
if docker ps -q -f name="\$CONTAINER_NAME" | grep -q .; then
    echo "Stopping existing container: \$CONTAINER_NAME"
    docker stop "\$CONTAINER_NAME"
    docker rm "\$CONTAINER_NAME"
fi

# Build docker run command
PORT_ARGS=\$(parse_ports "\$CONTAINER_PORTS")
ENV_ARGS=\$(parse_env "\$CONTAINER_ENV")
VOLUME_ARGS=\$(parse_volumes "\$CONTAINER_VOLUMES")

echo "Starting \$CONTAINER_NAME container..."
docker run -d \\
    --name "\$CONTAINER_NAME" \\
    --restart unless-stopped \\
    \$PORT_ARGS \\
    \$ENV_ARGS \\
    \$VOLUME_ARGS \\
    "$DOCKER_IMAGE"

if [ \$? -eq 0 ]; then
    echo "✓ \$CONTAINER_NAME started successfully"
    docker ps --filter name="\$CONTAINER_NAME"
else
    echo "✗ Failed to start \$CONTAINER_NAME"
    exit 1
fi
CONTAINER_SCRIPT

chmod +x /usr/local/bin/start-$APPLIANCE_NAME-container.sh

# Create systemd service for the container
cat > /etc/systemd/system/$APPLIANCE_NAME-container.service << 'SERVICE_EOF'
[Unit]
Description=$APP_NAME Container Service
After=docker.service
Requires=docker.service
After=one-context.service
Wants=one-context.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/start-$APPLIANCE_NAME-container.sh
ExecStop=/usr/bin/docker stop $DEFAULT_CONTAINER_NAME
ExecStopPost=/usr/bin/docker rm $DEFAULT_CONTAINER_NAME
TimeoutStartSec=300
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl enable $APPLIANCE_NAME-container.service

# Configure VNC access
apt-get install -y ubuntu-desktop-minimal tightvncserver

# Configure auto-login
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'VNC_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I \$TERM
Type=idle
VNC_EOF

# Set root password for VNC
echo 'root:opennebula' | chpasswd

# Create welcome message
cat > /etc/profile.d/99-$APPLIANCE_NAME-welcome.sh << 'WELCOME_EOF'
#!/bin/bash
case \$- in
    *i*) ;;
      *) return;;
esac

echo "=================================================="
echo "  $APP_NAME Appliance"
echo "=================================================="
echo "  Docker Image: $DOCKER_IMAGE"
echo "  Container: $DEFAULT_CONTAINER_NAME"
echo "  Ports: $DEFAULT_PORTS"
echo ""
echo "  Commands:"
echo "    docker ps                    - Show running containers"
echo "    docker logs $DEFAULT_CONTAINER_NAME   - View container logs"
echo "    docker exec -it $DEFAULT_CONTAINER_NAME /bin/bash - Access container"
echo ""
EOF

if [ "$WEB_INTERFACE" = "true" ]; then
    cat >> "../appliances/$APPLIANCE_NAME/appliance.sh" << EOF
echo "  Web Interface: http://VM_IP:$APP_PORT"
echo ""
EOF
fi

cat >> "../appliances/$APPLIANCE_NAME/appliance.sh" << 'EOF'
echo "  SSH Access: Enabled with OpenNebula context keys"
echo "  VNC Access: Available through OpenNebula"
echo "=================================================="
WELCOME_EOF

chmod +x /etc/profile.d/99-$APPLIANCE_NAME-welcome.sh

# Clean up
apt-get autoremove -y
apt-get autoclean
find /var/log -type f -exec truncate -s 0 {} \;

sync
EOF

chmod +x "../appliances/$APPLIANCE_NAME/appliance.sh"
print_success "appliance.sh generated"

# Generate basic Packer files
print_info "📝 Generating Packer configuration files..."

# Generate variables.pkr.hcl
cat > "../apps-code/community-apps/packer/$APPLIANCE_NAME/variables.pkr.hcl" << 'EOF'
variable "appliance_name" {
  type = string
}

variable "version" {
  type = string
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type = bool
  default = true
}

variable "arch" {
  type = string
  default = "x86_64"
}
EOF

# Generate main .pkr.hcl file
cat > "../apps-code/community-apps/packer/$APPLIANCE_NAME/$APPLIANCE_NAME.pkr.hcl" << EOF
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "$APPLIANCE_NAME" {
  accelerator      = "kvm"
  boot_command     = ["<enter><wait><f6><esc><wait> ", "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ", "--- <enter>"]
  boot_wait        = "5s"
  disk_size        = "8192M"
  format           = "qcow2"
  headless         = var.headless
  http_directory   = var.input_dir
  iso_checksum     = "file:https://releases.ubuntu.com/jammy/SHA256SUMS"
  iso_url          = "https://releases.ubuntu.com/jammy/ubuntu-22.04.4-live-server-amd64.iso"
  memory           = 2048
  net_device       = "virtio-net"
  output_directory = var.output_dir
  qemuargs         = [["-cpu", "host"]]
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  ssh_password     = "packer"
  ssh_timeout     = "60m"
  ssh_username     = "packer"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.$APPLIANCE_NAME"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "../one-apps/packer/10-upgrade-distro.sh",
      "../one-apps/packer/11-update-grub.sh",
      "../one-apps/packer/80-install-context.sh",
      "../one-apps/packer/81-configure-ssh.sh",
      "82-configure-context.sh",
      "../one-apps/packer/90-install-$APPLIANCE_NAME-appliance.sh",
      "../one-apps/packer/98-collect-garbage.sh"
    ]
  }

  post-processor "shell-local" {
    script = "postprocess.sh"
    environment_vars = [
      "OUTPUT_DIR=\${var.output_dir}",
      "APPLIANCE_NAME=\${var.appliance_name}"
    ]
  }
}
EOF

# Generate 82-configure-context.sh
cat > "../apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh" << 'EOF'
#!/usr/bin/env bash

# Configure OpenNebula context for the appliance

exec 1>&2
set -eux -o pipefail

export DEBIAN_FRONTEND=noninteractive

# Install context packages if not already installed
if ! dpkg -l | grep -q one-context; then
    wget -q -O- https://downloads.opennebula.io/repo/repo2.key | apt-key add -
    echo "deb https://downloads.opennebula.io/repo/6.8/Ubuntu/22.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list
    apt-get update
    apt-get install -y opennebula-context
fi

# Enable context service
systemctl enable one-context.service

sync
EOF

# Generate gen_context
cat > "../apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context" << 'EOF'
#!/bin/bash

# Generate context ISO for the appliance
# This script is called during the build process

CONTEXT_DIR="context"
mkdir -p "$CONTEXT_DIR"

# Create user-data for cloud-init
cat > "$CONTEXT_DIR/user-data" << 'USERDATA'
#cloud-config
users:
  - name: packer
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $6$rounds=4096$saltsalt$L9tjczoIVjNaoOmeyjQjqoTs7KM6N.UVBczRLz9IH8OvZY3P62k/9ZQToD3/wYX0EleVLjeJR.oP/4E.X/qkU1
USERDATA

# Create meta-data
cat > "$CONTEXT_DIR/meta-data" << 'METADATA'
instance-id: packer-build
local-hostname: packer-build
METADATA

# Create context ISO
genisoimage -output context.iso -volid cidata -joliet -rock "$CONTEXT_DIR"
EOF

# Generate postprocess.sh
cat > "../apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh" << 'EOF'
#!/bin/bash

# Post-processing script for the appliance

set -e

echo "Post-processing appliance..."

# Add any post-processing steps here
# For example: image optimization, cleanup, etc.

echo "Post-processing completed"
EOF

chmod +x "../apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
chmod +x "../apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
chmod +x "../apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"

# Generate additional required files
print_info "📝 Generating additional required files..."

# Generate CHANGELOG.md
cat > "../appliances/$APPLIANCE_NAME/CHANGELOG.md" << EOF
# Changelog

All notable changes to the $APP_NAME appliance will be documented in this file.

## [1.0.0-1] - $CURRENT_DATE

### Added
- Initial release of $APP_NAME appliance
- Docker container: $DOCKER_IMAGE
- VNC desktop access
- SSH key authentication
- OpenNebula context integration
- Configurable container parameters
EOF

# Generate tests.yaml
cat > "../appliances/$APPLIANCE_NAME/tests.yaml" << EOF
---
- 00-$APPLIANCE_NAME\_basic.rb
EOF

# Generate basic test file
cat > "../appliances/$APPLIANCE_NAME/tests/00-${APPLIANCE_NAME}_basic.rb" << EOF
# Basic test for $APP_NAME appliance

require_relative '../../../lib/tests'

class Test${APPLIANCE_NAME^} < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_container_service_enabled
    assert_cmd('systemctl is-enabled $APPLIANCE_NAME-container.service')
  end

  def test_image_pulled
    assert_cmd("docker images | grep '$DOCKER_IMAGE'")
  end
end
EOF

# Generate context.yaml for testing
cat > "../appliances/$APPLIANCE_NAME/context.yaml" << EOF
---
CONTAINER_NAME: $DEFAULT_CONTAINER_NAME
CONTAINER_PORTS: $DEFAULT_PORTS
CONTAINER_ENV: $DEFAULT_ENV_VARS
CONTAINER_VOLUMES: $DEFAULT_VOLUMES
EOF

print_success "Additional files generated"

print_success "Packer configuration files generated"

print_info "🎉 Appliance '$APPLIANCE_NAME' generated successfully!"
print_info ""
print_info "📁 Files created:"
print_info "  ✅ appliances/$APPLIANCE_NAME/metadata.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/README.md"
print_info "  ✅ appliances/$APPLIANCE_NAME/appliance.sh (with your Docker config)"
print_info "  ✅ appliances/$APPLIANCE_NAME/CHANGELOG.md"
print_info "  ✅ appliances/$APPLIANCE_NAME/tests.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/context.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/tests/00-${APPLIANCE_NAME}_basic.rb"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/*.pkr.hcl"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"
print_info ""
print_info "🚀 Next steps:"
print_info "  1. Add $APPLIANCE_NAME to apps-code/community-apps/Makefile.config SERVICES list"
print_info "  2. Add logo: logos/$APPLIANCE_NAME.png"
print_info "  3. Build: cd apps-code/community-apps && make $APPLIANCE_NAME"
print_info "  4. Test the appliance"
