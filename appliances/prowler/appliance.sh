#!/usr/bin/env bash

# Prowler Security Platform - Full App Appliance
# Multi-container deployment with UI, API, Database, and Workers
# https://github.com/prowler-cloud/prowler

set -o errexit -o pipefail

### Configuration ##########################################################

PROWLER_DATA_DIR="/opt/prowler"
PROWLER_COMPOSE_FILE="${PROWLER_DATA_DIR}/docker-compose.yml"
PROWLER_ENV_FILE="${PROWLER_DATA_DIR}/.env"
PASSWORD_LENGTH=32
ONE_SERVICE_SETUP_DIR="/opt/one-appliance"

### CONTEXT SECTION ##########################################################

ONE_SERVICE_PARAMS=(
    'ONEAPP_PROWLER_ADMIN_EMAIL'     'configure' 'Admin email for Prowler UI'                    'O|text'
    'ONEAPP_PROWLER_ADMIN_PASSWORD'  'configure' 'Admin password for Prowler UI'                 'O|password'
    'ONEAPP_PROWLER_UI_PORT'         'configure' 'Prowler UI port'                               'O|text'
    'ONEAPP_PROWLER_API_PORT'        'configure' 'Prowler API port'                              'O|text'
    'ONEAPP_PROWLER_DB_PASSWORD'     'configure' 'PostgreSQL database password'                  'O|password'
    'ONEAPP_PROWLER_SECRET_KEY'      'configure' 'Django secret key for API'                     'O|password'
    'ONEAPP_PROWLER_AUTH_SECRET'     'configure' 'Auth secret for UI sessions'                   'O|password'
    'ONEAPP_PROWLER_VERSION'         'configure' 'Prowler version tag (stable/latest)'           'O|text'
)

# Default values (passwords are generated in service_configure if not set)
ONEAPP_PROWLER_UI_PORT="${ONEAPP_PROWLER_UI_PORT:-3000}"
ONEAPP_PROWLER_API_PORT="${ONEAPP_PROWLER_API_PORT:-8080}"
ONEAPP_PROWLER_VERSION="${ONEAPP_PROWLER_VERSION:-stable}"

### Appliance metadata ###############################################

ONE_SERVICE_NAME='Prowler Security Platform'
ONE_SERVICE_VERSION='5.16.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Open-source cloud security platform for AWS, Azure, GCP, and Kubernetes'
ONE_SERVICE_DESCRIPTION='Prowler is the most widely used open-source cloud security platform. It automates security assessments and compliance across any cloud environment with over 500+ security checks.'
ONE_SERVICE_RECONFIGURABLE=true

###############################################################################
# APPLIANCE LIFECYCLE FUNCTIONS
###############################################################################

