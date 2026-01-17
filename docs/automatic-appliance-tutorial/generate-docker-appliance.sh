#!/bin/bash

# Ultimate OpenNebula Docker Appliance Generator
# Creates ALL files needed for a Docker appliance from a simple config file

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
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

# Determine repository root (go up two levels from docs/automatic-appliance-tutorial/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create directories (absolute paths from repository root)
print_info "📁 Creating directory structure..."
mkdir -p "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests"
mkdir -p "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME"

APPLIANCE_UUID=$(uuidgen)
CREATION_TIME=$(date +%s)
CURRENT_DATE=$(date +%Y-%m-%d)

print_success "Directory structure created"

# Generate metadata.yaml
print_info "📝 Generating metadata.yaml..."
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/metadata.yaml" << EOF
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

cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml" << EOF
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
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/README.md" << EOF
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
docker restart $DEFAULT_CONTAINER_NAME

# Stop container
docker stop $DEFAULT_CONTAINER_NAME

# Start container
docker start $DEFAULT_CONTAINER_NAME
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

# Generate appliance.sh installation script with simplified Phoenix RTOS/Node-RED structure
print_info "📝 Generating appliance.sh installation script (simplified structure)..."
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh" << APPLIANCE_HEADER
#!/usr/bin/env bash

# $APP_NAME Appliance Installation Script
# Auto-generated by OpenNebula Docker Appliance Generator
# Docker Image: $DOCKER_IMAGE

set -o errexit -o pipefail

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_CONTAINER_NAME'     'configure'  'Docker container name'                    'O|text'
    'ONEAPP_CONTAINER_PORTS'    'configure'  'Docker container port mappings'           'O|text'
    'ONEAPP_CONTAINER_ENV'      'configure'  'Docker container environment variables'   'O|text'
    'ONEAPP_CONTAINER_VOLUMES'  'configure'  'Docker container volume mappings'         'O|text'
)

# Configuration from user input
DOCKER_IMAGE="$DOCKER_IMAGE"
DEFAULT_CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
DEFAULT_PORTS="$DEFAULT_PORTS"
DEFAULT_ENV_VARS="$DEFAULT_ENV_VARS"
DEFAULT_VOLUMES="$DEFAULT_VOLUMES"
APP_NAME="$APP_NAME"
APPLIANCE_NAME="$APPLIANCE_NAME"

### Appliance metadata ###############################################

ONE_SERVICE_NAME='$APP_NAME'
ONE_SERVICE_VERSION=   #latest
ONE_SERVICE_BUILD=\$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='$APP_NAME Docker Container Appliance'
ONE_SERVICE_DESCRIPTION='$APP_NAME running in Docker container'
ONE_SERVICE_RECONFIGURABLE=true
APPLIANCE_HEADER

# Now append the rest with quoted heredoc to avoid escaping
cat >> "$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh" << 'APPLIANCE_BODY'

### Appliance functions ##############################################

service_cleanup()
{
    :
}

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install Docker
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

    # Configure auto-login on console
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'CONSOLE_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I \\$TERM
Type=idle
CONSOLE_EOF

    # Configure serial console and set root password
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'SERIAL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
SERIAL_EOF

    echo 'root:opennebula' | chpasswd
    systemctl enable getty@tty1.service serial-getty@ttyS0.service

    # Create welcome message
    cat > /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh << WELCOME_EOF
#!/bin/bash
case \\\$- in
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
echo "  Access Methods:"
echo "    SSH: Enabled (password: 'opennebula' + context keys)"
echo "    Console: Auto-login as root (via OpenNebula console)"
echo "    Serial: Auto-login as root (via serial console)"
echo "=================================================="
WELCOME_EOF

    chmod +x /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh

    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    find /var/log -type f -exec truncate -s 0 {} \;

    sync

    return 0
}

service_configure()
{
    msg info "Verifying Docker is running"

    if ! systemctl is-active --quiet docker; then
        msg error "Docker is not running"
        return 1
    fi

    msg info "Docker is running"
    return 0
}

service_bootstrap()
{
    msg info "Starting $APP_NAME service bootstrap"

    # Setup and start the container
    setup_app_container

    return $?
}

# Setup container function
setup_app_container()
{
    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local container_ports="${ONEAPP_CONTAINER_PORTS:-$DEFAULT_PORTS}"
    local container_env="${ONEAPP_CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
    local container_volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

    msg info "Setting up $APP_NAME container: $container_name"

    # Stop and remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "Stopping existing container: $container_name"
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
            # Only create directory if it doesn't exist and is not a socket/device file
            if [ ! -e "$host_path" ]; then
                mkdir -p "$host_path"
                # Set ownership to 1000:1000 (common for Docker containers)
                chown -R 1000:1000 "$host_path" 2>/dev/null || true
            fi
            volume_args="$volume_args -v $vol"
        done
    fi

    # Start the container
    msg info "Starting $APP_NAME container with:"
    msg info "  Ports: $container_ports"
    msg info "  Environment: ${container_env:-none}"
    msg info "  Volumes: $container_volumes"

    docker run -d --name "$container_name" --restart unless-stopped $port_args $env_args $volume_args "$DOCKER_IMAGE"

    if [ $? -eq 0 ]; then
        msg info "$APP_NAME container started successfully"
        docker ps --filter name="$container_name"
        return 0
    else
        msg error "Failed to start $APP_NAME container"
        return 1
    fi
}
APPLIANCE_BODY

