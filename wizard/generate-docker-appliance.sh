#!/bin/bash

# Ultimate OpenNebula Docker Appliance Generator
# Creates ALL files needed for a Docker appliance from a simple config file

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; DIM='\033[2m'; NC='\033[0m'
print_info() { echo -e "  ${DIM}$1${NC}"; }
print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }
print_step() { echo -e "  ${WHITE}$1${NC}"; }

show_usage() {
    cat << EOF
🚀 Ultimate OpenNebula Docker Appliance Generator

Usage: $0 <config-file> [--no-build]

Creates ALL necessary files for a complete Docker-based OpenNebula appliance.

Options:
    --no-build    Generate files only, skip building the appliance image

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
    BASE_OS="ubuntu2204min"  # Optional: Base OS for the VM image
    VM_CPU="1"               # Optional: CPU cores (default: 1)
    VM_VCPU="2"              # Optional: Virtual CPUs (default: 2)
    VM_MEMORY="2048"         # Optional: Memory in MB (default: 2048)
    VM_DISK_SIZE="12288"     # Optional: Disk size in MB (default: 12GB, must be >= base image)
    ONE_VERSION="7.0"        # Optional: OpenNebula version (auto-detected)

Supported BASE_OS values (x86_64):
    ubuntu2204min, ubuntu2204, ubuntu2404min, ubuntu2404
    debian11, debian12, alma8, alma9, rocky8, rocky9, opensuse15

Supported BASE_OS values (ARM64):
    ubuntu2204.aarch64, ubuntu2404.aarch64
    debian11.aarch64, debian12.aarch64
    alma8.aarch64, alma9.aarch64, rocky8.aarch64, rocky9.aarch64
    opensuse15.aarch64

The base image must exist before building. Build it with:
    cd apps-code/one-apps && make <BASE_OS>

This will generate:
✅ All appliance files (metadata, appliance.sh, README, CHANGELOG)
✅ All Packer configuration files
✅ All test files
✅ Complete directory structure
✅ Ready-to-build appliance

EOF
}

# Parse arguments
SKIP_BUILD="false"
CONFIG_FILE=""

for arg in "$@"; do
    case "$arg" in
        --no-build)
            SKIP_BUILD="true"
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$CONFIG_FILE" ]; then
                CONFIG_FILE="$arg"
            else
                print_error "Unknown argument: $arg"
                show_usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "$CONFIG_FILE" ]; then show_usage; exit 1; fi
if [ ! -f "$CONFIG_FILE" ]; then print_error "Config file '$CONFIG_FILE' not found!"; exit 1; fi

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
BASE_OS="${BASE_OS:-ubuntu2204min}"

# VM sizing defaults (can be overridden in config)
VM_CPU="${VM_CPU:-1}"
VM_VCPU="${VM_VCPU:-2}"
VM_MEMORY="${VM_MEMORY:-2048}"
VM_DISK_SIZE="${VM_DISK_SIZE:-12288}"  # 12GB - must be >= base image size (10GB)

# Login configuration defaults
AUTOLOGIN_ENABLED="${AUTOLOGIN_ENABLED:-true}"
LOGIN_USERNAME="${LOGIN_USERNAME:-root}"
ROOT_PASSWORD="${ROOT_PASSWORD:-opennebula}"

# Docker update mode: CHECK (notify only), YES (auto-update), NO (never check)
DOCKER_AUTO_UPDATE="${DOCKER_AUTO_UPDATE:-CHECK}"

# Detect OpenNebula version (from installed version or default)
if command -v onevm &>/dev/null; then
    ONE_VERSION=$(onevm --version 2>/dev/null | grep -oP 'OpenNebula \K[0-9]+\.[0-9]+' || echo "7.0")
else
    ONE_VERSION="${ONE_VERSION:-7.0}"
fi

# Determine if this is an ARM64 build and set QEMU settings
IS_ARM64="false"
QEMU_BINARY="qemu-system-x86_64"
MACHINE_TYPE="pc"
QEMU_BIOS_ARG=""