service_install()
{
    msg info "Installing Prowler Security Platform dependencies..."

    export DEBIAN_FRONTEND=noninteractive

    # Wait for any existing apt processes to finish and disable unattended-upgrades
    msg info "Waiting for apt locks to be released..."
    wait_for_apt_lock

    # Disable and stop unattended-upgrades to prevent interference
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true
    apt-get remove -y unattended-upgrades 2>/dev/null || true

    # Update system
    apt-get update -y
    apt-get upgrade -y

    # Install prerequisites
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        jq \
        apache2-utils \
        python3 \
        python3-cryptography

    # Install Docker
    install_docker

    # Install Docker Compose plugin
    apt-get install -y docker-compose-plugin

    # Create Prowler directories
    mkdir -p "${PROWLER_DATA_DIR}"
    mkdir -p "${PROWLER_DATA_DIR}/_data/api"
    mkdir -p "${PROWLER_DATA_DIR}/_data/postgres"
    mkdir -p "${PROWLER_DATA_DIR}/_data/valkey"
    mkdir -p "${PROWLER_DATA_DIR}/_data/neo4j"

    # The API container runs as user prowler (UID 1000). The _data/api
    # volume is mounted at /home/prowler/.config/prowler-api where the
    # app writes JWT keys at startup. Without this chown the container
    # crashes with PermissionError on jwt_private.pem.
    chown -R 1000:1000 "${PROWLER_DATA_DIR}/_data/api"

    # Pull Prowler images during install to speed up first boot
    msg info "Pulling Prowler Docker images (this may take a few minutes)..."
    docker pull prowlercloud/prowler-api:stable || true
    docker pull prowlercloud/prowler-ui:stable || true
    docker pull prowlercloud/prowler-mcp:stable || true
    docker pull postgres:16.3-alpine3.20 || true
    docker pull valkey/valkey:7-alpine3.19 || true
    docker pull graphstack/dozerdb:5.26.3.0 || true

    # Configure console autologin
    configure_console_autologin

    # Create welcome message
    create_welcome_message

    # Cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    msg info "Configuring Prowler Security Platform..."

    # Ensure DNS is configured (virt-sysprep may delete /etc/resolv.conf)
    configure_dns

    # Generate passwords/keys if not set
    if [ -z "${ONEAPP_PROWLER_DB_PASSWORD}" ]; then
        ONEAPP_PROWLER_DB_PASSWORD=$(gen_password ${PASSWORD_LENGTH})
    fi
    if [ -z "${ONEAPP_PROWLER_SECRET_KEY}" ]; then
        # Django secrets key must be a valid Fernet key
        ONEAPP_PROWLER_SECRET_KEY=$(gen_fernet_key)
    fi
    if [ -z "${ONEAPP_PROWLER_AUTH_SECRET}" ]; then
        ONEAPP_PROWLER_AUTH_SECRET=$(gen_password ${PASSWORD_LENGTH})
    fi

    # Get the VM's IP address
    VM_IP=$(get_local_ip)

    # Create .env file
    create_env_file

    # Create docker-compose.yml
    create_docker_compose_file

    # Save credentials to report file
    cat > "$ONE_SERVICE_REPORT" <<EOF
[Prowler Security Platform]

Web Interface: http://${VM_IP}:${ONEAPP_PROWLER_UI_PORT}
API Endpoint:  http://${VM_IP}:${ONEAPP_PROWLER_API_PORT}/api/v1

Sign up with your email at the web interface to create an admin account.

[Database Credentials]
PostgreSQL User: prowler
PostgreSQL Password: ${ONEAPP_PROWLER_DB_PASSWORD}
PostgreSQL Database: prowler_db

[Service Management]
Start:   cd ${PROWLER_DATA_DIR} && docker compose up -d
Stop:    cd ${PROWLER_DATA_DIR} && docker compose down
Logs:    cd ${PROWLER_DATA_DIR} && docker compose logs -f
Status:  cd ${PROWLER_DATA_DIR} && docker compose ps

EOF

    chmod 600 "$ONE_SERVICE_REPORT"

    # Configure SSH access
    configure_ssh_access

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "Starting Prowler Security Platform..."

    cd "${PROWLER_DATA_DIR}"

    # Ensure the API data directory is writable by the prowler container
    # user (UID 1000). It writes JWT keys here on first start.
    chown -R 1000:1000 "${PROWLER_DATA_DIR}/_data/api"

    # Start all services
    docker compose up -d

    # Wait for services to be healthy
    msg info "Waiting for services to start (this may take 1-2 minutes)..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker compose ps | grep -q "healthy"; then
            # Check if API is responding
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ONEAPP_PROWLER_API_PORT}/api/v1/docs" | grep -q "200\|301\|302"; then
                msg info "Prowler API is ready!"
                break
            fi
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    # Show status
    docker compose ps

    VM_IP=$(get_local_ip)
    msg info "=============================================="
    msg info "Prowler Security Platform is ready!"
    msg info "=============================================="
    msg info "Web Interface: http://${VM_IP}:${ONEAPP_PROWLER_UI_PORT}"
    msg info "API Docs:      http://${VM_IP}:${ONEAPP_PROWLER_API_PORT}/api/v1/docs"
    msg info "=============================================="
    msg info "Sign up with your email to create an account."
    msg info "=============================================="

    msg info "BOOTSTRAP FINISHED"
    return 0
}

service_cleanup()
{
    :
}

###############################################################################
# HELPER FUNCTIONS
###############################################################################

# Wait for apt lock to be released
wait_for_apt_lock()
{
    local max_wait=120
    local wait_time=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            msg warning "Timeout waiting for apt lock, attempting to kill blocking processes..."
            pkill -9 -f unattended-upgrade 2>/dev/null || true
            pkill -9 -f apt 2>/dev/null || true
            sleep 2
            break
        fi
        msg info "Waiting for apt lock... ($wait_time/$max_wait seconds)"
        sleep 5
        wait_time=$((wait_time + 5))
    done
}

# Configure DNS nameservers
# This is critical for pulling Docker images from external registries
configure_dns()
{
    msg info "Checking DNS configuration..."

    # Check if DNS is already working
    if getent hosts google.com > /dev/null 2>&1; then
        msg info "DNS is already working"
        return 0
    fi

    # If resolv.conf is empty, missing, or has no valid nameservers
    if [ ! -s /etc/resolv.conf ] || ! grep -q "^nameserver" /etc/resolv.conf 2>/dev/null; then
        msg info "Setting up DNS nameservers (fallback configuration)"
        cat > /etc/resolv.conf << 'EOF'
# Fallback DNS configuration for Prowler
# Added by OpenNebula appliance service
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF
    fi

    # Verify DNS is now working
    if getent hosts google.com > /dev/null 2>&1; then
        msg info "DNS configuration successful"
    else
        msg warning "DNS may not be fully configured - container startup might fail"
    fi

    return 0
}