chmod +x "$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh"
print_success "appliance.sh generated (simplified Phoenix RTOS/Node-RED structure)"

# Generate basic Packer files
print_info "📝 Generating Packer configuration files..."

# Generate variables.pkr.hcl
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/variables.pkr.hcl" << 'EOF'
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
EOF

# Create symlink to common.pkr.hcl (like other appliances)
ln -sf "../../../one-apps/packer/common.pkr.hcl" "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/common.pkr.hcl"

# Generate main .pkr.hcl file
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/$APPLIANCE_NAME.pkr.hcl" << EOF
source "null" "null" { communicator = "none" }

# Prior to setting up the appliance, the context packages need to be generated first
build {
  sources = ["source.null.null"]

  provisioner "shell-local" {
    inline = [
      "mkdir -p \${var.input_dir}/context",
      "\${var.input_dir}/gen_context > \${var.input_dir}/context/context.sh",
      "mkisofs -o \${var.input_dir}/\${var.appliance_name}-context.iso -V CONTEXT -J -R \${var.input_dir}/context",
    ]
  }
}

# Build VM image
source "qemu" "$APPLIANCE_NAME" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/ubuntu2204min.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "8000"

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-cdrom", "\${var.input_dir}/\${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout     = "900s"
  shutdown_command = "poweroff"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.$APPLIANCE_NAME"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["\${var.input_dir}/81-configure-ssh.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }
  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }
  provisioner "file" {
    sources     = ["../../appliances/$APPLIANCE_NAME/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  provisioner "shell" {
    scripts = ["\${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=\${var.output_dir}",
      "APPLIANCE_NAME=\${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
EOF

# Generate 81-configure-ssh.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh" << 'EOF'
#!/usr/bin/env bash

# Configures critical settings for OpenSSH server.

exec 1>&2
set -eux -o pipefail

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PasswordAuthentication no" }
/^[#\s]*PasswordAuthentication\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PermitRootLogin without-password" }
/^[#\s]*PermitRootLogin\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "UseDNS no" }
/^[#\s]*UseDNS\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

sync
EOF

# Generate 82-configure-context.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh" << 'EOF'
#!/usr/bin/env bash

# Configure and enable service context.

exec 1>&2
set -eux -o pipefail

mv /etc/one-appliance/net-90-service-appliance /etc/one-context.d/
mv /etc/one-appliance/net-99-report-ready      /etc/one-context.d/

chown root:root /etc/one-context.d/*
chmod u=rwx,go=rx /etc/one-context.d/*

sync
EOF

# Generate gen_context (copy from example appliance)
cp "$REPO_ROOT/apps-code/community-apps/packer/example/gen_context" "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"

# Generate postprocess.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh" << 'EOF'
#!/bin/bash

# Post-processing script for the appliance

set -e

echo "Post-processing appliance..."

# Add any post-processing steps here
# For example: image optimization, cleanup, etc.

echo "Post-processing completed"
EOF

chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"

# Generate additional required files
print_info "📝 Generating additional required files..."

# Generate CHANGELOG.md
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/CHANGELOG.md" << EOF
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
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests.yaml" << EOF
---
- 00-$APPLIANCE_NAME\_basic.rb
EOF

# Generate basic test file
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests/00-${APPLIANCE_NAME}_basic.rb" << EOF
# Basic test for $APP_NAME appliance

require_relative '../../../lib/tests'

class Test${APPLIANCE_NAME^} < Test
  def test_docker_installed
    assert_cmd('docker --version')
  end

  def test_docker_running
    assert_cmd('systemctl is-active docker')
  end

  def test_image_pulled
    assert_cmd("docker images | grep '$DOCKER_IMAGE'")
  end

  def test_container_running
    assert_cmd("docker ps | grep '$DEFAULT_CONTAINER_NAME'")
  end
end
EOF

# Generate context.yaml for testing
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/context.yaml" << EOF
---
CONTAINER_NAME: $DEFAULT_CONTAINER_NAME
CONTAINER_PORTS: $DEFAULT_PORTS
CONTAINER_ENV: $DEFAULT_ENV_VARS
CONTAINER_VOLUMES: $DEFAULT_VOLUMES
EOF

print_success "Additional files generated"

print_success "Packer configuration files generated"

# Add appliance to Makefile.config SERVICES list
print_info "📝 Adding '$APPLIANCE_NAME' to Makefile.config SERVICES list..."
MAKEFILE_CONFIG="$REPO_ROOT/apps-code/community-apps/Makefile.config"

if [ -f "$MAKEFILE_CONFIG" ]; then
    # Check if appliance is already in SERVICES list
    if grep -q "SERVICES.*$APPLIANCE_NAME" "$MAKEFILE_CONFIG"; then
        print_info "  ℹ️  '$APPLIANCE_NAME' already in SERVICES list"
    else
        # Add appliance to SERVICES list
        sed -i "s/^\(SERVICES :=.*\)$/\1 $APPLIANCE_NAME/" "$MAKEFILE_CONFIG"
        print_success "  ✅ Added '$APPLIANCE_NAME' to SERVICES list"
    fi
else
    print_warning "  ⚠️  Makefile.config not found, skipping SERVICES update"
fi

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
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"
print_info "  ✅ apps-code/community-apps/Makefile.config (updated SERVICES list)"
print_info ""
print_info "🚀 Next steps:"
print_info "  1. Add logo: logos/$APPLIANCE_NAME.png (256x256 PNG)"
print_info "  2. Build the image:"
print_info "     cd apps-code/community-apps && make $APPLIANCE_NAME"
print_info "  3. Test the appliance"
print_info ""

# Ask user if they want to build the image now
read -p "$(echo -e "${BLUE}Do you want to build the image now? (y/n):${NC} ")" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "🔨 Preparing to build the image..."

    # Check and initialize git submodules
    print_info "📦 Checking git submodules..."
    cd "$REPO_ROOT" || {
        print_error "Failed to navigate to repository root"
        exit 1
    }

    # Check if one-apps submodule is initialized
    if [ ! -f "apps-code/one-apps/packer/build.sh" ]; then
        print_info "  ⚙️  Initializing one-apps submodule (this may take a moment)..."
        if git submodule update --init --recursive apps-code/one-apps; then
            print_success "  ✅ Submodule initialized successfully"
        else
            print_error "Failed to initialize git submodules"
            print_info "Please run manually: git submodule update --init --recursive"
            exit 1
        fi
    else
        print_info "  ✅ Submodule already initialized"
    fi

    # Check if base image exists
    BASE_IMAGE="$REPO_ROOT/apps-code/one-apps/export/ubuntu2204min.qcow2"
    if [ ! -f "$BASE_IMAGE" ]; then
        print_info "📦 Base Ubuntu minimal image not found - building it now..."
        print_info "  ℹ️  This is a one-time process that will take 3-5 minutes"
        print_info "  ℹ️  The base image will be reused for all future appliances"
        print_info ""

        cd "$REPO_ROOT/apps-code/one-apps" || {
            print_error "Failed to navigate to one-apps directory"
            exit 1
        }

        print_info "🔨 Building base Ubuntu minimal image..."
        if make ubuntu2204min; then
            print_success "✅ Base image built successfully!"
        else
            print_error "❌ Base image build failed!"
            print_info "You can try building it manually later:"
            print_info "  cd $REPO_ROOT/apps-code/one-apps && make ubuntu2204min"
            exit 1
        fi
    else
        print_info "  ✅ Base Ubuntu minimal image found"
    fi

    # Navigate to the build directory
    cd "$REPO_ROOT/apps-code/community-apps" || {
        print_error "Failed to navigate to apps-code/community-apps"
        exit 1
    }

    # Build the image using make
    print_info "🔨 Building appliance image..."
    print_info "Running: make $APPLIANCE_NAME"
    if make "$APPLIANCE_NAME"; then
        print_success "✅ Image built successfully!"

        # Check if the qcow2 file exists
        if [ -f "export/$APPLIANCE_NAME.qcow2" ]; then
            QCOW2_SIZE=$(du -h "export/$APPLIANCE_NAME.qcow2" | cut -f1)
            print_success "Image location: $REPO_ROOT/apps-code/community-apps/export/$APPLIANCE_NAME.qcow2"
            print_success "Image size: $QCOW2_SIZE"
            print_info ""
            print_info "📋 Next steps to deploy:"
            print_info "  1. Copy to OpenNebula frontend: cp export/$APPLIANCE_NAME.qcow2 /var/tmp/"
            print_info "  2. Create image: oneimage create --name $APPLIANCE_NAME --path /var/tmp/$APPLIANCE_NAME.qcow2 --datastore <datastore_id>"
            print_info "  3. Create template and instantiate VM"
        else
            print_warning "Image file not found at export/$APPLIANCE_NAME.qcow2"
            print_info "The image might be in a different location. Check the build output above."
        fi
    else
        print_error "❌ Image build failed!"
        print_info "Check the error messages above for details."
        exit 1
    fi
else
    print_info "Skipping build. You can build later using:"
    print_info "  cd $REPO_ROOT/apps-code/community-apps && make $APPLIANCE_NAME"
fi
