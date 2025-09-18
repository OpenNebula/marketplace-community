#!/usr/bin/env bash

# Custom Docker Appliance for OpenNebula Community Marketplace
# This appliance provides Ubuntu with Docker pre-installed and configured
# Based on patterns from lithops and harbor appliances

### Custom Docker Configuration ##########################################################

# Configuration paths and variables
DOCKER_CONFIG_DIR="/etc/docker"
DOCKER_DATA_DIR="/var/lib/docker"
ONE_SERVICE_SETUP_DIR="/opt/one-appliance" ### Install location. Required by bash helpers

### CONTEXT SECTION ##########################################################

# List of contextualization parameters
# These variables are defined in the CONTEXT section of the VM Template as custom variables
ONE_SERVICE_PARAMS=(
    'ONEAPP_PHOENIXRTOS_PORTS'          'configure' 'Port mappings for Phoenix RTOS (e.g., 8080:8080)'            'O|text'
    'ONEAPP_PHOENIXRTOS_VOLUMES'        'configure' 'Volume mappings for Phoenix RTOS'                             'O|text'
    'ONEAPP_PHOENIXRTOS_ENV_VARS'       'configure' 'Environment variables for Phoenix RTOS container'             'O|text'
    'ONEAPP_PHOENIXRTOS_COMMAND'        'configure' 'Custom command to run in Phoenix RTOS container'              'O|text'
    'ONEAPP_DOCKER_REGISTRY_URL'        'configure' 'Custom Docker registry URL (optional)'                       'O|text'
    'ONEAPP_DOCKER_REGISTRY_USER'       'configure' 'Docker registry username (optional)'                         'O|text'
    'ONEAPP_DOCKER_REGISTRY_PASSWORD'   'configure' 'Docker registry password (optional)'                         'O|password'
    'ONEAPP_DOCKER_COMPOSE_VERSION'     'configure' 'Docker Compose version to install'                           'O|text'
    'ONEAPP_DOCKER_DAEMON_CONFIG'       'configure' 'Custom Docker daemon configuration (JSON)'                   'O|text'
    'ONEAPP_ENABLE_DOCKER_BUILDX'       'configure' 'Enable Docker Buildx plugin (yes/no)'                        'O|boolean'
    'ONEAPP_DOCKER_LOG_DRIVER'          'configure' 'Docker logging driver (json-file, syslog, etc.)'             'O|text'
    'ONEAPP_DOCKER_LOG_MAX_SIZE'        'configure' 'Maximum size of log files'                                    'O|text'
    'ONEAPP_DOCKER_LOG_MAX_FILE'        'configure' 'Maximum number of log files'                                  'O|text'
)

# Default values for when the variable doesn't exist on the VM Template
ONEAPP_PHOENIXRTOS_PORTS="${ONEAPP_PHOENIXRTOS_PORTS:-8080:8080}"
ONEAPP_PHOENIXRTOS_VOLUMES="${ONEAPP_PHOENIXRTOS_VOLUMES:-}"
ONEAPP_PHOENIXRTOS_ENV_VARS="${ONEAPP_PHOENIXRTOS_ENV_VARS:-}"
ONEAPP_PHOENIXRTOS_COMMAND="${ONEAPP_PHOENIXRTOS_COMMAND:-}"
ONEAPP_DOCKER_REGISTRY_URL="${ONEAPP_DOCKER_REGISTRY_URL:-}"
ONEAPP_DOCKER_REGISTRY_USER="${ONEAPP_DOCKER_REGISTRY_USER:-}"
ONEAPP_DOCKER_REGISTRY_PASSWORD="${ONEAPP_DOCKER_REGISTRY_PASSWORD:-}"
ONEAPP_DOCKER_COMPOSE_VERSION="${ONEAPP_DOCKER_COMPOSE_VERSION:-2.24.0}"
ONEAPP_DOCKER_DAEMON_CONFIG="${ONEAPP_DOCKER_DAEMON_CONFIG:-}"
ONEAPP_ENABLE_DOCKER_BUILDX="${ONEAPP_ENABLE_DOCKER_BUILDX:-yes}"
ONEAPP_DOCKER_LOG_DRIVER="${ONEAPP_DOCKER_LOG_DRIVER:-json-file}"
ONEAPP_DOCKER_LOG_MAX_SIZE="${ONEAPP_DOCKER_LOG_MAX_SIZE:-10m}"
ONEAPP_DOCKER_LOG_MAX_FILE="${ONEAPP_DOCKER_LOG_MAX_FILE:-3}"