if [[ "$BASE_OS" == *".aarch64" ]]; then
    IS_ARM64="true"
    QEMU_BINARY="qemu-system-aarch64"
    MACHINE_TYPE="virt,gic-version=max"
    # ARM64 requires UEFI BIOS
    QEMU_BIOS_ARG=',
    ["-bios", "/usr/share/AAVMF/AAVMF_CODE.fd"]'

    # Warn about cross-architecture builds
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "x86_64" ]; then
        print_warning "Cross-architecture build detected (x86_64 → ARM64)"
        print_warning "This requires QEMU emulation and will be slow"
    fi
fi

# Validate appliance name (lowercase letters, numbers, hyphens; must start with letter)
if [[ ! "$APPLIANCE_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    print_error "APPLIANCE_NAME must be lowercase letters, numbers, and hyphens only (start with letter)"; exit 1
fi

# Extract OS name and version from BASE_OS for metadata
# BASE_OS examples: ubuntu2204min, ubuntu2404.aarch64, debian12, alma9.aarch64
BASE_OS_CLEAN="${BASE_OS%.aarch64}"  # Remove .aarch64 suffix if present
case "$BASE_OS_CLEAN" in
    ubuntu2204*) OS_NAME="Ubuntu"; OS_VERSION="22.04" ;;
    ubuntu2404*) OS_NAME="Ubuntu"; OS_VERSION="24.04" ;;
    debian12*)   OS_NAME="Debian"; OS_VERSION="12" ;;
    debian11*)   OS_NAME="Debian"; OS_VERSION="11" ;;
    alma9*)      OS_NAME="AlmaLinux"; OS_VERSION="9" ;;
    alma8*)      OS_NAME="AlmaLinux"; OS_VERSION="8" ;;
    rocky9*)     OS_NAME="Rocky Linux"; OS_VERSION="9" ;;
    rocky8*)     OS_NAME="Rocky Linux"; OS_VERSION="8" ;;
    opensuse15*) OS_NAME="openSUSE Leap"; OS_VERSION="15" ;;
    *)           OS_NAME="Linux"; OS_VERSION="unknown" ;;
esac

# Set architecture for metadata
if [ "$IS_ARM64" = "true" ]; then
    OS_ARCH="aarch64"
    ARCH_TAGS="- arm64
- aarch64"
else
    OS_ARCH="x86_64"
    ARCH_TAGS="- x86_64
- amd64"
fi

# Generate OS tag (lowercase version of OS name)
OS_TAG=$(echo "$OS_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Determine repository root (go up one level from wizard/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Display clean header
echo ""
echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}Generating: ${CYAN}${APPLIANCE_NAME}${NC}"
echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${DIM}App:${NC}  ${APP_NAME}"
echo -e "  ${DIM}OS:${NC}   ${OS_NAME} ${OS_VERSION} (${OS_ARCH})"
echo -e "  ${DIM}Base:${NC} ${DOCKER_IMAGE}"
echo -e "  ${DIM}VM:${NC}   ${VM_CPU} CPU, ${VM_VCPU} vCPU, ${VM_MEMORY}MB RAM, ${VM_DISK_SIZE}MB disk"
echo -e "  ${DIM}ONE:${NC}  v${ONE_VERSION}"
echo ""

# Create directories (absolute paths from repository root)
mkdir -p "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests"
mkdir -p "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME"

APPLIANCE_UUID=$(uuidgen)
CREATION_TIME=$(date +%s)
CURRENT_DATE=$(date +%Y-%m-%d)

# Progress tracking
echo -e "  ${WHITE}Creating files...${NC}"
echo ""

# Generate metadata.yaml
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/metadata.yaml" << EOF
---
:app:
  :name: $APPLIANCE_NAME
  :type: service
  :os:
    - $OS_NAME
    - '$OS_VERSION'
  :arch:
    - $OS_ARCH
  :format: qcow2
  :hypervisor:
    - KVM
  :opennebula_version:
    - '7.0'
  :opennebula_template:
    context:
      - SSH_PUBLIC_KEY="\$USER[SSH_PUBLIC_KEY]"
      - SET_HOSTNAME="\$USER[SET_HOSTNAME]"
    cpu: '$VM_CPU'
    vcpu: '$VM_VCPU'
    memory: '$VM_MEMORY'
    disk_size: '$VM_DISK_SIZE'
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
  running in a Docker container on $OS_NAME $OS_VERSION with VNC access and
  SSH key authentication.

  **$APP_NAME features:**
