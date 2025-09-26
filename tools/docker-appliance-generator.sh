#!/bin/bash

# OpenNebula Docker Appliance Generator
# Automatically creates all necessary files for a Docker-based appliance
# Usage: ./docker-appliance-generator.sh config.env

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show usage
show_usage() {
    cat << EOF
OpenNebula Docker Appliance Generator

Usage: $0 <config-file>

Example:
    $0 nginx.env

The config file should contain:
    DOCKER_IMAGE="nginx:alpine"
    DEFAULT_CONTAINER_NAME="nginx-server"
    DEFAULT_PORTS="80:80,443:443"
    DEFAULT_ENV_VARS=""
    DEFAULT_VOLUMES="/etc/nginx/conf.d:/etc/nginx/conf.d"
    APP_NAME="NGINX Web Server"
    APP_PORT="80"
    WEB_INTERFACE="true"
    APPLIANCE_NAME="nginx"
    PUBLISHER_NAME="Your Name"
    PUBLISHER_EMAIL="your.email@domain.com"
    APP_DESCRIPTION="NGINX is a web server and reverse proxy server"
    APP_FEATURES="High performance web server,Reverse proxy capabilities,Load balancing,SSL/TLS termination"

EOF
}

# Check if config file is provided
if [ $# -ne 1 ]; then
    show_usage
    exit 1
fi

CONFIG_FILE="$1"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file '$CONFIG_FILE' not found!"
    exit 1
fi

# Load configuration
print_info "Loading configuration from $CONFIG_FILE"
source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=(
    "DOCKER_IMAGE"
    "APPLIANCE_NAME"
    "APP_NAME"
    "PUBLISHER_NAME"
    "PUBLISHER_EMAIL"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required variable $var is not set in $CONFIG_FILE"
        exit 1
    fi
done

# Set defaults for optional variables
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-${APPLIANCE_NAME}-container}"
DEFAULT_PORTS="${DEFAULT_PORTS:-8080:80}"
DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS:-}"
DEFAULT_VOLUMES="${DEFAULT_VOLUMES:-}"
APP_PORT="${APP_PORT:-8080}"
WEB_INTERFACE="${WEB_INTERFACE:-true}"
APP_DESCRIPTION="${APP_DESCRIPTION:-Docker-based appliance for ${APP_NAME}}"
APP_FEATURES="${APP_FEATURES:-Containerized application,Easy deployment,Configurable parameters}"

# Validate appliance name (must be lowercase, single word)
if [[ ! "$APPLIANCE_NAME" =~ ^[a-z][a-z0-9]*$ ]]; then
    print_error "APPLIANCE_NAME must be a single lowercase word (letters and numbers only)"
    exit 1
fi

print_info "Generating appliance: $APPLIANCE_NAME"
print_info "Docker image: $DOCKER_IMAGE"
print_info "Publisher: $PUBLISHER_NAME <$PUBLISHER_EMAIL>"

# Create directory structure
print_info "Creating directory structure..."
mkdir -p "appliances/$APPLIANCE_NAME/tests"
mkdir -p "apps-code/community-apps/packer/$APPLIANCE_NAME"

# Generate UUID for the appliance
APPLIANCE_UUID=$(uuidgen)
print_info "Generated UUID: $APPLIANCE_UUID"

# Get current date for creation time
CREATION_TIME=$(date +%s)
CURRENT_DATE=$(date +%Y-%m-%d)

print_success "Directory structure created"

# Function to generate metadata.yaml
generate_metadata_yaml() {
    print_info "Generating metadata.yaml..."
    
    cat > "appliances/$APPLIANCE_NAME/metadata.yaml" << EOF
---
:app:
  :name: $APPLIANCE_NAME # name used to make the app with the makefile
  :type: service # there are service (complex apps) and distro (base apps)
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
    
    print_success "metadata.yaml generated"
}

