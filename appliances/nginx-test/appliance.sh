#!/usr/bin/env bash

# -------------------------------------------------------------------------- #
# Copyright 2002-2025, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may  #
# not use this file except in compliance with the License. You may obtain   #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'DOCKER_IMAGE_PORTS'          'configure' 'Port mappings for container (e.g., 8080:8080)'            'O|text'
    'DOCKER_IMAGE_VOLUMES'        'configure' 'Volume mappings for container'                             'O|text'
    'DOCKER_IMAGE_ENV_VARS'       'configure' 'Environment variables for container'                       'O|text'
    'DOCKER_IMAGE_COMMAND'        'configure' 'Custom command to run in container'                        'O|text'
    'DOCKER_REGISTRY_URL'         'configure' 'Custom Docker registry URL (optional)'                    'O|text'
    'DOCKER_REGISTRY_USER'        'configure' 'Docker registry username (optional)'                      'O|text'
    'DOCKER_REGISTRY_PASSWORD'    'configure' 'Docker registry password (optional)'                      'O|password'
    'DOCKER_COMPOSE_VERSION'      'configure' 'Docker Compose version to install'                        'O|text'
    'DOCKER_DAEMON_CONFIG'        'configure' 'Custom Docker daemon configuration (JSON)'                'O|text'
    'ENABLE_DOCKER_BUILDX'        'configure' 'Enable Docker Buildx plugin (yes/no)'                     'O|boolean'
    'DOCKER_LOG_DRIVER'           'configure' 'Docker logging driver (json-file, syslog, etc.)'          'O|text'
    'DOCKER_LOG_MAX_SIZE'         'configure' 'Maximum size of log files'                                 'O|text'
    'DOCKER_LOG_MAX_FILE'         'configure' 'Maximum number of log files'                               'O|text'
)

# Default values
ONEAPP_DOCKER_IMAGE_PORTS="${ONEAPP_DOCKER_IMAGE_PORTS:-80:80,443:443}"
ONEAPP_DOCKER_IMAGE_VOLUMES="${ONEAPP_DOCKER_IMAGE_VOLUMES:-}"
ONEAPP_DOCKER_IMAGE_ENV_VARS="${ONEAPP_DOCKER_IMAGE_ENV_VARS:-}"
ONEAPP_DOCKER_IMAGE_COMMAND="${ONEAPP_DOCKER_IMAGE_COMMAND:-}"
ONEAPP_DOCKER_REGISTRY_URL="${ONEAPP_DOCKER_REGISTRY_URL:-}"
ONEAPP_DOCKER_REGISTRY_USER="${ONEAPP_DOCKER_REGISTRY_USER:-}"
ONEAPP_DOCKER_REGISTRY_PASSWORD="${ONEAPP_DOCKER_REGISTRY_PASSWORD:-}"
ONEAPP_DOCKER_COMPOSE_VERSION="${ONEAPP_DOCKER_COMPOSE_VERSION:-2.24.0}"
ONEAPP_DOCKER_DAEMON_CONFIG="${ONEAPP_DOCKER_DAEMON_CONFIG:-}"
ONEAPP_ENABLE_DOCKER_BUILDX="${ONEAPP_ENABLE_DOCKER_BUILDX:-yes}"
ONEAPP_DOCKER_LOG_DRIVER="${ONEAPP_DOCKER_LOG_DRIVER:-json-file}"
ONEAPP_DOCKER_LOG_MAX_SIZE="${ONEAPP_DOCKER_LOG_MAX_SIZE:-10m}"
ONEAPP_DOCKER_LOG_MAX_FILE="${ONEAPP_DOCKER_LOG_MAX_FILE:-3}"

# Docker version to install
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"

# Container configuration
DOCKER_IMAGE="nginx:latest"
CONTAINER_NAME="nginx-container"

# Appliance metadata
ONE_SERVICE_NAME='Nginx Docker Service - KVM'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='nginx running in Docker on Ubuntu 22.04 LTS'
ONE_SERVICE_DESCRIPTION=$(cat <<EOD
nginx running in Docker on Ubuntu 22.04 LTS

This appliance provides:
- Ubuntu 22.04 LTS base operating system
- Docker Engine CE pre-installed and configured
- nginx:latest container ready to run
- Configurable port mappings and volume mounts
- Docker Compose support for complex deployments
- Optional custom Docker registry authentication
- Configurable Docker daemon settings
- Docker Buildx plugin support
- Customizable logging configuration

After deploying the appliance, nginx will be running in a Docker container.
You can access it via the configured ports (default: 80:80,443:443). Check the status of the
deployment in /etc/one-appliance/status and view logs in /var/log/one-appliance/.

**NOTE: The appliance supports reconfiguration. Modifying context variables
will trigger service reconfiguration on the next boot.**
EOD
)