install_docker()
{
    msg info "Installing Docker Engine..."

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    msg info "Docker installed successfully"
}

create_env_file()
{
    msg info "Creating Prowler environment configuration..."

    # Generate Neo4j password if not set
    local NEO4J_PASSWORD
    NEO4J_PASSWORD=$(gen_password 16)

    # Use the VM's actual IP so the UI redirects work from any client
    local HOST_IP
    HOST_IP=$(get_local_ip)

    cat > "${PROWLER_ENV_FILE}" <<EOF
# Prowler Security Platform Configuration
# Generated by OpenNebula Appliance

# UI Configuration
PROWLER_UI_VERSION=${ONEAPP_PROWLER_VERSION}
AUTH_URL=http://${HOST_IP}:${ONEAPP_PROWLER_UI_PORT}
API_BASE_URL=http://prowler-api:${ONEAPP_PROWLER_API_PORT}/api/v1
NEXT_PUBLIC_API_BASE_URL=http://${HOST_IP}:${ONEAPP_PROWLER_API_PORT}/api/v1
NEXT_PUBLIC_API_DOCS_URL=http://prowler-api:${ONEAPP_PROWLER_API_PORT}/api/v1/docs
AUTH_TRUST_HOST=true
UI_PORT=${ONEAPP_PROWLER_UI_PORT}
AUTH_SECRET=${ONEAPP_PROWLER_AUTH_SECRET}

# MCP Server Configuration
PROWLER_MCP_VERSION=${ONEAPP_PROWLER_VERSION}
PROWLER_MCP_SERVER_URL=http://mcp-server:8000/mcp

# API Configuration
PROWLER_API_VERSION=${ONEAPP_PROWLER_VERSION}
POSTGRES_HOST=postgres-db
POSTGRES_PORT=5432
POSTGRES_ADMIN_USER=prowler_admin
POSTGRES_ADMIN_PASSWORD=${ONEAPP_PROWLER_DB_PASSWORD}
POSTGRES_USER=prowler
POSTGRES_PASSWORD=${ONEAPP_PROWLER_DB_PASSWORD}
POSTGRES_DB=prowler_db

# Neo4j Configuration (for Attack Paths)
NEO4J_HOST=neo4j
NEO4J_PORT=7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD}
NEO4J_DBMS_MAX__DATABASES=1000000
NEO4J_SERVER_MEMORY_PAGECACHE_SIZE=512M
NEO4J_SERVER_MEMORY_HEAP_INITIAL__SIZE=512M
NEO4J_SERVER_MEMORY_HEAP_MAX__SIZE=512M
NEO4J_POC_EXPORT_FILE_ENABLED=true
NEO4J_APOC_IMPORT_FILE_ENABLED=true
NEO4J_APOC_IMPORT_FILE_USE_NEO4J_CONFIG=true
NEO4J_PLUGINS=["apoc"]
NEO4J_DBMS_SECURITY_PROCEDURES_ALLOWLIST=apoc.*
NEO4J_DBMS_SECURITY_PROCEDURES_UNRESTRICTED=apoc.*
NEO4J_DBMS_CONNECTOR_BOLT_LISTEN_ADDRESS=0.0.0.0:7687
NEO4J_INSERT_BATCH_SIZE=500

# Task Queue Configuration
TASK_RETRY_DELAY_SECONDS=0.1
TASK_RETRY_ATTEMPTS=5

# Cache Configuration
VALKEY_HOST=valkey
VALKEY_PORT=6379
VALKEY_DB=0

# Django Configuration
DJANGO_TMP_OUTPUT_DIRECTORY=/tmp/prowler_api_output
DJANGO_FINDINGS_BATCH_SIZE=1000
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,prowler-api,${HOST_IP}
DJANGO_BIND_ADDRESS=0.0.0.0
DJANGO_PORT=${ONEAPP_PROWLER_API_PORT}
DJANGO_DEBUG=False
DJANGO_SETTINGS_MODULE=config.django.production
DJANGO_LOGGING_FORMATTER=human_readable
DJANGO_LOGGING_LEVEL=INFO
DJANGO_WORKERS=4
DJANGO_ACCESS_TOKEN_LIFETIME=30
DJANGO_REFRESH_TOKEN_LIFETIME=1440
DJANGO_CACHE_MAX_AGE=3600
DJANGO_STALE_WHILE_REVALIDATE=60
DJANGO_MANAGE_DB_PARTITIONS=True
DJANGO_SECRETS_ENCRYPTION_KEY=${ONEAPP_PROWLER_SECRET_KEY}
DJANGO_BROKER_VISIBILITY_TIMEOUT=86400
DJANGO_THROTTLE_TOKEN_OBTAIN=50/minute