$(echo -e "$FEATURES_YAML")
  **This appliance provides:**
  - $OS_NAME $OS_VERSION base operating system
  - Docker Engine CE pre-installed and configured
  - $APP_NAME container ($DOCKER_IMAGE) ready to run
  - VNC access for desktop environment
  - SSH key authentication from OpenNebula context$WEB_FEATURE
  - Configurable container parameters (ports, volumes, environment variables)

  **Access Methods:**
  - VNC: Direct access to desktop environment
  - SSH: Key-based authentication from OpenNebula$WEB_ACCESS

short_description: $APP_NAME on $OS_NAME $OS_VERSION ($OS_ARCH)
tags:
- $APPLIANCE_NAME
- docker
- $OS_TAG
$ARCH_TAGS
- container
- vnc
- ssh-key
format: qcow2
creation_time: $CREATION_TIME
os-id: $OS_NAME
os-release: '$OS_VERSION'
os-arch: $OS_ARCH
hypervisor: KVM
opennebula_version: '$ONE_VERSION'
opennebula_template:
  context:
    network: 'YES'
    ssh_public_key: \$USER[SSH_PUBLIC_KEY]
    set_hostname: \$USER[SET_HOSTNAME]
  cpu: '$VM_CPU'
  vcpu: '$VM_VCPU'
  disk:
    image: \$FILE[IMAGE_ID]
    image_uname: \$USER[IMAGE_UNAME]
  graphics:
    listen: 0.0.0.0
    type: vnc
  memory: '$VM_MEMORY'
  name: $APP_NAME
  user_inputs:
    - CONTAINER_NAME: 'M|text|Container name|$DEFAULT_CONTAINER_NAME|$DEFAULT_CONTAINER_NAME'
    - CONTAINER_PORTS: 'M|text|Container ports (format: host:container)|$DEFAULT_PORTS|$DEFAULT_PORTS'
    - CONTAINER_ENV: 'O|text|Environment variables (format: VAR1=value1,VAR2=value2)|$DEFAULT_ENV_VARS|'
    - CONTAINER_VOLUMES: 'O|text|Volume mounts (format: /host/path:/container/path)|$DEFAULT_VOLUMES|'
  inputs_order: CONTAINER_NAME,CONTAINER_PORTS,CONTAINER_ENV,CONTAINER_VOLUMES
logo: logos/$APPLIANCE_NAME.png
EOF

print_success "Metadata files"

# Generate README.md
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/README.md" << EOF
# $APP_NAME Appliance

$APP_DESCRIPTION. This appliance provides $APP_NAME running in a Docker container on $OS_NAME $OS_VERSION with VNC access and SSH key authentication.

## Key Features

**$APP_NAME capabilities:**
$(echo -e "$FEATURES_YAML")
**This appliance provides:**
- $OS_NAME $OS_VERSION base operating system
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

print_success "README.md"

# Generate appliance.sh installation script
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
    'ONEAPP_DOCKER_AUTO_UPDATE' 'configure'  'Docker update mode (CHECK/YES/NO)'        'O|text'
)

# Configuration from user input
DOCKER_IMAGE="$DOCKER_IMAGE"
DEFAULT_CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
DEFAULT_PORTS="$DEFAULT_PORTS"
DEFAULT_ENV_VARS="$DEFAULT_ENV_VARS"
DEFAULT_VOLUMES="$DEFAULT_VOLUMES"
APP_NAME="$APP_NAME"
APPLIANCE_NAME="$APPLIANCE_NAME"
DOCKER_AUTO_UPDATE="${DOCKER_AUTO_UPDATE:-CHECK}"
AUTOLOGIN_ENABLED="${AUTOLOGIN_ENABLED:-true}"
LOGIN_USERNAME="${LOGIN_USERNAME:-root}"
ROOT_PASSWORD="${ROOT_PASSWORD:-opennebula}"
DOCKER_VERSION_FILE="/opt/one-appliance/.docker_image_digest"

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