# Function to generate UUID.yaml (main appliance metadata)
generate_uuid_yaml() {
    print_info "Generating ${APPLIANCE_UUID}.yaml..."
    
    # Convert features to YAML list format
    IFS=',' read -ra FEATURES_ARRAY <<< "$APP_FEATURES"
    FEATURES_YAML=""
    for feature in "${FEATURES_ARRAY[@]}"; do
        FEATURES_YAML="$FEATURES_YAML  - $(echo "$feature" | xargs)\n"
    done
    
    # Determine web interface description
    if [ "$WEB_INTERFACE" = "true" ]; then
        WEB_ACCESS="  - Web: $APP_NAME interface at http://VM_IP:$APP_PORT"
        WEB_FEATURE="  - Web interface on port $APP_PORT"
    else
        WEB_ACCESS=""
        WEB_FEATURE=""
    fi
    
    cat > "appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml" << EOF
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
    
    print_success "${APPLIANCE_UUID}.yaml generated"
}

# Start generation process
print_info "Starting appliance generation for: $APP_NAME"

generate_metadata_yaml
generate_uuid_yaml

# Function to generate appliance.sh
generate_appliance_sh() {
    print_info "Generating appliance.sh..."

    cat > "appliances/$APPLIANCE_NAME/appliance.sh" << 'EOF'
#!/usr/bin/env bash

# APPLIANCE_NAME_PLACEHOLDER Appliance Installation Script
# Auto-generated by OpenNebula Docker Appliance Generator

###############################################################################
# Configuration Variables - AUTO-GENERATED
###############################################################################

# Docker image to use
DOCKER_IMAGE="DOCKER_IMAGE_PLACEHOLDER"

# Default container configuration
DEFAULT_CONTAINER_NAME="DEFAULT_CONTAINER_NAME_PLACEHOLDER"
DEFAULT_PORTS="DEFAULT_PORTS_PLACEHOLDER"
DEFAULT_ENV_VARS="DEFAULT_ENV_VARS_PLACEHOLDER"
DEFAULT_VOLUMES="DEFAULT_VOLUMES_PLACEHOLDER"

# Application specific settings
APP_NAME="APP_NAME_PLACEHOLDER"
APP_PORT="APP_PORT_PLACEHOLDER"
WEB_INTERFACE="WEB_INTERFACE_PLACEHOLDER"

###############################################################################
# Standard Installation Functions
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

# Execute main function
main "$@"
EOF

    # Replace placeholders with actual values
    sed -i "s/APPLIANCE_NAME_PLACEHOLDER/$APP_NAME/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s|DOCKER_IMAGE_PLACEHOLDER|$DOCKER_IMAGE|g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/DEFAULT_CONTAINER_NAME_PLACEHOLDER/$DEFAULT_CONTAINER_NAME/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/DEFAULT_PORTS_PLACEHOLDER/$DEFAULT_PORTS/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/DEFAULT_ENV_VARS_PLACEHOLDER/$DEFAULT_ENV_VARS/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/DEFAULT_VOLUMES_PLACEHOLDER/$DEFAULT_VOLUMES/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/APP_NAME_PLACEHOLDER/$APP_NAME/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/APP_PORT_PLACEHOLDER/$APP_PORT/g" "appliances/$APPLIANCE_NAME/appliance.sh"
    sed -i "s/WEB_INTERFACE_PLACEHOLDER/$WEB_INTERFACE/g" "appliances/$APPLIANCE_NAME/appliance.sh"

    chmod +x "appliances/$APPLIANCE_NAME/appliance.sh"

    print_success "appliance.sh generated"
}

# Check if --generate-all flag is provided
if [ "$2" = "--generate-all" ]; then
    generate_appliance_sh
    print_success "All files generated successfully!"
    print_info "Appliance '$APPLIANCE_NAME' is ready for building!"
    print_info "Next steps:"
    print_info "1. Add logo: logos/$APPLIANCE_NAME.png"
    print_info "2. Build: cd apps-code && make $APPLIANCE_NAME"
    print_info "3. Test the appliance"
else
    print_success "Basic metadata files generated!"
    print_info "Next: Run './docker-appliance-generator.sh $CONFIG_FILE --generate-all' to create all files"
fi