# Version Info
NEXT_PUBLIC_PROWLER_RELEASE_VERSION=v5.16.0
EOF

    chmod 600 "${PROWLER_ENV_FILE}"
}

create_docker_compose_file()
{
    msg info "Creating Docker Compose configuration..."

    cat > "${PROWLER_COMPOSE_FILE}" <<'COMPOSEFILE'
# Prowler Security Platform - Docker Compose Configuration
# Based on official Prowler docker-compose.yml
# https://github.com/prowler-cloud/prowler

services:
  postgres:
    image: postgres:16.3-alpine3.20
    hostname: "postgres-db"
    environment:
      POSTGRES_USER: ${POSTGRES_ADMIN_USER}
      POSTGRES_PASSWORD: ${POSTGRES_ADMIN_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - ./_data/postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:${POSTGRES_PORT:-5432}"
    healthcheck:
      test: ["CMD-SHELL", "sh -c 'pg_isready -U ${POSTGRES_ADMIN_USER} -d ${POSTGRES_DB}'"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  valkey:
    image: valkey/valkey:7-alpine3.19
    hostname: "valkey"
    volumes:
      - ./_data/valkey:/data
    ports:
      - "${VALKEY_PORT:-6379}:6379"
    healthcheck:
      test: ["CMD-SHELL", "sh -c 'valkey-cli ping'"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped

  neo4j:
    image: graphstack/dozerdb:5.26.3.0
    hostname: "neo4j"
    volumes:
      - ./_data/neo4j:/data
    environment:
      - NEO4J_AUTH=${NEO4J_USER}/${NEO4J_PASSWORD}
      - NEO4J_dbms_max__databases=${NEO4J_DBMS_MAX__DATABASES:-1000000}
      - NEO4J_server_memory_pagecache_size=${NEO4J_SERVER_MEMORY_PAGECACHE_SIZE:-512M}
      - NEO4J_server_memory_heap_initial__size=${NEO4J_SERVER_MEMORY_HEAP_INITIAL__SIZE:-512M}
      - NEO4J_server_memory_heap_max__size=${NEO4J_SERVER_MEMORY_HEAP_MAX__SIZE:-512M}
      - apoc.export.file.enabled=${NEO4J_POC_EXPORT_FILE_ENABLED:-true}
      - apoc.import.file.enabled=${NEO4J_APOC_IMPORT_FILE_ENABLED:-true}
      - apoc.import.file.use_neo4j_config=${NEO4J_APOC_IMPORT_FILE_USE_NEO4J_CONFIG:-true}
      - "NEO4J_PLUGINS=${NEO4J_PLUGINS:-[\"apoc\"]}"
      - "NEO4J_dbms_security_procedures_allowlist=${NEO4J_DBMS_SECURITY_PROCEDURES_ALLOWLIST:-apoc.*}"
      - "NEO4J_dbms_security_procedures_unrestricted=${NEO4J_DBMS_SECURITY_PROCEDURES_UNRESTRICTED:-apoc.*}"
      - "dbms.connector.bolt.listen_address=${NEO4J_DBMS_CONNECTOR_BOLT_LISTEN_ADDRESS:-0.0.0.0:7687}"
    ports:
      - "${NEO4J_PORT:-7687}:7687"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "http://localhost:7474"]
      interval: 10s
      timeout: 10s
      retries: 10
    restart: unless-stopped

  api:
    hostname: "prowler-api"
    image: prowlercloud/prowler-api:${PROWLER_API_VERSION:-stable}
    env_file: .env
    ports:
      - "${DJANGO_PORT:-8080}:${DJANGO_PORT:-8080}"
    volumes:
      - ./_data/api:/home/prowler/.config/prowler-api
      - output:/tmp/prowler_api_output
    depends_on:
      postgres:
        condition: service_healthy
      valkey:
        condition: service_healthy
      neo4j:
        condition: service_healthy
    entrypoint:
      - "/home/prowler/docker-entrypoint.sh"
      - "prod"
    restart: unless-stopped

  ui:
    image: prowlercloud/prowler-ui:${PROWLER_UI_VERSION:-stable}
    env_file: .env
    ports:
      - "${UI_PORT:-3000}:${UI_PORT:-3000}"
    depends_on:
      mcp-server:
        condition: service_healthy
    restart: unless-stopped

  mcp-server:
    image: prowlercloud/prowler-mcp:${PROWLER_MCP_VERSION:-stable}
    environment:
      - PROWLER_MCP_TRANSPORT_MODE=http
    env_file: .env
    ports:
      - "8000:8000"
    command: ["uvicorn", "--host", "0.0.0.0", "--port", "8000"]
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:8000/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped

  worker:
    image: prowlercloud/prowler-api:${PROWLER_API_VERSION:-stable}
    env_file: .env
    volumes:
      - output:/tmp/prowler_api_output
    depends_on:
      valkey:
        condition: service_healthy
      postgres:
        condition: service_healthy
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    entrypoint:
      - "/home/prowler/docker-entrypoint.sh"
      - "worker"
    restart: unless-stopped

  worker-beat:
    image: prowlercloud/prowler-api:${PROWLER_API_VERSION:-stable}
    env_file: .env
    depends_on:
      valkey:
        condition: service_healthy
      postgres:
        condition: service_healthy
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    entrypoint:
      - "/home/prowler/docker-entrypoint.sh"
      - "beat"
    restart: unless-stopped

volumes:
  output:
    driver: local
COMPOSEFILE
}

configure_console_autologin()
{
    msg info "Configuring console autologin..."

    # Create TTY devices service
    cat > /etc/systemd/system/create-tty-devices.service << 'EOF'
[Unit]
Description=Create TTY device nodes
DefaultDependencies=no
Before=getty@tty1.service
After=systemd-tmpfiles-setup-dev.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for i in 0 1 2 3 4 5 6; do [ -e /dev/tty$i ] || mknod /dev/tty$i c 4 $i; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable create-tty-devices.service

    # Configure VNC console autologin
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Unit]
ConditionPathExists=

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I $TERM
Type=idle
EOF

    # Configure serial console autologin
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
EOF

    # Set root password
    echo "root:opennebula" | chpasswd

    # Enable getty services
    systemctl enable getty@tty1.service serial-getty@ttyS0.service
}

configure_ssh_access()
{
    msg info "Configuring SSH access..."

    local SSHD_CONFIG="/etc/ssh/sshd_config"

    # Enable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"

    # Restart SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
}

create_welcome_message()
{
    cat > /etc/profile.d/99-prowler-welcome.sh << 'EOF'
#!/bin/bash
case $- in
    *i*) ;;
      *) return;;