###############################################################################
# Service implementation
###############################################################################

service_install()
{
    msg info "INSTALLATION STARTED"

    # Update system packages
    msg info "Updating system packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y

    # Install basic dependencies
    msg info "Installing basic dependencies"
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        unzip \
        wget \
        jq

    # Install Docker Engine
    msg info "Installing Docker Engine"
    install_docker

    # Install Docker Compose
    msg info "Installing Docker Compose"
    install_docker_compose

    # Cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    msg info "CONFIGURATION STARTED"

    # Configure Docker daemon
    configure_docker_daemon

    # Configure Docker registry authentication
    configure_docker_registry

    # Enable and start Docker service
    systemctl enable docker
    systemctl start docker

    # Verify Docker installation
    verify_docker_installation

    # Pull and start container
    msg info "Setting up nginx container"
    setup_container

    # Generate service report
    generate_service_report

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "BOOTSTRAP STARTED"

    # Check container status
    msg info "Checking nginx container status"
    check_container

    msg info "BOOTSTRAP FINISHED"
    return 0
}

service_help()
{
    msg info "Nginx Docker appliance - Ubuntu 22.04 LTS with nginx in Docker"
    msg info "Docker version: $(docker --version 2>/dev/null || echo 'Not available')"
    msg info "Docker Compose version: $(docker compose version --short 2>/dev/null || echo 'Not available')"
    msg info "Nginx image: ${DOCKER_IMAGE}"
    msg info "Nginx ports: ${ONEAPP_DOCKER_IMAGE_PORTS}"
    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" ]]; then
        msg info "Registry configured: $ONEAPP_DOCKER_REGISTRY_URL"
    fi
    return 0
}

###############################################################################
# Helper functions
###############################################################################

install_docker()
{
    msg info "Adding Docker official GPG key"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    msg info "Adding Docker repository to apt sources"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    msg info "Updating package lists"
    apt-get update

    msg info "Installing Docker Engine with specific version"
    apt-get install -y \
        containerd.io \
        docker-buildx-plugin \
        docker-ce="$DOCKER_VERSION" \
        docker-ce-cli="$DOCKER_VERSION" \
        docker-compose-plugin

    msg info "Docker installation completed successfully"
}

install_docker_compose()
{
    msg info "Docker Compose plugin is already installed with Docker"
    local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
    msg info "✓ Docker Compose plugin version: $compose_version"
}

configure_docker_daemon()
{
    msg info "Configuring Docker daemon"
    
    local daemon_config="/etc/docker/daemon.json"
    local default_config='{
        "log-driver": "'"$ONEAPP_DOCKER_LOG_DRIVER"'",
        "log-opts": {
            "max-size": "'"$ONEAPP_DOCKER_LOG_MAX_SIZE"'",
            "max-file": "'"$ONEAPP_DOCKER_LOG_MAX_FILE"'"
        },
        "storage-driver": "overlay2",
        "live-restore": true
    }'
    
    if [[ -n "$ONEAPP_DOCKER_DAEMON_CONFIG" ]]; then
        msg info "Using custom Docker daemon configuration"
        echo "$ONEAPP_DOCKER_DAEMON_CONFIG" > "$daemon_config"
    else
        msg info "Using default Docker daemon configuration"
        echo "$default_config" > "$daemon_config"
    fi
    
    msg info "✓ Docker daemon configuration applied"
}

configure_docker_registry()
{
    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" && -n "$ONEAPP_DOCKER_REGISTRY_USER" && -n "$ONEAPP_DOCKER_REGISTRY_PASSWORD" ]]; then
        msg info "Configuring Docker registry authentication"
        echo "$ONEAPP_DOCKER_REGISTRY_PASSWORD" | docker login "$ONEAPP_DOCKER_REGISTRY_URL" --username "$ONEAPP_DOCKER_REGISTRY_USER" --password-stdin
        msg info "✓ Docker registry authentication configured"
    fi
}

verify_docker_installation()
{
    msg info "Verifying Docker installation"
    
    if ! systemctl is-active --quiet docker; then
        msg error "Docker service is not running"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        msg error "Docker is not responding"
        return 1
    fi
    
    msg info "✓ Docker is installed and running correctly"
}

