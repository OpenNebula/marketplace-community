#!/usr/bin/env bash

# OpenNebula Docker Appliance for redis:alpine
# Generated automatically

ONE_SERVICE_PARAMS=(
    'DOCKER_IMAGE_PORTS'          'configure' 'Port mappings for container (e.g., 8080:8080)'            'O|text'
    'DOCKER_IMAGE_VOLUMES'        'configure' 'Volume mappings for container'                             'O|text'
    'DOCKER_IMAGE_ENV_VARS'       'configure' 'Environment variables for container'                       'O|text'
    'DOCKER_IMAGE_COMMAND'        'configure' 'Custom command to run in container'                        'O|text'
    'DOCKER_REGISTRY_URL'         'configure' 'Custom Docker registry URL (optional)'                    'O|text'
    'DOCKER_REGISTRY_USER'        'configure' 'Docker registry username (optional)'                      'O|text'
    'DOCKER_REGISTRY_PASSWORD'    'configure' 'Docker registry password (optional)'                      'O|password'
)

# Default values
ONEAPP_DOCKER_IMAGE_PORTS="${ONEAPP_DOCKER_IMAGE_PORTS:-6379:6379}"
ONEAPP_DOCKER_IMAGE_VOLUMES="${ONEAPP_DOCKER_IMAGE_VOLUMES:-}"
ONEAPP_DOCKER_IMAGE_ENV_VARS="${ONEAPP_DOCKER_IMAGE_ENV_VARS:-}"
ONEAPP_DOCKER_IMAGE_COMMAND="${ONEAPP_DOCKER_IMAGE_COMMAND:-}"
ONEAPP_DOCKER_REGISTRY_URL="${ONEAPP_DOCKER_REGISTRY_URL:-}"
ONEAPP_DOCKER_REGISTRY_USER="${ONEAPP_DOCKER_REGISTRY_USER:-}"
ONEAPP_DOCKER_REGISTRY_PASSWORD="${ONEAPP_DOCKER_REGISTRY_PASSWORD:-}"

# Container configuration
DOCKER_IMAGE="redis:alpine"
CONTAINER_NAME="redis-container"

# Appliance metadata
ONE_SERVICE_NAME='Redis Docker Service - KVM'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='redis running in Docker on Ubuntu 22.04 LTS'

service_install() {
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
        software-properties-common

    # Install Docker Engine
    msg info "Installing Docker Engine"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y containerd.io docker-buildx-plugin docker-ce docker-ce-cli docker-compose-plugin

    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure() {
    msg info "CONFIGURATION STARTED"

    # Enable and start Docker service
    systemctl enable docker
    systemctl start docker

    # Configure Docker registry authentication if provided
    if [[ -n "$ONEAPP_DOCKER_REGISTRY_URL" && -n "$ONEAPP_DOCKER_REGISTRY_USER" && -n "$ONEAPP_DOCKER_REGISTRY_PASSWORD" ]]; then
        msg info "Configuring Docker registry authentication"
        echo "$ONEAPP_DOCKER_REGISTRY_PASSWORD" | docker login "$ONEAPP_DOCKER_REGISTRY_URL" --username "$ONEAPP_DOCKER_REGISTRY_USER" --password-stdin
    fi

    # Pull and start container
    msg info "Setting up $CONTAINER_NAME container"
    setup_container

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap() {
    msg info "BOOTSTRAP STARTED"
    
    # Check container status
    check_container

    msg info "BOOTSTRAP FINISHED"
    return 0
}

service_help() {
    msg info "Redis Docker appliance - Ubuntu 22.04 LTS with redis in Docker"
    msg info "Docker image: $DOCKER_IMAGE"
    msg info "Container ports: $ONEAPP_DOCKER_IMAGE_PORTS"
    return 0
}

setup_container() {
    local full_image="$DOCKER_IMAGE"
    
    msg info "Setting up container: $CONTAINER_NAME"
    msg info "Using image: $full_image"

    # Stop and remove any existing container
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    # Pull the image
    msg info "Pulling image: $full_image"
    docker pull "$full_image"

    # Build docker run command
    local docker_cmd="docker run -d --name $CONTAINER_NAME --restart=unless-stopped"
    
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
    
    # Add image and command
    docker_cmd="$docker_cmd $full_image"
    if [[ -n "$ONEAPP_DOCKER_IMAGE_COMMAND" ]]; then
        docker_cmd="$docker_cmd $ONEAPP_DOCKER_IMAGE_COMMAND"
    fi
    
    msg info "Executing: $docker_cmd"
    eval "$docker_cmd"
    
    # Wait and verify
    sleep 5
    if docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        msg info "✓ Container is running"
    else
        msg error "✗ Container failed to start"
        docker logs "$CONTAINER_NAME" || true
    fi
}

check_container() {
    if docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        msg info "✓ Container is running"
        local status=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
        msg info "  Status: $status"
    else
        msg warning "⚠ Container is not running"
        docker start "$CONTAINER_NAME" 2>/dev/null || msg error "Failed to start container"
    fi
}