# Check for Docker image updates
check_docker_updates()
{
    local update_mode="${ONEAPP_DOCKER_AUTO_UPDATE:-$DOCKER_AUTO_UPDATE}"

    if [ "$update_mode" = "NO" ]; then
        msg info "Docker update check disabled"
        return 0
    fi

    msg info "Checking for Docker image updates..."

    # Get current saved digest
    local current_digest=""
    if [ -f "$DOCKER_VERSION_FILE" ]; then
        current_digest=$(cat "$DOCKER_VERSION_FILE")
    fi

    # Get latest remote digest without pulling the full image
    local latest_digest
    latest_digest=$(docker manifest inspect "$DOCKER_IMAGE" 2>/dev/null | \
                    grep -o '"digest": "sha256:[a-f0-9]*"' | head -1 | \
                    cut -d'"' -f4) || true

    if [ -z "$latest_digest" ]; then
        msg warning "Could not check for updates (network issue or private registry)"
        return 0
    fi

    # Save current digest if first run
    if [ -z "$current_digest" ]; then
        local running_digest
        running_digest=$(docker inspect "$DOCKER_IMAGE" --format='{{.Id}}' 2>/dev/null) || true
        if [ -n "$running_digest" ]; then
            echo "$running_digest" > "$DOCKER_VERSION_FILE"
            current_digest="$running_digest"
        fi
    fi

    if [ "$current_digest" = "$latest_digest" ]; then
        msg info "Docker image is up to date"
        return 0
    fi

    # Update available!
    case "$update_mode" in
        YES)
            msg info "New Docker image version available - auto-updating..."
            perform_docker_update "$latest_digest"
            ;;
        CHECK|*)
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo "  🆕 UPDATE AVAILABLE for $APP_NAME"
            echo "════════════════════════════════════════════════════════════════"
            echo "  Image: $DOCKER_IMAGE"
            [ -n "$current_digest" ] && echo "  Current: ${current_digest:0:30}..."
            echo "  Latest:  ${latest_digest:0:30}..."
            echo ""
            echo "  To update, run:  docker-appliance-update"
            echo "  To auto-update:  Set ONEAPP_DOCKER_AUTO_UPDATE=YES in context"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            ;;
    esac
}

# Perform the Docker image update
perform_docker_update()
{
    local new_digest="$1"

    msg info "Pulling latest image: $DOCKER_IMAGE"
    if ! docker pull "$DOCKER_IMAGE"; then
        msg error "Failed to pull image"
        return 1
    fi

    msg info "Stopping current container..."
    docker stop "$DEFAULT_CONTAINER_NAME" 2>/dev/null || true

    msg info "Removing old container..."
    docker rm "$DEFAULT_CONTAINER_NAME" 2>/dev/null || true

    msg info "Starting updated container..."
    start_docker_container

    # Save new digest
    local updated_digest
    updated_digest=$(docker inspect "$DOCKER_IMAGE" --format='{{.Id}}' 2>/dev/null) || true
    if [ -n "$updated_digest" ]; then
        echo "$updated_digest" > "$DOCKER_VERSION_FILE"
    fi

    msg info "✅ Update complete!"
}

# Start the Docker container with configured settings
start_docker_container()
{
    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local ports="${ONEAPP_CONTAINER_PORTS:-$DEFAULT_PORTS}"
    local env_vars="${ONEAPP_CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
    local volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

    # Build docker run command
    local docker_cmd="docker run -d --name $container_name --restart unless-stopped"

    # Add port mappings
    if [ -n "$ports" ]; then
        for port in $(echo "$ports" | tr ',' ' '); do
            docker_cmd="$docker_cmd -p $port"
        done
    fi

    # Add environment variables
    if [ -n "$env_vars" ]; then
        for env in $(echo "$env_vars" | tr ',' ' '); do
            docker_cmd="$docker_cmd -e $env"
        done
    fi

    # Add volume mappings
    if [ -n "$volumes" ]; then
        for vol in $(echo "$volumes" | tr ',' ' '); do
            # Create host directory if it doesn't exist
            local host_path=$(echo "$vol" | cut -d: -f1)
            [ -n "$host_path" ] && mkdir -p "$host_path"
            docker_cmd="$docker_cmd -v $vol"
        done
    fi

    # Add the image
    docker_cmd="$docker_cmd $DOCKER_IMAGE"

    # Run the container
    eval $docker_cmd
}