esac

# Get VM IP
VM_IP=$(hostname -I | awk '{print $1}')

echo "=================================================================="
echo "  Prowler Security Platform"
echo "=================================================================="
echo "  Web Interface: http://${VM_IP}:3000"
echo "  API Docs:      http://${VM_IP}:8080/api/v1/docs"
echo ""
echo "  Commands:"
echo "    prowler-status   - Show service status"
echo "    prowler-logs     - View service logs"
echo "    prowler-restart  - Restart all services"
echo ""
echo "  First time? Sign up at the web interface with your email."
echo "=================================================================="
EOF

    chmod +x /etc/profile.d/99-prowler-welcome.sh

    # Create helper commands
    cat > /usr/local/bin/prowler-status << 'EOF'
#!/bin/bash
cd /opt/prowler && docker compose ps
EOF

    cat > /usr/local/bin/prowler-logs << 'EOF'
#!/bin/bash
cd /opt/prowler && docker compose logs -f "${@}"
EOF

    cat > /usr/local/bin/prowler-restart << 'EOF'
#!/bin/bash
cd /opt/prowler && docker compose restart
EOF

    chmod +x /usr/local/bin/prowler-status
    chmod +x /usr/local/bin/prowler-logs
    chmod +x /usr/local/bin/prowler-restart
}

gen_fernet_key()
{
    # Generate a valid Fernet key (32 url-safe base64-encoded bytes)
    # Fernet keys must be exactly 32 bytes, base64 encoded
    python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null || \
    openssl rand -base64 32 | tr '+/' '-_'
}

postinstall_cleanup()
{
    msg info "Cleaning up..."
    apt-get autoremove -y
    apt-get autoclean
    rm -rf /var/lib/apt/lists/*

    # Remove NetworkManager netplan configs created during Packer build.
    # These use renderer: NetworkManager and conflict with one-context's
    # 50-one-context.yaml (renderer: networkd), preventing eth0 from
    # getting an IP address at boot.
    rm -f /etc/netplan/90-NM-*.yaml

    find /var/log -type f -exec truncate -s 0 {} \;
}