setup_container()
{
    local full_image="$DOCKER_IMAGE"
    
    msg info "Setting up container: $CONTAINER_NAME"
    msg info "Using image: $full_image"

    # Stop and remove any existing container
    if docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        msg info "Stopping and removing existing container"
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi

    # Pull the image
    msg info "Pulling image: $full_image"
    if ! docker pull "$full_image"; then
        msg error "Failed to pull image: $full_image"
        return 1
    fi

    # Build docker run command
    local docker_cmd="docker run -d --name $CONTAINER_NAME"
    
    # Add restart policy
    docker_cmd="$docker_cmd --restart=unless-stopped"
    
    # Add port mappings
    if [[ -n "$ONEAPP_DOCKER_IMAGE_PORTS" ]]; then
        IFS=',' read -ra PORTS <<< "$ONEAPP_DOCKER_IMAGE_PORTS"
        for port in "${PORTS[@]}"; do
            docker_cmd="$docker_cmd -p $port"
        done
    fi
    
    # Add volume mappings
    if [[ -n "$ONEAPP_DOCKER_IMAGE_VOLUMES" ]]; then
        IFS=',' read -ra VOLUMES <<< "$ONEAPP_DOCKER_IMAGE_VOLUMES"
        for volume in "${VOLUMES[@]}"; do
            local host_path=$(echo "$volume" | cut -d':' -f1)
            if [[ "$host_path" == /* ]]; then
                mkdir -p "$host_path"
            fi
            docker_cmd="$docker_cmd -v $volume"
        done
    fi
    
    # Add environment variables
    if [[ -n "$ONEAPP_DOCKER_IMAGE_ENV_VARS" ]]; then
        IFS=',' read -ra ENV_VARS <<< "$ONEAPP_DOCKER_IMAGE_ENV_VARS"
        for env_var in "${ENV_VARS[@]}"; do
            docker_cmd="$docker_cmd -e $env_var"
        done
    fi
    
    # Add management labels
    docker_cmd="$docker_cmd --label oneapp.managed=true"
    docker_cmd="$docker_cmd --label oneapp.service=nginx"
    docker_cmd="$docker_cmd --label oneapp.image=$DOCKER_IMAGE"
    
    # Add image
    docker_cmd="$docker_cmd $full_image"
    
    # Add custom command if specified
    if [[ -n "$ONEAPP_DOCKER_IMAGE_COMMAND" ]]; then
        docker_cmd="$docker_cmd $ONEAPP_DOCKER_IMAGE_COMMAND"
    fi
    
    msg info "Executing: $docker_cmd"
    
    # Execute the command
    if eval "$docker_cmd"; then
        msg info "✓ Container created and started successfully"
        
        # Wait a moment and check if container is still running
        sleep 5
        if docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
            msg info "✓ Container is running"
            
            # Show container logs for verification
            msg info "Container logs (last 10 lines):"
            docker logs --tail 10 "$CONTAINER_NAME" 2>&1 | while read line; do
                msg info "  $line"
            done
        else
            msg error "✗ Container stopped unexpectedly"
            msg info "Container logs:"
            docker logs "$CONTAINER_NAME" 2>&1 | tail -20 | while read line; do
                msg info "  $line"
            done
            return 1
        fi
    else
        msg error "✗ Failed to create container"
        return 1
    fi
}

check_container()
{
    if docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        msg info "✓ Container is running"
        
        local status=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
        msg info "  Status: $status"
        
        local ports=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Ports}}")
        if [[ -n "$ports" ]]; then
            msg info "  Ports: $ports"
        fi
    else
        msg warning "⚠ Container is not running"
        
        if docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
            msg info "Attempting to start container"
            if docker start "$CONTAINER_NAME"; then
                msg info "✓ Container started successfully"
            else
                msg error "✗ Failed to start container"
            fi
        else
            msg warning "Container does not exist"
        fi
    fi
}

generate_service_report()
{
    msg info "Generating service report"
    
    local report_file="/etc/one-appliance/status"
    cat > "$report_file" << EOD
Service: Nginx Docker
Status: Configured
Docker Version: $(docker --version 2>/dev/null || echo 'Unknown')
Docker Compose Version: $(docker compose version --short 2>/dev/null || echo 'Unknown')
Container Image: $DOCKER_IMAGE
Container Name: $CONTAINER_NAME
Container Status: $(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}" 2>/dev/null || echo 'Not running')
Ports: $ONEAPP_DOCKER_IMAGE_PORTS
Configuration Time: $(date)
EOD
    
    msg info "✓ Service report generated"
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