service_install()
{
    # Detect OS family
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_FAMILY=""
        case "$ID" in
            ubuntu|debian|linuxmint)
                OS_FAMILY="debian"
                ;;
            almalinux|rocky|centos|rhel|fedora)
                OS_FAMILY="rhel"
                ;;
            opensuse*|suse|sles)
                OS_FAMILY="suse"
                ;;
            *)
                msg error "Unsupported OS: $ID"
                return 1
                ;;
        esac
    else
        msg error "Cannot detect OS - /etc/os-release not found"
        return 1
    fi

    msg info "Detected OS: $ID $VERSION_ID (family: $OS_FAMILY)"

    # Install Docker based on OS family
    case "$OS_FAMILY" in
        debian)
            install_docker_debian
            ;;
        rhel)
            install_docker_rhel
            ;;
        suse)
            install_docker_suse
            ;;
    esac

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Pull the Docker image
    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    # Configure console auto-login
    configure_console_autologin

    # Create the docker-appliance-update helper script
    cat > /usr/local/bin/docker-appliance-update << 'UPDATE_SCRIPT_EOF'
#!/bin/bash
# Docker Appliance Update Script

echo ""
echo "🔄 Updating Docker image..."
echo ""

# Source the appliance config
DOCKER_IMAGE="$DOCKER_IMAGE"
DEFAULT_CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
DEFAULT_PORTS="$DEFAULT_PORTS"
DEFAULT_ENV_VARS="$DEFAULT_ENV_VARS"
DEFAULT_VOLUMES="$DEFAULT_VOLUMES"
DOCKER_VERSION_FILE="/opt/one-appliance/.docker_image_digest"

# Pull latest image
echo "Pulling latest image: \$DOCKER_IMAGE"
if ! docker pull "\$DOCKER_IMAGE"; then
    echo "❌ Failed to pull image"
    exit 1
fi

# Stop current container
echo "Stopping current container..."
docker stop "\$DEFAULT_CONTAINER_NAME" 2>/dev/null || true

# Remove old container
echo "Removing old container..."
docker rm "\$DEFAULT_CONTAINER_NAME" 2>/dev/null || true

# Build and run new container
echo "Starting updated container..."
docker_cmd="docker run -d --name \$DEFAULT_CONTAINER_NAME --restart unless-stopped"

# Add port mappings
if [ -n "\$DEFAULT_PORTS" ]; then
    for port in \$(echo "\$DEFAULT_PORTS" | tr ',' ' '); do
        docker_cmd="\$docker_cmd -p \$port"
    done
fi

# Add environment variables
if [ -n "\$DEFAULT_ENV_VARS" ]; then
    for env in \$(echo "\$DEFAULT_ENV_VARS" | tr ',' ' '); do
        docker_cmd="\$docker_cmd -e \$env"
    done
fi

# Add volume mappings
if [ -n "\$DEFAULT_VOLUMES" ]; then
    for vol in \$(echo "\$DEFAULT_VOLUMES" | tr ',' ' '); do
        host_path=\$(echo "\$vol" | cut -d: -f1)
        [ -n "\$host_path" ] && mkdir -p "\$host_path"
        docker_cmd="\$docker_cmd -v \$vol"
    done
fi

docker_cmd="\$docker_cmd \$DOCKER_IMAGE"
eval \$docker_cmd

# Save new digest
mkdir -p "\$(dirname "\$DOCKER_VERSION_FILE")"
docker inspect "\$DOCKER_IMAGE" --format='{{.Id}}' > "\$DOCKER_VERSION_FILE" 2>/dev/null

echo ""
echo "✅ Update complete!"
echo ""
docker ps --filter "name=\$DEFAULT_CONTAINER_NAME"
UPDATE_SCRIPT_EOF

    chmod +x /usr/local/bin/docker-appliance-update

    # Create directory for version tracking
    mkdir -p /opt/one-appliance

    # Save initial image digest
    docker inspect "$DOCKER_IMAGE" --format='{{.Id}}' > "$DOCKER_VERSION_FILE" 2>/dev/null || true

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
echo "    docker-appliance-update      - Update to latest image version"
echo ""
echo "  Access Methods:"
echo "    SSH: Enabled (password: 'opennebula' + context keys)"
echo "    Console: Auto-login as root (via OpenNebula console)"
echo "    Serial: Auto-login as root (via serial console)"
echo "=================================================="
WELCOME_EOF

    chmod +x /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh

    # Clean up based on OS
    cleanup_os

    sync

    return 0
}