# Docker version to install (following lithops pattern)
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"

# Phoenix RTOS Docker image configuration
PHOENIXRTOS_DOCKER_IMAGE="pablodelarco/phoenix-rtos-one"
PHOENIXRTOS_DOCKER_TAG="latest"

### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Phoenix RTOS Docker Service - KVM'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Phoenix RTOS appliance running in Docker on Ubuntu 22.04 LTS'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Phoenix RTOS appliance that runs the Phoenix RTOS operating system in a Docker container
on Ubuntu 22.04 LTS with Docker pre-installed and configured.

Phoenix RTOS is a scalable real-time operating system for IoT. This appliance provides
an easy way to run and experiment with Phoenix RTOS using Docker containerization.

Features:
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- Phoenix RTOS (pablodelarco/phoenix-rtos-one:latest) container ready to run
- Configurable port mappings and volume mounts
- Docker Compose support for complex deployments
- Optional custom Docker registry authentication
- Configurable Docker daemon settings
- Docker Buildx plugin support
- Customizable logging configuration

After deploying the appliance, Phoenix RTOS will be running in a Docker container.
You can access it via the configured ports (default: 8080). Check the status of the
deployment in /etc/one-appliance/status and view logs in /var/log/one-appliance/.

**NOTE: The appliance supports reconfiguration. Modifying context variables
will trigger service reconfiguration on the next boot.**
EOF
)

# Reconfiguration support
ONE_SERVICE_RECONFIGURABLE=true

###############################################################################
###############################################################################
###############################################################################

# The following functions will be called by the appliance service manager at
# the different stages of the appliance life cycles. They must exist
# https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle

#
# Mandatory Functions
#

service_install()
{
    mkdir -p "$ONE_SERVICE_SETUP_DIR"
    mkdir -p "$DOCKER_DATA_DIR"

    msg info "Starting Custom Docker appliance installation"

    # Update system packages
    msg info "Updating system packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y

    # Install basic dependencies
    msg info "Installing basic dependencies"
    apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common \
                       apt-transport-https wget unzip jq

    # Install Docker
    msg info "Installing Docker Engine"
    install_docker

    # Install Docker Compose
    msg info "Installing Docker Compose"
    install_docker_compose

    # Create service metadata
    create_one_service_metadata

    # Cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    msg info "Starting Docker service configuration"

    # Configure Docker daemon
    msg info "Configuring Docker daemon"
    configure_docker_daemon

    # Configure Docker registry authentication if provided
    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" && -n "$ONEAPP_DOCKER_REGISTRY_USER" ]]; then
        msg info "Configuring Docker registry authentication"
        configure_docker_registry
    fi

    # Enable and start Docker service
    msg info "Starting Docker service"
    systemctl enable docker
    systemctl start docker

    # Verify Docker installation
    verify_docker_installation

    # Pull and start Phoenix RTOS container
    msg info "Setting up Phoenix RTOS container"
    setup_phoenixrtos_container

    # Generate service report
    generate_service_report

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "Starting Docker service bootstrap"

    # Verify Docker is running
    if ! systemctl is-active --quiet docker; then
        msg info "Starting Docker service..."
        systemctl start docker
    fi

    # Check Phoenix RTOS container status
    msg info "Checking Phoenix RTOS container status"
    check_phoenixrtos_container

    msg info "BOOTSTRAP FINISHED"
    return 0
}

service_help()
{
    msg info "Phoenix RTOS Docker appliance - Ubuntu 22.04 LTS with Phoenix RTOS in Docker"
    msg info "Docker version: $(docker --version 2>/dev/null || echo 'Not available')"
    msg info "Docker Compose version: $(docker compose version --short 2>/dev/null || echo 'Not available')"
    msg info "Phoenix RTOS image: ${PHOENIXRTOS_DOCKER_IMAGE}:${PHOENIXRTOS_DOCKER_TAG}"
    msg info "Phoenix RTOS ports: ${ONEAPP_PHOENIXRTOS_PORTS}"
    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" ]]; then
        msg info "Registry configured: $ONEAPP_DOCKER_REGISTRY_URL"
    fi
    return 0
}