install_docker_debian()
{
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get upgrade -y

    # Install generic kernel for VNC console support and proper initramfs
    msg info "Installing generic kernel for VNC console support"
    apt-get install -y linux-image-generic || true

    if [ -f /etc/default/grub ]; then
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
        update-grub
    fi

    # Install Docker
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings

    # Handle Linux Mint by using Ubuntu repos
    local DOCKER_DISTRO="$ID"
    [ "$ID" = "linuxmint" ] && DOCKER_DISTRO="ubuntu"

    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Disable unattended upgrades if present
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true
}

install_docker_rhel()
{
    dnf -y update
    dnf -y install dnf-plugins-core curl

    # Add Docker repo
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_suse()
{
    zypper refresh
    zypper -n update
    zypper -n install curl ca-certificates

    # openSUSE: Use official Docker packages from openSUSE repos
    # Note: docker-compose is available as a separate package
    zypper -n install docker docker-compose containerd

    # Alternatively for Docker CE, add the CentOS repo (works on openSUSE)
    # zypper addrepo https://download.docker.com/linux/centos/docker-ce.repo
    # zypper -n install docker-ce docker-ce-cli containerd.io
}

configure_console_autologin()
{
    msg info "Configuring VNC and serial console access..."

    # Create TTY devices at boot (fallback for kernels without VT support)
    cat > /etc/systemd/system/create-tty-devices.service << 'TTY_SERVICE_EOF'
[Unit]
Description=Create TTY device nodes for KVM kernel
DefaultDependencies=no
Before=getty@tty1.service
After=systemd-tmpfiles-setup-dev.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for i in 0 1 2 3 4 5 6; do [ -e /dev/tty$i ] || mknod /dev/tty$i c 4 $i; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TTY_SERVICE_EOF
    systemctl enable create-tty-devices.service

    # Configure console login based on AUTOLOGIN_ENABLED setting
    mkdir -p /etc/systemd/system/getty@tty1.service.d

    if [ "${AUTOLOGIN_ENABLED}" = "true" ]; then
        msg info "Configuring autologin for user: ${LOGIN_USERNAME}"
        cat > /etc/systemd/system/getty@tty1.service.d/override.conf << CONSOLE_EOF
[Unit]
# Remove ConditionPathExists to avoid skipping on KVM kernels
ConditionPathExists=

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin ${LOGIN_USERNAME} %I \$TERM
Type=idle
CONSOLE_EOF
    else
        msg info "Configuring password-based login for user: ${LOGIN_USERNAME}"
        cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'CONSOLE_EOF'
[Unit]
# Remove ConditionPathExists to avoid skipping on KVM kernels
ConditionPathExists=

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue %I $TERM
Type=idle
CONSOLE_EOF
    fi

    # Configure serial console (PRIMARY console for cloud VMs)
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d

    if [ "${AUTOLOGIN_ENABLED}" = "true" ]; then
        cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << SERIAL_EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin ${LOGIN_USERNAME} %I 115200,38400,9600 vt102
Type=idle
SERIAL_EOF
    else
        cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'SERIAL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue %I 115200,38400,9600 vt102
Type=idle
SERIAL_EOF
    fi

    # Set user password
    if [ -n "${ROOT_PASSWORD}" ]; then
        msg info "Setting password for ${LOGIN_USERNAME}"
        echo "${LOGIN_USERNAME}:${ROOT_PASSWORD}" | chpasswd
    else
        # Default password if none specified
        echo "${LOGIN_USERNAME}:opennebula" | chpasswd
    fi

    # Enable getty services
    systemctl enable getty@tty1.service serial-getty@ttyS0.service
}

cleanup_os()
{
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    fi

    case "$ID" in
        ubuntu|debian)
            apt-get autoremove -y
            apt-get autoclean
            ;;
        almalinux|rocky|rhel|centos|fedora)
            dnf clean all
            ;;
        opensuse*|sles)
            zypper clean --all
            ;;
    esac

    find /var/log -type f -exec truncate -s 0 {} \;
}