service_cleanup()
{
    msg info "CLEANUP logic goes here in case of install failure"
    # Stop Docker service
    systemctl stop docker 2>/dev/null || true
    # Remove Docker packages if needed
    # apt-get remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true
}

###############################################################################
###############################################################################
###############################################################################

# Helper functions

install_docker()
{
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version | cut -d' ' -f3 | sed 's/,//')
        msg info "Docker already installed: version $docker_version"
        return 0
    fi
    
    msg info "Adding Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Adding Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    msg info "Updating package lists"
    apt-get update

    msg info "Installing Docker Engine with specific version"
    if ! apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin; then
        msg error "Docker installation failed"
        exit 1
    fi

    msg info "Docker installation completed successfully"
}

install_docker_compose()
{
    # Docker Compose is now included as a plugin, but we can also install standalone version
    msg info "Docker Compose plugin is already installed with Docker"

    # Verify Docker Compose is working
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short)
        msg info "✓ Docker Compose plugin version: $compose_version"
    else
        msg warning "⚠ Docker Compose plugin not working properly"
    fi
}

configure_docker_daemon()
{
    # Create Docker daemon configuration
    mkdir -p "$DOCKER_CONFIG_DIR"

    local daemon_config=""

    if [[ -n "$ONEAPP_DOCKER_DAEMON_CONFIG" ]]; then
        # Use custom daemon configuration if provided
        msg info "Using custom Docker daemon configuration"
        daemon_config="$ONEAPP_DOCKER_DAEMON_CONFIG"
    else
        # Use default configuration
        msg info "Creating default Docker daemon configuration"
        daemon_config=$(cat <<EOF
{
    "log-driver": "$ONEAPP_DOCKER_LOG_DRIVER",
    "log-opts": {
        "max-size": "$ONEAPP_DOCKER_LOG_MAX_SIZE",
        "max-file": "$ONEAPP_DOCKER_LOG_MAX_FILE"
    },
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF
)
    fi

    echo "$daemon_config" > "$DOCKER_CONFIG_DIR/daemon.json"
    msg info "Docker daemon configuration saved to $DOCKER_CONFIG_DIR/daemon.json"
}

configure_docker_registry()
{
    # Configure Docker registry authentication
    local docker_config_dir="/root/.docker"
    mkdir -p "$docker_config_dir"

    if [[ -n "$ONEAPP_DOCKER_REGISTRY_PASSWORD" ]]; then
        msg info "Configuring Docker registry authentication for $ONEAPP_DOCKER_REGISTRY_URL"

        # Login to the registry
        echo "$ONEAPP_DOCKER_REGISTRY_PASSWORD" | docker login "$ONEAPP_DOCKER_REGISTRY_URL" \
            --username "$ONEAPP_DOCKER_REGISTRY_USER" --password-stdin

        if [[ $? -eq 0 ]]; then
            msg info "✓ Successfully authenticated with Docker registry"
        else
            msg error "✗ Failed to authenticate with Docker registry"
        fi
    fi
}

verify_docker_installation()
{
    msg info "Verifying Docker installation..."

    # Check Docker daemon
    if systemctl is-active --quiet docker; then
        msg info "✓ Docker daemon is running"
    else
        msg error "✗ Docker daemon is not running"
        return 1
    fi

    # Check Docker version
    local docker_version=$(docker --version 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        msg info "✓ Docker version: $docker_version"
    else
        msg error "✗ Docker command not available"
        return 1
    fi

    # Check Docker Compose
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short)
        msg info "✓ Docker Compose version: $compose_version"
    else
        msg warning "⚠ Docker Compose not available"
    fi

    # Check if Buildx is enabled
    if [[ "${ONEAPP_ENABLE_DOCKER_BUILDX,,}" == "yes" ]]; then
        if docker buildx version >/dev/null 2>&1; then
            msg info "✓ Docker Buildx is available"
        else
            msg warning "⚠ Docker Buildx not available"
        fi
    fi

    msg info "Docker verification completed"
}

generate_service_report()
{
    msg info "═══════════════════════════════════════════════════════════════"
    msg info "                Custom Docker Appliance Report"
    msg info "═══════════════════════════════════════════════════════════════"
    msg info ""
    msg info "✓ Installation Status: COMPLETED SUCCESSFULLY"
    msg info ""
    msg info "📋 Configuration Summary:"
    msg info "   • Base OS: Ubuntu 22.04 LTS"
    msg info "   • Docker Version: $(docker --version 2>/dev/null || echo 'Not available')"
    msg info "   • Docker Compose: $(docker compose version --short 2>/dev/null || echo 'Not available')"
    msg info "   • Log Driver: $ONEAPP_DOCKER_LOG_DRIVER"
    msg info "   • Log Max Size: $ONEAPP_DOCKER_LOG_MAX_SIZE"
    msg info "   • Log Max Files: $ONEAPP_DOCKER_LOG_MAX_FILE"

    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" ]]; then
        msg info "   • Registry: $ONEAPP_DOCKER_REGISTRY_URL"
    fi

    if [[ "${ONEAPP_ENABLE_DOCKER_BUILDX,,}" == "yes" ]]; then
        msg info "   • Docker Buildx: Enabled"
    fi

    msg info ""
    msg info "🐳 Docker Status:"
    if systemctl is-active --quiet docker; then
        msg info "   • Status: Running"
    else
        msg info "   • Status: Not running"
    fi

    msg info ""
    msg info "📚 Useful Commands:"
    msg info "   • Check Docker status: systemctl status docker"
    msg info "   • View Docker info: docker info"
    msg info "   • List images: docker images"
    msg info "   • List containers: docker ps -a"
    msg info "   • Docker logs: journalctl -u docker"
    msg info "═══════════════════════════════════════════════════════════════"

    cat > "$ONE_SERVICE_REPORT" <<EOF
[Docker Configuration]
Base OS = Ubuntu 22.04 LTS
Docker Version = $(docker --version 2>/dev/null || echo 'Not available')
Docker Compose = $(docker compose version --short 2>/dev/null || echo 'Not available')
Log Driver = $ONEAPP_DOCKER_LOG_DRIVER
Log Max Size = $ONEAPP_DOCKER_LOG_MAX_SIZE
Log Max Files = $ONEAPP_DOCKER_LOG_MAX_FILE
Registry URL = $ONEAPP_DOCKER_REGISTRY_URL
Buildx Enabled = $ONEAPP_ENABLE_DOCKER_BUILDX

[Useful Commands]
Check Docker status = systemctl status docker
View Docker info = docker info
List images = docker images
List containers = docker ps -a
Docker logs = journalctl -u docker

[Service Status]
Use 'systemctl status docker' to check Docker daemon status
Use 'docker info' to view detailed Docker system information
EOF

    chmod 600 "$ONE_SERVICE_REPORT"
}

postinstall_cleanup()
{
    msg info "Cleaning up installation files"
    apt-get autoclean
    apt-get autoremove -y
    rm -rf /var/lib/apt/lists/*

    # Clean up Docker build cache if needed
    docker system prune -f >/dev/null 2>&1 || true
}

###############################################################################
# Phoenix RTOS specific functions
###############################################################################

setup_phoenixrtos_container()
{
    local full_image="${PHOENIXRTOS_DOCKER_IMAGE}:${PHOENIXRTOS_DOCKER_TAG}"
    local container_name="phoenix-rtos-one"

    msg info "Setting up Phoenix RTOS container: $container_name"
    msg info "Using image: $full_image"

    # Stop and remove any existing Phoenix RTOS container
    if docker ps -a --filter "name=$container_name" --format "table {{.Names}}" | grep -q "$container_name"; then
        msg info "Stopping and removing existing Phoenix RTOS container"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    # Pull the Phoenix RTOS image
    msg info "Pulling Phoenix RTOS image: $full_image"
    if ! docker pull "$full_image"; then
        msg error "Failed to pull Phoenix RTOS image: $full_image"
        return 1
    fi

    # Build docker run command for Phoenix RTOS
    local docker_cmd="docker run -d --name $container_name"

    # Add restart policy
    docker_cmd="$docker_cmd --restart=unless-stopped"

    # Add port mappings
    if [[ -n "$ONEAPP_PHOENIXRTOS_PORTS" ]]; then
        IFS=',' read -ra PORTS <<< "$ONEAPP_PHOENIXRTOS_PORTS"
        for port in "${PORTS[@]}"; do
            docker_cmd="$docker_cmd -p $port"
        done
    fi

    # Add volume mappings
    if [[ -n "$ONEAPP_PHOENIXRTOS_VOLUMES" ]]; then
        IFS=',' read -ra VOLUMES <<< "$ONEAPP_PHOENIXRTOS_VOLUMES"
        for volume in "${VOLUMES[@]}"; do
            # Create host directory if it doesn't exist
            local host_path=$(echo "$volume" | cut -d':' -f1)
            if [[ "$host_path" == /* ]]; then
                mkdir -p "$host_path"
            fi
            docker_cmd="$docker_cmd -v $volume"
        done
    fi

    # Add environment variables
    if [[ -n "$ONEAPP_PHOENIXRTOS_ENV_VARS" ]]; then
        IFS=',' read -ra ENV_VARS <<< "$ONEAPP_PHOENIXRTOS_ENV_VARS"
        for env_var in "${ENV_VARS[@]}"; do
            docker_cmd="$docker_cmd -e $env_var"
        done
    fi

    # Add management labels
    docker_cmd="$docker_cmd --label oneapp.managed=true"
    docker_cmd="$docker_cmd --label oneapp.service=phoenix-rtos"
    docker_cmd="$docker_cmd --label oneapp.image=$PHOENIXRTOS_DOCKER_IMAGE"
    docker_cmd="$docker_cmd --label oneapp.tag=$PHOENIXRTOS_DOCKER_TAG"

    # Add image
    docker_cmd="$docker_cmd $full_image"

    # Add custom command if specified
    if [[ -n "$ONEAPP_PHOENIXRTOS_COMMAND" ]]; then
        docker_cmd="$docker_cmd $ONEAPP_PHOENIXRTOS_COMMAND"
    fi

    msg info "Executing: $docker_cmd"

    # Execute the command
    if eval "$docker_cmd"; then
        msg info "✓ Phoenix RTOS container created and started successfully"

        # Wait a moment and check if container is still running
        sleep 5
        if docker ps --filter "name=$container_name" --format "table {{.Names}}" | grep -q "$container_name"; then
            msg info "✓ Phoenix RTOS container is running"

            # Show container logs for verification
            msg info "Phoenix RTOS container logs (last 10 lines):"
            docker logs --tail 10 "$container_name" 2>&1 | while read line; do
                msg info "  $line"
            done
        else
            msg error "✗ Phoenix RTOS container stopped unexpectedly"
            msg info "Container logs:"
            docker logs "$container_name" 2>&1 | tail -20 | while read line; do
                msg info "  $line"
            done
            return 1
        fi
    else
        msg error "✗ Failed to create Phoenix RTOS container"
        return 1
    fi
}

check_phoenixrtos_container()
{
    local container_name="phoenix-rtos-one"

    if docker ps --filter "name=$container_name" --format "table {{.Names}}" | grep -q "$container_name"; then
        msg info "✓ Phoenix RTOS container is running"

        # Show container status
        local status=$(docker ps --filter "name=$container_name" --format "{{.Status}}")
        msg info "  Status: $status"

        # Show port mappings
        local ports=$(docker ps --filter "name=$container_name" --format "{{.Ports}}")
        if [[ -n "$ports" ]]; then
            msg info "  Ports: $ports"
        fi
    else
        msg warning "⚠ Phoenix RTOS container is not running"

        # Try to start it if it exists
        if docker ps -a --filter "name=$container_name" --format "table {{.Names}}" | grep -q "$container_name"; then
            msg info "Attempting to start Phoenix RTOS container"
            if docker start "$container_name"; then
                msg info "✓ Phoenix RTOS container started successfully"
            else
                msg error "✗ Failed to start Phoenix RTOS container"
            fi
        else
            msg warning "Phoenix RTOS container does not exist"
        fi
    fi
}