service_configure()
{
    msg info "Configuring SSH access"
    configure_ssh_access

    msg info "Verifying Docker is running"

    if ! systemctl is-active --quiet docker; then
        msg error "Docker is not running"
        return 1
    fi

    msg info "Docker is running"

    # Check for Docker image updates
    check_docker_updates

    return 0
}

# Configure SSH for easy access (runs at every boot via one-context)
configure_ssh_access()
{
    local SSHD_CONFIG="/etc/ssh/sshd_config"
    local SSH_CHANGED=false

    # Function to set SSH config option
    set_ssh_option() {
        local option="\$1"
        local value="\$2"
        if grep -qE "^[#[:space:]]*\${option}[[:space:]]" "\$SSHD_CONFIG" 2>/dev/null; then
            sed -i "s|^[#[:space:]]*\${option}[[:space:]].*|\${option} \${value}|" "\$SSHD_CONFIG"
        else
            echo "\${option} \${value}" >> "\$SSHD_CONFIG"
        fi
    }

    # Enable password authentication
    if ! grep -q "^PasswordAuthentication yes" "\$SSHD_CONFIG" 2>/dev/null; then
        set_ssh_option "PasswordAuthentication" "yes"
        SSH_CHANGED=true
    fi

    # Enable root login
    if ! grep -q "^PermitRootLogin yes" "\$SSHD_CONFIG" 2>/dev/null; then
        set_ssh_option "PermitRootLogin" "yes"
        SSH_CHANGED=true
    fi

    # Disable DNS lookup for faster connections
    set_ssh_option "UseDNS" "no"

    # Set root password if not already set (check if password is locked/empty)
    if passwd -S root 2>/dev/null | grep -qE "^root (L|NP)"; then
        echo "root:opennebula" | chpasswd
        msg info "Root password set to: opennebula"
    fi

    # Restart SSH if config changed
    if [ "\$SSH_CHANGED" = true ]; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        msg info "SSH configured: PasswordAuthentication=yes, PermitRootLogin=yes"
    fi

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
print_success "appliance.sh"

# Generate basic Packer files

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
  qemu_binary = "${QEMU_BINARY}"

  iso_url      = "../one-apps/export/${BASE_OS}.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "${VM_DISK_SIZE}"
  machine_type     = "${MACHINE_TYPE}"

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-cdrom", "\${var.input_dir}/\${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]${QEMU_BIOS_ARG}
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

# Generate 81-configure-ssh.sh (using sed for compatibility with all distros)
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh" << 'EOF'
#!/usr/bin/env bash

# Configures critical settings for OpenSSH server.
# Uses sed instead of gawk for compatibility with Alma, Rocky, Debian, etc.

exec 1>&2
set -eux -o pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"

# Function to set or add SSH config option
set_ssh_option() {
    local option="$1"
    local value="$2"
    if grep -qE "^[#[:space:]]*${option}[[:space:]]" "$SSHD_CONFIG"; then
        sed -i "s|^[#[:space:]]*${option}[[:space:]].*|${option} ${value}|" "$SSHD_CONFIG"
    else
        echo "${option} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Allow both password and key-based authentication for easier access
set_ssh_option "PasswordAuthentication" "yes"
set_ssh_option "PermitRootLogin" "yes"
set_ssh_option "UseDNS" "no"

# Ensure root password is set (for password-based SSH fallback)
echo "root:opennebula" | chpasswd

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

print_success "Packer configuration"

# Generate additional required files

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

# Add appliance to Makefile.config SERVICES list
MAKEFILE_CONFIG="$REPO_ROOT/apps-code/community-apps/Makefile.config"

if [ -f "$MAKEFILE_CONFIG" ]; then
    if ! grep -q "SERVICES.*$APPLIANCE_NAME" "$MAKEFILE_CONFIG"; then
        sed -i "s/^\(SERVICES :=.*\)$/\1 $APPLIANCE_NAME/" "$MAKEFILE_CONFIG"
    fi
fi

# Count generated files
APPLIANCE_FILES=$(find "$REPO_ROOT/appliances/$APPLIANCE_NAME" -type f 2>/dev/null | wc -l)
PACKER_FILES=$(find "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME" -type f 2>/dev/null | wc -l)

echo ""
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✓ Files generated successfully${NC}"
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${DIM}Appliance config:${NC}  appliances/${APPLIANCE_NAME}/  ${DIM}(${APPLIANCE_FILES} files)${NC}"
echo -e "  ${DIM}Packer build:${NC}      apps-code/community-apps/packer/${APPLIANCE_NAME}/  ${DIM}(${PACKER_FILES} files)${NC}"
echo ""

# Ask user if they want to build the image now
read -p "$(echo -e "  ${WHITE}Build the image now?${NC} [Y/n]: ")" -r REPLY
REPLY=${REPLY:-Y}  # Default to Y if empty
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "  ${WHITE}Preparing build...${NC}"

    # Check and initialize git submodules
    cd "$REPO_ROOT" || { print_error "Failed to navigate to repository root"; exit 1; }

    # Check if one-apps submodule is initialized
    if [ ! -f "apps-code/one-apps/packer/build.sh" ]; then
        echo -e "  ${DIM}Initializing submodules...${NC}"
        if ! git submodule update --init --recursive apps-code/one-apps; then
            print_error "Failed to initialize git submodules"
            exit 1
        fi
    fi

    # Check if base image exists (supports both x86_64 and ARM64)
    BASE_IMAGE="$REPO_ROOT/apps-code/one-apps/export/${BASE_OS}.qcow2"
    if [ ! -f "$BASE_IMAGE" ]; then
        echo ""
        echo -e "  ${YELLOW}Base image not found:${NC} ${BASE_OS}.qcow2"
        echo -e "  ${DIM}Building now (10-15 minutes, reused for future appliances)...${NC}"
        echo ""

        cd "$REPO_ROOT/apps-code/one-apps" || { print_error "Failed to navigate to one-apps"; exit 1; }

        if ! make "${BASE_OS}"; then
            print_error "Base image build failed"
            echo -e "  ${DIM}Try manually: cd $REPO_ROOT/apps-code/one-apps && make ${BASE_OS}${NC}"
            exit 1
        fi
        print_success "Base image built"
    fi

    # Navigate to the build directory
    cd "$REPO_ROOT/apps-code/community-apps" || { print_error "Failed to navigate to build dir"; exit 1; }

    # Build the image using make
    echo ""
    echo -e "  ${WHITE}Building appliance image...${NC}"
    echo -e "  ${DIM}This may take 10-20 minutes${NC}"
    echo ""

    if make "$APPLIANCE_NAME"; then
        # Check if the qcow2 file exists
        if [ -f "export/$APPLIANCE_NAME.qcow2" ]; then
            QCOW2_SIZE=$(du -h "export/$APPLIANCE_NAME.qcow2" | cut -f1)
            IMAGE_PATH="$REPO_ROOT/apps-code/community-apps/export/$APPLIANCE_NAME.qcow2"

            echo ""
            echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${GREEN}✓ Build complete!${NC}"
            echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "  ${WHITE}Image:${NC} ${CYAN}${IMAGE_PATH}${NC}"
            echo -e "  ${WHITE}Size:${NC}  ${QCOW2_SIZE}"
            echo ""
            echo -e "  ${WHITE}Deploy to OpenNebula:${NC}"
            echo ""
            echo -e "  ${DIM}# Copy image to frontend${NC}"
            echo -e "  ${CYAN}scp export/$APPLIANCE_NAME.qcow2 <frontend>:/var/tmp/${NC}"
            echo ""
            echo -e "  ${DIM}# Create image${NC}"
            echo -e "  ${CYAN}oneimage create --name $APPLIANCE_NAME \\${NC}"
            echo -e "  ${CYAN}  --path /var/tmp/$APPLIANCE_NAME.qcow2 \\${NC}"
            echo -e "  ${CYAN}  --driver qcow2 --datastore <ID>${NC}"
            echo ""
            echo -e "  ${DIM}# Create template and VM via Sunstone or CLI${NC}"
            echo ""
        else
            print_warning "Image file not found at expected location"
        fi
    else
        print_error "Build failed - check output above"
        exit 1
    fi
else
    echo ""
    echo -e "  ${DIM}Build skipped. To build later:${NC}"
    echo -e "  ${CYAN}cd $REPO_ROOT/apps-code/community-apps && make $APPLIANCE_NAME${NC}"
    echo ""
fi
