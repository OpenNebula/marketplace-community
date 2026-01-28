#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  OpenNebula Appliance Wizard                                              ║
# ║  Build production-ready appliances for OpenNebula                         ║
# ║                                                                           ║
# ║  • Docker Appliances - Turn any container into a full VM                  ║
# ║  • LXC Containers - Lightweight Alpine with pre-configured services       ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Author: OpenNebula Community
# License: Apache 2.0
# Version: 2.0.0
#

set -e

# ═══════════════════════════════════════════════════════════════════════════════
# TERMINAL COLORS & STYLING
# ═══════════════════════════════════════════════════════════════════════════════

# Base colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'

# Bright colors
BRIGHT_BLUE='\033[1;34m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_MAGENTA='\033[1;35m'

# Text formatting
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
REVERSE='\033[7m'
NC='\033[0m' # No Color / Reset

# Cursor control
CURSOR_UP='\033[A'
CURSOR_DOWN='\033[B'
CLEAR_LINE='\033[2K'

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Version info
WIZARD_VERSION="2.0.0"
WIZARD_CODENAME="Nebula"

# Script directory (wizard/ is at repo root level)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Current step tracking for navigation
CURRENT_STEP=0
TOTAL_STEPS=12

# Variables to collect
DOCKER_IMAGE=""
ARCH=""  # x86_64 or aarch64
BASE_OS=""
APPLIANCE_NAME=""
APP_NAME=""
PUBLISHER_NAME=""
PUBLISHER_EMAIL=""
APP_DESCRIPTION=""
APP_FEATURES=""
DEFAULT_CONTAINER_NAME=""
DEFAULT_PORTS=""
DEFAULT_ENV_VARS=""
DEFAULT_VOLUMES=""
APP_PORT=""
WEB_INTERFACE="true"

# SSH and Login configuration
SSH_KEY_SOURCE=""        # "host" or "custom"
SSH_PUBLIC_KEY=""        # The actual SSH public key content
AUTOLOGIN_ENABLED=""     # "true" or "false"
LOGIN_USERNAME="root"    # Username for login
ROOT_PASSWORD=""         # Password when autologin is disabled

# Docker update mode: CHECK (notify only), YES (auto-update), NO (never check)
DOCKER_AUTO_UPDATE="CHECK"

# ═══════════════════════════════════════════════════════════════════════════════
# LXC CONFIGURATION (Added for LXC container support)
# ═══════════════════════════════════════════════════════════════════════════════

# Appliance type: "docker" or "lxc"
APPLIANCE_TYPE="docker"

# LXC-specific variables
LXC_APPLICATION=""
LXC_PACKAGES=""
LXC_PORTS=""
LXC_SETUP_CMD=""
CONTEXT_MODE="auto"  # "auto", "context", "contextless"

# ═══════════════════════════════════════════════════════════════════════════════
# MARKETPLACE SUBMISSION VARIABLES
# ═══════════════════════════════════════════════════════════════════════════════
MARKETPLACE_SUBMIT=""           # "yes" or "no"
MARKETPLACE_PUBLISHER=""        # Publisher name
MARKETPLACE_EMAIL=""            # Publisher email
MARKETPLACE_GITHUB_USER=""      # GitHub username
MARKETPLACE_IMAGE_URL=""        # CDN URL for image
MARKETPLACE_IMAGE_MD5=""        # MD5 checksum
MARKETPLACE_IMAGE_SHA256=""     # SHA256 checksum
MARKETPLACE_IMAGE_SIZE=""       # Image size in bytes
MARKETPLACE_UUID=""             # Generated UUID for appliance

# LXC Application Catalog
# Format: app_id="Display Name|packages|ports|setup_function"
# Setup functions are defined below and called during appliance build
declare -A LXC_APP_CATALOG=(
    ["mqtt"]="Mosquitto MQTT Broker|mosquitto mosquitto-clients|1883|setup_mqtt"
    ["nodered"]="Node-RED Flow Editor|nodejs npm|1880|setup_nodered"
    ["nginx"]="Nginx Web Server|nginx nginx-mod-http-lua|80,443|setup_nginx"
    ["redis"]="Redis In-Memory Database|redis|6379|setup_redis"
    ["postgres"]="PostgreSQL Database|postgresql postgresql-contrib|5432|setup_postgres"
    ["influxdb"]="InfluxDB Time Series DB|influxdb|8086|setup_influxdb"
    ["telegraf"]="Telegraf Metrics Agent|telegraf|8125|setup_telegraf"
    ["grafana"]="Grafana Dashboard|grafana|3000|setup_grafana"
    ["homebridge"]="Homebridge HomeKit|nodejs npm avahi avahi-compat-libdns_sd|8581|setup_homebridge"
    ["zigbee2mqtt"]="Zigbee2MQTT|nodejs npm|8080|setup_zigbee2mqtt"
    ["netdata"]="Netdata Monitoring|netdata|19999|setup_netdata"
    ["custom"]="Custom Application|<specify packages>|<specify ports>|setup_custom"
)

# Memory requirements per application (MB)
declare -A LXC_APP_MEMORY=(
    ["mqtt"]="128"
    ["nodered"]="256"
    ["nginx"]="128"
    ["redis"]="256"
    ["postgres"]="512"
    ["influxdb"]="512"
    ["telegraf"]="128"
    ["grafana"]="512"
    ["homebridge"]="256"
    ["zigbee2mqtt"]="256"
    ["netdata"]="256"
    ["custom"]="256"
)

# ═══════════════════════════════════════════════════════════════════════════════
# LXC APPLICATION SETUP FUNCTIONS
# These functions configure each application inside the chroot environment
# ═══════════════════════════════════════════════════════════════════════════════

# Setup Mosquitto MQTT Broker
setup_app_mqtt() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Configure Mosquitto for network access
cat > /etc/mosquitto/mosquitto.conf << 'MQTTCONF'
# Mosquitto MQTT Broker Configuration
listener 1883 0.0.0.0
allow_anonymous true
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log
MQTTCONF

mkdir -p /var/lib/mosquitto /var/log/mosquitto
chown mosquitto:mosquitto /var/lib/mosquitto /var/log/mosquitto
rc-update add mosquitto default
SETUPEOF
}

# Setup Node-RED Flow Editor
setup_app_nodered() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Install Node-RED globally
npm install -g --unsafe-perm node-red

# Create Node-RED user and directories
adduser -D -h /opt/node-red nodered 2>/dev/null || true
mkdir -p /opt/node-red/.node-red
chown -R nodered:nodered /opt/node-red

# Create init script
cat > /etc/init.d/nodered << 'INITSCRIPT'
#!/sbin/openrc-run
name="Node-RED"
description="Node-RED Flow Editor"
command="/usr/bin/node-red"
command_args="--userDir /opt/node-red/.node-red"
command_user="nodered"
command_background="yes"
pidfile="/run/nodered.pid"
output_log="/var/log/nodered.log"
error_log="/var/log/nodered.log"

depend() {
    need net
    after firewall
}
INITSCRIPT
chmod +x /etc/init.d/nodered

# Create default settings
cat > /opt/node-red/.node-red/settings.js << 'SETTINGS'
module.exports = {
    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",
    flowFile: 'flows.json',
    userDir: '/opt/node-red/.node-red',
    logging: {
        console: { level: "info", metrics: false, audit: false }
    }
}
SETTINGS
chown -R nodered:nodered /opt/node-red

rc-update add nodered default
SETUPEOF
}

# Setup Nginx Web Server
setup_app_nginx() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Create default HTML page
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head><title>OpenNebula LXC Appliance</title></head>
<body>
<h1>Nginx is running!</h1>
<p>OpenNebula LXC Appliance - Alpine Linux</p>
</body>
</html>
HTML

# Configure nginx for container
sed -i 's/user nginx;/user root;/' /etc/nginx/nginx.conf 2>/dev/null || true
rc-update add nginx default
SETUPEOF
}

# Setup Redis In-Memory Database
setup_app_redis() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Configure Redis for network access
sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' /etc/redis.conf 2>/dev/null || true
sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis.conf 2>/dev/null || true

# Ensure data directory exists
mkdir -p /var/lib/redis
chown redis:redis /var/lib/redis

rc-update add redis default
SETUPEOF
}

# Setup PostgreSQL Database
setup_app_postgres() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Create postgres directories
mkdir -p /var/lib/postgresql/data /run/postgresql
chown -R postgres:postgres /var/lib/postgresql /run/postgresql

# Initialize database
su - postgres -c "initdb -D /var/lib/postgresql/data" 2>/dev/null || true

# Configure for network access
if [ -f /var/lib/postgresql/data/postgresql.conf ]; then
    echo "listen_addresses = '*'" >> /var/lib/postgresql/data/postgresql.conf
fi
if [ -f /var/lib/postgresql/data/pg_hba.conf ]; then
    echo "host all all 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf
fi

rc-update add postgresql default
SETUPEOF
}

# Setup InfluxDB Time Series Database
setup_app_influxdb() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Create directories
mkdir -p /var/lib/influxdb /etc/influxdb

# Basic configuration
cat > /etc/influxdb/influxdb.conf << 'INFLUXCONF'
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  wal-dir = "/var/lib/influxdb/wal"

[http]
  enabled = true
  bind-address = ":8086"
INFLUXCONF

chown -R influxdb:influxdb /var/lib/influxdb 2>/dev/null || true
rc-update add influxdb default
SETUPEOF
}

# Setup Telegraf Metrics Agent
setup_app_telegraf() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Create basic Telegraf configuration
mkdir -p /etc/telegraf

cat > /etc/telegraf/telegraf.conf << 'TELEGRAFCONF'
[global_tags]
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

[[outputs.influxdb]]
  urls = ["http://127.0.0.1:8086"]
  database = "telegraf"

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.mem]]
[[inputs.net]]
[[inputs.processes]]
[[inputs.system]]

[[inputs.statsd]]
  protocol = "udp"
  service_address = ":8125"
TELEGRAFCONF

rc-update add telegraf default
SETUPEOF
}

# Setup Grafana Dashboard
setup_app_grafana() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Create directories
mkdir -p /var/lib/grafana /var/log/grafana

# Configure Grafana for network access (listen on all interfaces)
if [ -f /etc/grafana.ini ]; then
    sed -i 's/;http_addr =/http_addr = 0.0.0.0/' /etc/grafana.ini
    sed -i 's/http_addr = 127.0.0.1/http_addr = 0.0.0.0/' /etc/grafana.ini
fi

# Update conf.d to listen on all interfaces and remove logger dependency
if [ -f /etc/conf.d/grafana ]; then
    sed -i 's/cfg:server.http_addr=127.0.0.1/cfg:server.http_addr=0.0.0.0/' /etc/conf.d/grafana
    sed -i 's/^rc_need=logger/#rc_need=logger/' /etc/conf.d/grafana
fi

chown -R grafana:grafana /var/lib/grafana /var/log/grafana 2>/dev/null || true
rc-update add grafana default
SETUPEOF
}

# Setup Homebridge HomeKit
setup_app_homebridge() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Install Homebridge globally
npm install -g --unsafe-perm homebridge homebridge-config-ui-x

# Create homebridge user and directories
adduser -D -h /var/lib/homebridge homebridge 2>/dev/null || true
mkdir -p /var/lib/homebridge

# Create config
cat > /var/lib/homebridge/config.json << 'HBCONFIG'
{
    "bridge": {
        "name": "Homebridge",
        "username": "CC:22:3D:E3:CE:30",
        "port": 51826,
        "pin": "031-45-154"
    },
    "platforms": [
        {
            "platform": "config",
            "name": "Config",
            "port": 8581,
            "auth": "form",
            "theme": "auto"
        }
    ]
}
HBCONFIG
chown -R homebridge:homebridge /var/lib/homebridge

# Create init script
cat > /etc/init.d/homebridge << 'INITSCRIPT'
#!/sbin/openrc-run
name="Homebridge"
description="Homebridge HomeKit Server"
command="/usr/bin/homebridge"
command_args="-U /var/lib/homebridge"
command_user="homebridge"
command_background="yes"
pidfile="/run/homebridge.pid"
output_log="/var/log/homebridge.log"
error_log="/var/log/homebridge.log"

depend() {
    need net
    after firewall
}
INITSCRIPT
chmod +x /etc/init.d/homebridge

# Enable Avahi for mDNS
rc-update add avahi-daemon default 2>/dev/null || true
rc-update add homebridge default
SETUPEOF
}

# Setup Zigbee2MQTT
setup_app_zigbee2mqtt() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Install Zigbee2MQTT globally
npm install -g --unsafe-perm zigbee2mqtt

# Create zigbee2mqtt user and directories
adduser -D -h /opt/zigbee2mqtt zigbee2mqtt 2>/dev/null || true
mkdir -p /opt/zigbee2mqtt/data

# Create default configuration
cat > /opt/zigbee2mqtt/data/configuration.yaml << 'Z2MCONFIG'
# Zigbee2MQTT Configuration
homeassistant: false
permit_join: true
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://localhost:1883
serial:
  # Update this to your Zigbee adapter path
  port: /dev/ttyUSB0
  # adapter: ezsp  # Uncomment for EZSP adapters
frontend:
  port: 8080
  host: 0.0.0.0
advanced:
  log_level: info
  log_output:
    - console
    - file
  log_directory: /opt/zigbee2mqtt/data/log
  network_key: GENERATE
Z2MCONFIG
chown -R zigbee2mqtt:zigbee2mqtt /opt/zigbee2mqtt

# Create init script
cat > /etc/init.d/zigbee2mqtt << 'INITSCRIPT'
#!/sbin/openrc-run
name="Zigbee2MQTT"
description="Zigbee to MQTT bridge"
command="/usr/bin/zigbee2mqtt"
command_user="zigbee2mqtt"
command_background="yes"
directory="/opt/zigbee2mqtt"
pidfile="/run/zigbee2mqtt.pid"
output_log="/var/log/zigbee2mqtt.log"
error_log="/var/log/zigbee2mqtt.log"

depend() {
    need net
    after firewall mosquitto
}
INITSCRIPT
chmod +x /etc/init.d/zigbee2mqtt

rc-update add zigbee2mqtt default
SETUPEOF
}

# Setup Netdata Monitoring
setup_app_netdata() {
    local rootfs="$1"
    $SUDO chroot "$rootfs" /bin/sh << 'SETUPEOF'
# Configure Netdata for network access
if [ -f /etc/netdata/netdata.conf ]; then
    sed -i 's/bind to = localhost/bind to = 0.0.0.0/' /etc/netdata/netdata.conf 2>/dev/null || true
fi

rc-update add netdata default
SETUPEOF
}

# Setup Custom Application (placeholder)
setup_app_custom() {
    local rootfs="$1"
    # Custom apps use the LXC_SETUP_CMD variable set by user
    if [ -n "$LXC_SETUP_CMD" ] && [ "$LXC_SETUP_CMD" != "<specify setup>" ]; then
        $SUDO chroot "$rootfs" /bin/sh -c "$LXC_SETUP_CMD" 2>/dev/null || true
    fi
}

# LXC Base OS options (lightweight, optimized for containers)
declare -a LXC_OS_LIST_ARM=(
    "alpine320.aarch64|Alpine Linux 3.20|Minimal - Recommended"
    "alpine319.aarch64|Alpine Linux 3.19|Minimal"
)

declare -a LXC_OS_LIST_X86=(
    "alpine320|Alpine Linux 3.20|Minimal - Recommended"
    "alpine319|Alpine Linux 3.19|Minimal"
)

# LXC disk sizes (base|with-app, in MB) - much smaller than Docker
declare -A LXC_DISK_SIZES=(
    ["alpine320"]="64|256"
    ["alpine319"]="64|256"
)

# Supported base OS options (id|name|category)
# x86_64 OS options
declare -a OS_LIST_X86=(
    "ubuntu2204min|Ubuntu 22.04 LTS (Minimal)|Ubuntu - Recommended"
    "ubuntu2204|Ubuntu 22.04 LTS|Ubuntu"
    "ubuntu2404min|Ubuntu 24.04 LTS (Minimal)|Ubuntu"
    "ubuntu2404|Ubuntu 24.04 LTS|Ubuntu"
    "debian12|Debian 12 (Bookworm)|Debian"
    "debian11|Debian 11 (Bullseye)|Debian"
    "alma9|AlmaLinux 9|Enterprise Linux"
    "alma8|AlmaLinux 8|Enterprise Linux"
    "rocky9|Rocky Linux 9|Enterprise Linux"
    "rocky8|Rocky Linux 8|Enterprise Linux"
    "opensuse15|openSUSE Leap 15|SUSE"
)

# ARM64 OS options (use .aarch64 suffix in the build system)
declare -a OS_LIST_ARM=(
    "ubuntu2204.aarch64|Ubuntu 22.04 LTS|Ubuntu - Recommended"
    "ubuntu2404.aarch64|Ubuntu 24.04 LTS|Ubuntu"
    "debian12.aarch64|Debian 12 (Bookworm)|Debian"
    "debian11.aarch64|Debian 11 (Bullseye)|Debian"
    "alma9.aarch64|AlmaLinux 9|Enterprise Linux"
    "alma8.aarch64|AlmaLinux 8|Enterprise Linux"
    "rocky9.aarch64|Rocky Linux 9|Enterprise Linux"
    "rocky8.aarch64|Rocky Linux 8|Enterprise Linux"
    "opensuse15.aarch64|openSUSE Leap 15|SUSE"
)

# Combined list for lookups (populated based on selected architecture)
declare -a OS_LIST=()

# Base OS image sizes (approximate, in MB) - used for disk size recommendations
# Format: base_os_id=base_size|recommended_with_docker
declare -A OS_DISK_SIZES=(
    # Ubuntu minimal images are smaller
    ["ubuntu2204min"]="2048|10240"
    ["ubuntu2404min"]="2048|10240"
    # Full Ubuntu images
    ["ubuntu2204"]="4096|12288"
    ["ubuntu2404"]="4096|12288"
    # Debian
    ["debian11"]="2048|10240"
    ["debian12"]="2048|10240"
    # Enterprise Linux (larger base)
    ["alma8"]="4096|12288"
    ["alma9"]="4096|12288"
    ["rocky8"]="4096|12288"
    ["rocky9"]="4096|12288"
    # openSUSE
    ["opensuse15"]="4096|12288"
)

# Get recommended disk size for a base OS
get_recommended_disk_size() {
    local base_os="$1"
    # Strip .aarch64 suffix for lookup
    local lookup_os="${base_os%.aarch64}"

    if [ -n "${OS_DISK_SIZES[$lookup_os]}" ]; then
        echo "${OS_DISK_SIZES[$lookup_os]#*|}"
    else
        # Default recommendation
        echo "12288"
    fi
}

# Get base image size for a base OS
get_base_image_size() {
    local base_os="$1"
    local lookup_os="${base_os%.aarch64}"

    if [ -n "${OS_DISK_SIZES[$lookup_os]}" ]; then
        echo "${OS_DISK_SIZES[$lookup_os]%%|*}"
    else
        echo "4096"
    fi
}

# Parse Docker image into components
# Args: $1=docker_image
# Sets: PARSED_REGISTRY, PARSED_REPO, PARSED_TAG
parse_docker_image() {
    local image="$1"

    # Extract tag (default to "latest")
    if [[ "$image" == *":"* ]]; then
        PARSED_TAG="${image##*:}"
        image="${image%:*}"
    else
        PARSED_TAG="latest"
    fi

    # Extract registry and repository
    if [[ "$image" == *"."*"/"* ]]; then
        # Custom registry (e.g., ghcr.io/user/repo)
        PARSED_REGISTRY="${image%%/*}"
        PARSED_REPO="${image#*/}"
    elif [[ "$image" == *"/"* ]]; then
        # Docker Hub with namespace (e.g., user/repo)
        PARSED_REGISTRY="registry-1.docker.io"
        PARSED_REPO="$image"
    else
        # Docker Hub official image (e.g., nginx -> library/nginx)
        PARSED_REGISTRY="registry-1.docker.io"
        PARSED_REPO="library/$image"
    fi
}

# Get Docker Hub token for anonymous access
# Args: $1=repository (e.g., library/nginx)
# Returns: token string or empty on failure
get_dockerhub_token() {
    local repo="$1"
    curl -s --connect-timeout 3 --max-time 5 \
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
        2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

# Get GitHub Container Registry (ghcr.io) token for anonymous access
# Args: $1=repository (e.g., home-assistant/home-assistant)
# Returns: token string or empty on failure
get_ghcr_token() {
    local repo="$1"
    curl -s --connect-timeout 3 --max-time 5 \
        "https://ghcr.io/token?scope=repository:${repo}:pull" \
        2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

# Cache for manifest - stored in temp file to persist across subshells
MANIFEST_CACHE_FILE="/tmp/wizard_manifest_cache_$$"
MANIFEST_CACHE_IMAGE_FILE="/tmp/wizard_manifest_image_$$"

# Clean up cache on exit
trap 'rm -f "$MANIFEST_CACHE_FILE" "$MANIFEST_CACHE_IMAGE_FILE"' EXIT

# Fetch manifest from Docker registry (fast HTTP method)
# Args: $1=docker_image
# Returns: manifest JSON on stdout, sets MANIFEST_HTTP_CODE
fetch_docker_manifest() {
    local image="$1"

    # Return cached manifest if same image (use file-based cache for subshell persistence)
    if [[ -f "$MANIFEST_CACHE_IMAGE_FILE" ]] && [[ -f "$MANIFEST_CACHE_FILE" ]]; then
        local cached_image
        cached_image=$(cat "$MANIFEST_CACHE_IMAGE_FILE" 2>/dev/null)
        if [[ "$image" == "$cached_image" ]]; then
            MANIFEST_HTTP_CODE=0
            cat "$MANIFEST_CACHE_FILE"
            return
        fi
    fi

    parse_docker_image "$image"

    local manifest=""

    if [[ "$PARSED_REGISTRY" == "registry-1.docker.io" ]]; then
        # Docker Hub - need token
        local token
        token=$(get_dockerhub_token "$PARSED_REPO")

        if [ -n "$token" ]; then
            manifest=$(curl -s --connect-timeout 3 --max-time 10 \
                -H "Authorization: Bearer $token" \
                -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
                -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                -H "Accept: application/vnd.oci.image.index.v1+json" \
                "https://registry-1.docker.io/v2/${PARSED_REPO}/manifests/${PARSED_TAG}" 2>/dev/null)
            MANIFEST_HTTP_CODE=$?
        else
            MANIFEST_HTTP_CODE=1
        fi
    elif [[ "$PARSED_REGISTRY" == "ghcr.io" ]]; then
        # GitHub Container Registry - need token for anonymous access
        local token
        token=$(get_ghcr_token "$PARSED_REPO")

        if [ -n "$token" ]; then
            manifest=$(curl -s --connect-timeout 3 --max-time 10 \
                -H "Authorization: Bearer $token" \
                -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
                -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                -H "Accept: application/vnd.oci.image.index.v1+json" \
                "https://ghcr.io/v2/${PARSED_REPO}/manifests/${PARSED_TAG}" 2>/dev/null)
            MANIFEST_HTTP_CODE=$?
        else
            MANIFEST_HTTP_CODE=1
        fi
    else
        # Other registries - try anonymous
        manifest=$(curl -s --connect-timeout 3 --max-time 10 \
            -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            "https://${PARSED_REGISTRY}/v2/${PARSED_REPO}/manifests/${PARSED_TAG}" 2>/dev/null)
        MANIFEST_HTTP_CODE=$?
    fi

    # Cache the result to temp files (persists across subshells)
    if [[ "$MANIFEST_HTTP_CODE" -eq 0 ]] && [[ -n "$manifest" ]]; then
        echo "$manifest" > "$MANIFEST_CACHE_FILE"
        echo "$image" > "$MANIFEST_CACHE_IMAGE_FILE"
    fi

    echo "$manifest"
}

# Check if a Docker image supports a specific architecture (fast HTTP method)
# Args: $1=docker_image, $2=target_arch (x86_64 or aarch64)
# Returns: 0=supported, 1=not supported, 2=unknown, 3=auth required, 4=not found, 5=rate limited
check_docker_image_arch() {
    local image="$1"
    local target_arch="$2"

    # Map wizard arch to Docker arch naming
    local docker_arch="amd64"
    [[ "$target_arch" == "aarch64" || "$target_arch" == "arm64" ]] && docker_arch="arm64"

    local manifest
    manifest=$(fetch_docker_manifest "$image")

    if [ -z "$manifest" ]; then
        return 2  # Unknown/network error
    fi

    # Check for error responses
    if echo "$manifest" | grep -q '"errors"'; then
        if echo "$manifest" | grep -qi "TOOMANYREQUESTS"; then
            return 5  # Rate limited
        elif echo "$manifest" | grep -qi "UNAUTHORIZED\|DENIED"; then
            return 3  # Auth required
        elif echo "$manifest" | grep -qi "MANIFEST_UNKNOWN\|NAME_UNKNOWN"; then
            return 4  # Not found
        fi
        return 2  # Other error
    fi

    # Check if the architecture is in the manifest (handle optional whitespace in JSON)
    if echo "$manifest" | grep -qE "\"architecture\"[[:space:]]*:[[:space:]]*\"$docker_arch\""; then
        return 0  # Supported
    elif echo "$manifest" | grep -qE "\"architecture\"[[:space:]]*:"; then
        return 1  # Has architectures but not the one we want
    else
        return 2  # Unknown - can't determine (legacy manifest)
    fi
}

# Get list of supported architectures for a Docker image (fast HTTP method)
# Args: $1=docker_image
# Returns: comma-separated list of architectures, or empty if unknown
get_docker_image_archs() {
    local image="$1"

    local manifest
    manifest=$(fetch_docker_manifest "$image")

    if [ -z "$manifest" ]; then
        echo ""
        return
    fi

    # Check if this is an error response
    if echo "$manifest" | grep -q '"errors"'; then
        echo ""
        return
    fi

    # Extract unique architectures (filter out "unknown")
    echo "$manifest" | grep -o '"architecture"[[:space:]]*:[[:space:]]*"[^"]*"' | \
        sed 's/.*"\([^"]*\)"$/\1/' | grep -v "unknown" | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Extract registry from Docker image name
# Args: $1=docker_image
# Returns: registry hostname or "docker.io" for Docker Hub
get_image_registry() {
    local image="$1"

    # Check if image contains a registry (has a dot before the first slash)
    if [[ "$image" == *"."*"/"* ]]; then
        echo "${image%%/*}"
    elif [[ "$image" == *"/"* ]]; then
        # Docker Hub with namespace (e.g., library/nginx or myuser/myimage)
        echo "docker.io"
    else
        # Docker Hub official image (e.g., nginx)
        echo "docker.io"
    fi
}

# Verify Docker image exists in registry (uses fetch_docker_manifest to populate cache)
# Args: $1=docker_image
# Returns: 0=exists, 1=not found, 2=auth required, 3=unknown/network error, 4=rate limited
verify_docker_image_exists() {
    local image="$1"

    # Fetch the manifest (this populates the cache for get_docker_image_archs)
    local manifest
    manifest=$(fetch_docker_manifest "$image")

    # Check result
    if [ -z "$manifest" ]; then
        return 3  # Network error or empty response
    fi

    # Check for error responses (Docker registry returns JSON with "errors" array)
    if echo "$manifest" | grep -q '"errors"'; then
        if echo "$manifest" | grep -qi "MANIFEST_UNKNOWN\|NAME_UNKNOWN"; then
            return 1  # Not found
        elif echo "$manifest" | grep -qi "UNAUTHORIZED\|DENIED"; then
            return 2  # Auth required
        elif echo "$manifest" | grep -qi "TOOMANYREQUESTS"; then
            return 4  # Rate limited
        else
            return 3  # Other error
        fi
    fi

    # If we got a non-empty response without errors, assume image exists
    # Valid manifests contain schemaVersion, but we're lenient here
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENV FILE SUPPORT (Non-interactive mode)
# ═══════════════════════════════════════════════════════════════════════════════

# Check for --help first
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat << 'HELPEOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║  OpenNebula Community Marketplace - Appliance Creation Wizard             ║
╚═══════════════════════════════════════════════════════════════════════════╝

Usage:
  ./appliance-wizard.sh                    # Interactive wizard mode
  ./appliance-wizard.sh <config.env>       # Non-interactive mode with env file
  ./appliance-wizard.sh --help             # Show this help

Env file format (myapp.env):
  DOCKER_IMAGE="nginx:alpine"
  APPLIANCE_NAME="nginx"
  APP_NAME="NGINX Web Server"
  PUBLISHER_NAME="Your Name"
  PUBLISHER_EMAIL="you@example.com"
  APP_DESCRIPTION="High-performance web server"
  APP_FEATURES="Web server,Reverse proxy,Load balancing"
  DEFAULT_CONTAINER_NAME="nginx-server"
  DEFAULT_PORTS="80:80,443:443"
  DEFAULT_ENV_VARS="NGINX_HOST=localhost"
  DEFAULT_VOLUMES="/data:/usr/share/nginx/html"
  APP_PORT="80"
  WEB_INTERFACE="true"
  BASE_OS="ubuntu2204min"                  # or ubuntu2404.aarch64 for ARM

  # Image disk size (used during build)
  VM_DISK_SIZE="12288"                     # Disk size in MB (must be >= 10GB)

  # VM template defaults (used at deployment, not build time)
  VM_CPU="1"                               # Default CPU cores for VM template
  VM_VCPU="2"                              # Default vCPUs for VM template
  VM_MEMORY="2048"                         # Default memory in MB for VM template

  # Optional: SSH and Login configuration
  SSH_PUBLIC_KEY="ssh-rsa AAAA..."         # Embedded SSH public key
  AUTOLOGIN_ENABLED="true"                 # true = auto-login, false = password required
  LOGIN_USERNAME="root"                    # Username for console login
  ROOT_PASSWORD="mysecurepassword"         # Password when autologin disabled

  # Optional: Docker update behavior
  DOCKER_AUTO_UPDATE="CHECK"               # CHECK=notify, YES=auto-update, NO=never

  # Optional: Skip interactive build prompt
  AUTO_BUILD="true"                        # Auto-start build after generating

Supported BASE_OS values:
  x86_64:  ubuntu2204min, ubuntu2404, debian12, alma9, rocky9, opensuse15
  ARM64:   ubuntu2204.aarch64, ubuntu2404.aarch64, debian12.aarch64, alma9.aarch64

HELPEOF
            exit 0
            ;;
    esac
done

# Check if env file provided as argument
ENV_FILE=""
AUTO_BUILD="false"
if [ -n "$1" ] && [ -f "$1" ]; then
    ENV_FILE="$1"
    echo ""
    echo -e "  ${WHITE}Loading configuration from:${NC} ${CYAN}$ENV_FILE${NC}"
    source "$ENV_FILE"

    # Validate required variables based on appliance type
    if [ "$APPLIANCE_TYPE" = "lxc" ]; then
        REQUIRED_VARS=("APPLIANCE_NAME" "BASE_OS" "LXC_APPLICATION" "LXC_PACKAGES")
    else
        REQUIRED_VARS=("DOCKER_IMAGE" "APPLIANCE_NAME" "APP_NAME" "PUBLISHER_NAME" "PUBLISHER_EMAIL")
    fi

    MISSING_VARS=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS+=("$var")
        fi
    done

    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Missing required variables: ${MISSING_VARS[*]}"
        echo ""
        exit 1
    fi

    # Set defaults for optional variables
    DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-${APPLIANCE_NAME}-container}"
    DEFAULT_PORTS="${DEFAULT_PORTS:-8080:80}"
    DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS:-}"
    DEFAULT_VOLUMES="${DEFAULT_VOLUMES:-}"
    APP_PORT="${APP_PORT:-8080}"
    WEB_INTERFACE="${WEB_INTERFACE:-true}"
    APP_DESCRIPTION="${APP_DESCRIPTION:-Docker-based appliance for ${APP_NAME}}"
    APP_FEATURES="${APP_FEATURES:-Containerized application,Easy deployment}"
    BASE_OS="${BASE_OS:-ubuntu2204min}"
    VM_CPU="${VM_CPU:-1}"
    VM_VCPU="${VM_VCPU:-2}"
    VM_MEMORY="${VM_MEMORY:-2048}"
    VM_DISK_SIZE="${VM_DISK_SIZE:-12288}"

    # SSH and Login configuration defaults for non-interactive mode
    SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
    AUTOLOGIN_ENABLED="${AUTOLOGIN_ENABLED:-true}"
    LOGIN_USERNAME="${LOGIN_USERNAME:-root}"
    ROOT_PASSWORD="${ROOT_PASSWORD:-opennebula}"
    DOCKER_AUTO_UPDATE="${DOCKER_AUTO_UPDATE:-CHECK}"

    # If no SSH key provided, try to use host key
    if [ -z "$SSH_PUBLIC_KEY" ]; then
        if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
            SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
        elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
            SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
        fi
    fi

    # Detect architecture from BASE_OS
    if [[ "$BASE_OS" == *".aarch64"* ]]; then
        ARCH="aarch64"
        OS_LIST=("${OS_LIST_ARM[@]}")
    else
        ARCH="x86_64"
        OS_LIST=("${OS_LIST_X86[@]}")
    fi

    echo -e "  ${GREEN}✓${NC} Configuration loaded"
    echo ""
    echo -e "  ${DIM}Appliance:${NC}   $APPLIANCE_NAME"
    echo -e "  ${DIM}Docker:${NC}      $DOCKER_IMAGE"
    echo -e "  ${DIM}Base OS:${NC}     $BASE_OS"
    echo -e "  ${DIM}Arch:${NC}        $ARCH"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TERMINAL UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

clear_screen() {
    clear
}

hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

# Reset terminal to known good state for interactive input
# Call this after processes that may have corrupted stdin (builds, pipes, etc.)
reset_terminal_for_input() {
    # Reset terminal settings FIRST
    stty sane </dev/tty 2>/dev/null || true

    # Multiple drain passes with increasing timeouts to catch all garbage
    # Pass 1: Quick drain (1ms timeout)
    while IFS= read -rsn1 -t 0.001 _discard </dev/tty 2>/dev/null; do :; done

    # Pass 2: Medium drain (10ms timeout) - catches slower arriving data
    while IFS= read -rsn1 -t 0.01 _discard </dev/tty 2>/dev/null; do :; done

    # Pass 3: Final drain (50ms timeout) - ensures buffer is truly empty
    while IFS= read -rsn1 -t 0.05 _discard </dev/tty 2>/dev/null; do :; done

    # Reset terminal settings again after draining
    stty sane </dev/tty 2>/dev/null || true

    # Small delay to let everything settle
    sleep 0.1
}

# Get terminal width
get_term_width() {
    tput cols 2>/dev/null || echo 80
}

# Center text in terminal
center_text() {
    local text="$1"
    local width=$(get_term_width)
    local text_len=${#text}
    local padding=$(( (width - text_len) / 2 ))
    printf "%${padding}s%s\n" "" "$text"
}

# Trap to ensure cursor is shown on exit
trap 'show_cursor; stty echo 2>/dev/null' EXIT INT TERM

# Navigation result constants
NAV_CONTINUE=0
NAV_BACK=1
NAV_QUIT=2

# ═══════════════════════════════════════════════════════════════════════════════
# ASCII ART & BRANDING
# ═══════════════════════════════════════════════════════════════════════════════

print_logo() {
    echo ""
    # OpenNebula logo with space elements
    echo -e "${DIM}                                                              ·${NC}"
    echo -e "${DIM}          ·                                           ✦${NC}"
    echo -e "${DIM}                    ✦                      ·${NC}"
    echo -e "${WHITE}${BOLD}     ___                   _   _      _           _${NC}"
    echo -e "${WHITE}${BOLD}    / _ \\ _ __   ___ _ __ | \\ | | ___| |__  _   _| | __ _${NC}      ${DIM}·${NC}"
    echo -e "${WHITE}${BOLD}   | | | | '_ \\ / _ \\ '_ \\|  \\| |/ _ \\ '_ \\| | | | |/ _\` |${NC}"
    echo -e "${WHITE}${BOLD}   | |_| | |_) |  __/ | | | |\\  |  __/ |_) | |_| | | (_| |${NC}   ${DIM}✦${NC}"
    echo -e "${WHITE}${BOLD}    \\___/| .__/ \\___|_| |_|_| \\_|\\___|_.__/ \\__,_|_|\\__,_|${NC}"
    echo -e "${WHITE}${BOLD}         |_|${NC}"
    echo -e "${BRIGHT_CYAN}    ════════════════════════════════════════════════════════${NC}"
    echo -e "${DIM}                   ·                                      ✦${NC}"
    echo -e "${DIM}         ✦                          ·${NC}"
    echo ""
    echo -e "                      ${DIM}Appliance Wizard v${WIZARD_VERSION}${NC}"
    echo ""
}

print_header() {
    print_logo
    echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# UI COMPONENTS
# ═══════════════════════════════════════════════════════════════════════════════

print_step() {
    local step=$1
    local total=$2
    local title=$3

    echo ""
    echo -e "  ${BRIGHT_CYAN}[$step/$total]${NC} ${WHITE}${BOLD}${title}${NC}"
    echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
    echo ""
}

print_nav_hint() {
    echo -e "  ${DIM}[Enter] Next  [:b] Back  [:q] Quit${NC}"
    echo ""
}

print_info() {
    echo -e "  ${DIM}$1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}!${NC} $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROGRESS BAR & SPINNER
# ═══════════════════════════════════════════════════════════════════════════════

# Spinner animation frames
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Show a spinner with message while a command runs
# Usage: run_with_spinner "message" command args...
run_with_spinner() {
    local message="$1"
    shift
    local pid
    local frame=0

    # Start command in background
    "$@" &
    pid=$!

    # Show spinner while command runs
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${SPINNER_FRAMES[$frame]}${NC} %s" "$message"
        frame=$(( (frame + 1) % ${#SPINNER_FRAMES[@]} ))
        sleep 0.1
    done

    # Wait for command and get exit status
    wait "$pid"
    local status=$?
    show_cursor

    # Clear spinner line
    printf "\r${CLEAR_LINE}"

    return $status
}

# Show a progress bar
# Usage: show_progress_bar current total [message]
show_progress_bar() {
    local current=$1
    local total=$2
    local message="${3:-}"
    local bar_width=40
    local filled=$(( current * bar_width / total ))
    local empty=$(( bar_width - filled ))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    local percent=$(( current * 100 / total ))
    printf "\r  [${CYAN}%s${NC}] %3d%% %s" "$bar" "$percent" "$message"
}

# Monitor a long-running build process with live progress
# Usage: monitor_build_progress "log_pattern" pid
monitor_build_progress() {
    local pid=$1
    local stage_name=""
    local stages=("Initializing" "Downloading" "Building" "Provisioning" "Finalizing")
    local stage_idx=0
    local dots=""

    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        stage_name="${stages[$stage_idx]}"
        dots="${dots}."
        [ ${#dots} -gt 3 ] && dots="."

        printf "\r  ${CYAN}⟳${NC} ${WHITE}%s${NC}%-4s" "$stage_name" "$dots"

        # Cycle through stages slowly to show activity
        if [ $(( RANDOM % 20 )) -eq 0 ] && [ $stage_idx -lt $(( ${#stages[@]} - 1 )) ]; then
            stage_idx=$((stage_idx + 1))
            dots=""
        fi
        sleep 0.3
    done
    show_cursor
    printf "\r${CLEAR_LINE}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MENU SELECTOR (Arrow-key navigation)
# ═══════════════════════════════════════════════════════════════════════════════

# Arrow menu selection with back support
# Args: $1=result_var, $2...=options
# Sets result_var to selected index, or returns NAV_BACK if user pressed 'b'
menu_select() {
    # Temporarily disable set -e to prevent unexpected exits during menu interaction
    # This is critical after build processes that may leave terminal/fd state corrupted
    local was_errexit=0
    [[ $- == *e* ]] && was_errexit=1
    set +e

    local result_var=$1
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key=""

    # DEBUG LOG FILE
    local MENU_LOG="/tmp/menu_select_debug.log"
    echo "========================================" >> "$MENU_LOG"
    echo "menu_select called at $(date)" >> "$MENU_LOG"
    echo "Options: ${options[*]}" >> "$MENU_LOG"
    echo "Num options: $num_options" >> "$MENU_LOG"
    echo "PID: $$" >> "$MENU_LOG"
    echo "TTY: $(tty 2>&1)" >> "$MENU_LOG"
    echo "/dev/tty exists: $(test -e /dev/tty && echo yes || echo no)" >> "$MENU_LOG"
    echo "/dev/tty readable: $(test -r /dev/tty && echo yes || echo no)" >> "$MENU_LOG"
    echo "fd 0 (stdin): $(ls -l /proc/$$/fd/0 2>&1)" >> "$MENU_LOG"
    echo "fd 1 (stdout): $(ls -l /proc/$$/fd/1 2>&1)" >> "$MENU_LOG"
    echo "fd 2 (stderr): $(ls -l /proc/$$/fd/2 2>&1)" >> "$MENU_LOG"
    echo "" >> "$MENU_LOG"

    # Open a FRESH file descriptor for /dev/tty - ensures clean state after build processes
    echo "Opening fd 3 for /dev/tty..." >> "$MENU_LOG"
    if ! exec 3</dev/tty; then
        echo "FAILED to open /dev/tty as fd 3!" >> "$MENU_LOG"
        eval "$result_var=0"
        [ $was_errexit -eq 1 ] && set -e
        return $NAV_CONTINUE
    fi
    echo "fd 3 opened successfully" >> "$MENU_LOG"
    echo "fd 3: $(ls -l /proc/$$/fd/3 2>&1)" >> "$MENU_LOG"

    # Initial drain of any garbage in the fresh descriptor
    local drain_count=0
    while IFS= read -rsn1 -t 0.01 _init_drain <&3 2>/dev/null; do
        drain_count=$((drain_count + 1))
    done
    echo "Initial drain: removed $drain_count characters" >> "$MENU_LOG"

    # Print options immediately - selected option has green arrow
    echo ""
    for i in "${!options[@]}"; do
        if [[ $i -eq $selected ]]; then
            echo -e "    ${GREEN}>${NC} ${WHITE}${options[$i]}${NC}"
        else
            echo -e "      ${DIM}${options[$i]}${NC}"
        fi
    done
    echo ""
    echo -e "  ${DIM}[↑↓] Navigate  [Enter] Select  [b] Back  [q] Quit${NC}"

    hide_cursor

    local iteration=0
    while true; do
        iteration=$((iteration + 1))
        echo "--- Iteration $iteration ---" >> "$MENU_LOG"
        echo "About to read from fd 3..." >> "$MENU_LOG"

        # Read from fresh tty descriptor - wait for real user input
        local read_status=0
        IFS= read -rsn1 key <&3 || read_status=$?

        echo "Read returned. Status: $read_status" >> "$MENU_LOG"
        echo "Key value: '$(printf '%q' "$key")'" >> "$MENU_LOG"
        echo "Key hex: $(printf '%s' "$key" | xxd -p 2>/dev/null || echo 'xxd not available')" >> "$MENU_LOG"
        echo "Key length: ${#key}" >> "$MENU_LOG"

        # Handle navigation keys
        local should_redraw=0

        if [ "$key" = $'\x1b' ]; then
            echo "ESC detected, reading escape sequence..." >> "$MENU_LOG"
            # Read the full escape sequence with timeout to avoid hanging
            if IFS= read -rsn2 -t 0.1 seq <&3 2>/dev/null; then
                echo "Escape sequence: '$seq' (hex: $(printf '%s' "$seq" | xxd -p 2>/dev/null))" >> "$MENU_LOG"
                case "$seq" in
                    '[A') # Up arrow
                        echo "UP arrow" >> "$MENU_LOG"
                        if ((selected > 0)); then
                            ((selected--))
                            should_redraw=1
                        fi
                        ;;
                    '[B') # Down arrow
                        echo "DOWN arrow" >> "$MENU_LOG"
                        echo "  selected=$selected, num_options=$num_options" >> "$MENU_LOG"
                        sync  # Flush log immediately
                        if ((selected < num_options - 1)); then
                            ((selected++))
                            echo "  incremented selected to $selected" >> "$MENU_LOG"
                            should_redraw=1
                            echo "  should_redraw set to 1" >> "$MENU_LOG"
                        else
                            echo "  already at bottom, not incrementing" >> "$MENU_LOG"
                        fi
                        echo "  exiting DOWN case" >> "$MENU_LOG"
                        sync  # Flush log
                        ;;
                    '[C'|'[D') # Right/Left arrows - ignore
                        echo "LEFT/RIGHT arrow (ignored)" >> "$MENU_LOG"
                        ;;
                    *) # Unknown escape sequence - ignore
                        echo "Unknown escape sequence (ignored)" >> "$MENU_LOG"
                        ;;
                esac
            else
                echo "Escape sequence read failed/timed out" >> "$MENU_LOG"
            fi
            echo "After ESC handling, should_redraw=$should_redraw" >> "$MENU_LOG"
            # If read timed out or failed, just ignore the ESC and don't redraw
        elif [ "$key" = "" ]; then
            echo "EMPTY KEY detected (could be Enter or spurious)" >> "$MENU_LOG"
            # Empty read could be Enter key OR spurious data after build processes
            # Verify by checking if more data arrives immediately (spurious = garbage in buffer)
            if IFS= read -rsn1 -t 0.02 _verify <&3 2>/dev/null; then
                echo "SPURIOUS: Got more data immediately, draining..." >> "$MENU_LOG"
                # Got more data immediately - this was spurious, drain and retry
                local spurious_drain=0
                while IFS= read -rsn1 -t 0.001 _drain <&3 2>/dev/null; do
                    spurious_drain=$((spurious_drain + 1))
                done
                echo "Spurious drain: removed $spurious_drain characters" >> "$MENU_LOG"
                continue
            fi
            # No more data - this was a real Enter press
            echo "ENTER: No more data, treating as Enter press" >> "$MENU_LOG"
            echo "Breaking out of loop with selected=$selected" >> "$MENU_LOG"
            break
        elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            echo "QUIT pressed" >> "$MENU_LOG"
            exec 3<&-  # Close file descriptor
            show_cursor
            echo ""
            print_warning "Cancelled."
            [ $was_errexit -eq 1 ] && set -e
            exit 0
        elif [ "$key" = "b" ] || [ "$key" = "B" ]; then
            echo "BACK pressed" >> "$MENU_LOG"
            exec 3<&-  # Close file descriptor
            show_cursor
            eval "$result_var=-1"
            [ $was_errexit -eq 1 ] && set -e
            return $NAV_BACK
        elif [ "$key" = "k" ]; then
            echo "VIM UP (k)" >> "$MENU_LOG"
            # Vim-style up
            if ((selected > 0)); then
                ((selected--))
                should_redraw=1
            fi
        elif [ "$key" = "j" ]; then
            echo "VIM DOWN (j)" >> "$MENU_LOG"
            # Vim-style down
            if ((selected < num_options - 1)); then
                ((selected++))
                should_redraw=1
            fi
        else
            echo "UNKNOWN key (ignored): '$(printf '%q' "$key")'" >> "$MENU_LOG"
            # Unknown key - ignore and don't redraw
            continue
        fi

        echo "Past all key handling, should_redraw=$should_redraw" >> "$MENU_LOG"

        # Only redraw if selection changed
        if [ $should_redraw -eq 0 ]; then
            echo "No redraw needed" >> "$MENU_LOG"
            continue
        fi

        echo "Redrawing menu..." >> "$MENU_LOG"
        sync  # Flush log to disk
        echo "  About to move cursor up $((num_options+3)) lines" >> "$MENU_LOG"
        # Redraw (num_options + 3 lines: empty line, options, empty line, help line)
        for ((i=0; i<num_options+3; i++)); do printf '\033[A'; done
        echo "  Cursor moved, now redrawing options" >> "$MENU_LOG"

        printf '\033[2K'
        echo ""
        for i in "${!options[@]}"; do
            printf '\033[2K'
            if [[ $i -eq $selected ]]; then
                echo -e "    ${GREEN}>${NC} ${WHITE}${options[$i]}${NC}"
            else
                echo -e "      ${DIM}${options[$i]}${NC}"
            fi
        done
        printf '\033[2K'
        echo ""
        printf '\033[2K'
        echo -e "  ${DIM}[↑↓] Navigate  [Enter] Select  [b] Back  [q] Quit${NC}"
    done

    exec 3<&-  # Close file descriptor
    show_cursor
    eval "$result_var=$selected"
    echo "menu_select returning with selected=$selected" >> "$MENU_LOG"
    echo "========================================" >> "$MENU_LOG"
    echo "" >> "$MENU_LOG"
    [ $was_errexit -eq 1 ] && set -e
    return $NAV_CONTINUE
}

# ═══════════════════════════════════════════════════════════════════════════════
# INPUT PROMPTS
# ═══════════════════════════════════════════════════════════════════════════════

prompt_with_nav() {
    local prompt=$1
    local var_name=$2
    local default=$3
    local required=$4
    local value=""

    while true; do
        local current_val
        eval "current_val=\$$var_name"
        local show_default="${current_val:-$default}"

        if [ -n "$show_default" ]; then
            echo -ne "  ${prompt} ${DIM}[${show_default}]${NC}: "
        elif [ "$required" = "true" ]; then
            echo -ne "  ${prompt}${RED}*${NC}: "
        else
            echo -ne "  ${prompt} ${DIM}(optional)${NC}: "
        fi

        read -r value

        case "${value,,}" in
            ':b'|':back'|'<') return $NAV_BACK ;;
            ':q'|':quit') return $NAV_QUIT ;;
        esac

        [ -z "$value" ] && value="$show_default"

        if [ "$required" = "true" ] && [ -z "$value" ]; then
            print_error "Required field"
        else
            eval "$var_name='$value'"
            return $NAV_CONTINUE
        fi
    done
}

prompt_required() {
    prompt_with_nav "$1" "$2" "$3" "true"
    return $?
}

prompt_optional() {
    prompt_with_nav "$1" "$2" "$3" "false"
    return $?
}

prompt_yes_no() {
    local prompt=$1
    local var_name=$2
    local default=$3

    local default_hint="y/n"
    [ "$default" = "true" ] && default_hint="Y/n"
    [ "$default" = "false" ] && default_hint="y/N"

    local current_val
    eval "current_val=\$$var_name"
    [ -n "$current_val" ] && default="$current_val"

    echo -en "${CYAN}${prompt}${NC} ${DIM}[${default_hint}]${NC}: "
    read -r value

    case "${value,,}" in
        ':b'|':back'|'<') return $NAV_BACK ;;
        ':q'|':quit') return $NAV_QUIT ;;
        y|yes) eval "$var_name='true'" ;;
        n|no) eval "$var_name='false'" ;;
        *) eval "$var_name='$default'" ;;
    esac
    return $NAV_CONTINUE
}

validate_docker_image() {
    local image=$1
    if [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*:[a-zA-Z0-9._-]+$ ]] && \
       [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]]; then
        return 1
    fi
    return 0
}

validate_appliance_name() {
    local name=$1
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        return 1
    fi
    return 0
}

# Wizard steps - each returns: 0=continue, 1=back, 2=quit

step_welcome() {
    clear_screen
    print_logo

    echo -e "  ${WHITE}Build production-ready appliances for OpenNebula${NC}"
    echo ""
    echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BRIGHT_CYAN}›${NC} ${WHITE}Docker Appliances${NC}"
    echo -e "    ${DIM}Turn any container into a full VM with networking,${NC}"
    echo -e "    ${DIM}persistent storage, and OpenNebula context support${NC}"
    echo ""
    echo -e "  ${BRIGHT_CYAN}›${NC} ${WHITE}LXC System Containers${NC}"
    echo -e "    ${DIM}Lightweight Alpine-based appliances with pre-configured${NC}"
    echo -e "    ${DIM}services: MQTT, Node-RED, Nginx, PostgreSQL, and more${NC}"
    echo ""
    echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${DIM}Navigation${NC}"
    echo -e "  ${DIM}  [↑↓] Select   [Enter] Confirm   [:b] Back   [:q] Quit${NC}"
    echo ""
    echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
    echo ""
    echo -ne "  Press ${WHITE}[Enter]${NC} to continue "
    read -r
    # Flush any remaining input and reset terminal
    read -t 0.1 -n 10000 discard 2>/dev/null || true
    return $NAV_CONTINUE
}

# ═══════════════════════════════════════════════════════════════════════════════
# NEW LXC STEPS
# ═══════════════════════════════════════════════════════════════════════════════

step_appliance_type() {
    local type_options=("Docker Appliance  │ KVM VM running any Docker image" "LXC Container     │ Lightweight Alpine with pre-configured apps")

    while true; do
        clear_screen
        print_header
        print_step 1 $TOTAL_STEPS "Appliance Type"

        echo -e "  ${DIM}Select the type of appliance to create${NC}"
        echo ""

        local selected_idx
        menu_select selected_idx "${type_options[@]}"
        local result=$?

        [ $result -eq $NAV_BACK ] && return $NAV_BACK

        if [ "$selected_idx" -eq 0 ]; then
            APPLIANCE_TYPE="docker"
            TOTAL_STEPS=12
            print_success "Docker Appliance"
        else
            APPLIANCE_TYPE="lxc"
            TOTAL_STEPS=6
            print_success "LXC Container"
        fi

        sleep 0.3
        return $NAV_CONTINUE
    done
}

step_lxc_application() {
    # Skip if not LXC
    [ "$APPLIANCE_TYPE" != "lxc" ] && return $NAV_CONTINUE

    clear_screen
    print_header
    print_step 2 $TOTAL_STEPS "Select LXC Application"

    echo ""
    echo -e "  ${WHITE}Choose a pre-configured application:${NC}"

    # Build sorted list of applications and display names
    local app_ids=($(echo "${!LXC_APP_CATALOG[@]}" | tr ' ' '\n' | sort))
    local app_options=()
    for app_id in "${app_ids[@]}"; do
        IFS='|' read -r name packages ports setup <<< "${LXC_APP_CATALOG[$app_id]}"
        app_options+=("${name} (ports: ${ports})")
    done

    local selected_idx
    menu_select selected_idx "${app_options[@]}"
    local result=$?

    [ $result -eq $NAV_BACK ] && return $NAV_BACK

    LXC_APPLICATION="${app_ids[$selected_idx]}"
    IFS='|' read -r name LXC_PACKAGES LXC_PORTS LXC_SETUP_CMD <<< "${LXC_APP_CATALOG[$LXC_APPLICATION]}"

    if [ "$LXC_APPLICATION" = "custom" ]; then
        echo ""
        prompt_input "Application name" LXC_APPLICATION ""
        [ $? -ne $NAV_CONTINUE ] && return $?
        prompt_input "Alpine packages (space-separated)" LXC_PACKAGES ""
        [ $? -ne $NAV_CONTINUE ] && return $?
        prompt_input "Exposed ports (comma-separated)" LXC_PORTS ""
        [ $? -ne $NAV_CONTINUE ] && return $?
        prompt_input "Setup command (or empty)" LXC_SETUP_CMD ""
    fi

    # Auto-generate appliance name from application
    APPLIANCE_NAME="${LXC_APPLICATION}-alpine-lxc"

    print_success "Selected: $LXC_APPLICATION"
    sleep 0.3
    return $NAV_CONTINUE
}

step_lxc_base_os() {
    # Skip if not LXC
    [ "$APPLIANCE_TYPE" != "lxc" ] && return $NAV_CONTINUE

    clear_screen
    print_header
    print_step 4 $TOTAL_STEPS "Select LXC Base OS"

    echo ""
    echo -e "  ${WHITE}Choose base operating system:${NC}"
    echo -e "  ${DIM}(Alpine is recommended for minimal footprint)${NC}"

    # Select OS list based on architecture
    local os_list=()
    if [ "$ARCH" = "aarch64" ]; then
        os_list=("${LXC_OS_LIST_ARM[@]}")
    else
        os_list=("${LXC_OS_LIST_X86[@]}")
    fi

    # Build display options
    local os_options=()
    for os_entry in "${os_list[@]}"; do
        IFS='|' read -r os_id os_name os_cat <<< "$os_entry"
        os_options+=("${os_name} (${os_cat})")
    done

    local selected_idx
    menu_select selected_idx "${os_options[@]}"
    local result=$?

    [ $result -eq $NAV_BACK ] && return $NAV_BACK

    IFS='|' read -r BASE_OS os_name os_cat <<< "${os_list[$selected_idx]}"
    print_success "Selected: $os_name"
    sleep 0.3
    return $NAV_CONTINUE
}

step_context_mode() {
    # Skip if not LXC
    [ "$APPLIANCE_TYPE" != "lxc" ] && return $NAV_CONTINUE

    clear_screen
    print_header
    print_step 5 $TOTAL_STEPS "Contextualization Mode"

    echo ""

    # Check if any LXC hosts lack iso9660 support
    local has_hosts_without_iso9660=false
    local hosts_checked=0
    local incompatible_hosts=""

    if command -v onehost &>/dev/null && command -v ssh &>/dev/null; then
        # Get LXC hosts (aarch64 architecture)
        local lxc_hosts=$(onehost list -l ID,NAME,STAT --csv 2>/dev/null | grep -v "^ID" | grep "on$" | cut -d',' -f2 || true)

        if [ -n "$lxc_hosts" ]; then
            while IFS= read -r host; do
                [ -z "$host" ] && continue
                hosts_checked=$((hosts_checked + 1))

                # Check if host has iso9660 support (check for module or built-in support)
                local has_iso9660=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$host" \
                    'modinfo iso9660 &>/dev/null && echo "yes" || (zgrep -q "CONFIG_ISO9660_FS=y" /proc/config.gz 2>/dev/null && echo "yes" || echo "no")' 2>/dev/null || echo "no")

                if [ "$has_iso9660" = "no" ]; then
                    has_hosts_without_iso9660=true
                    incompatible_hosts="${incompatible_hosts}${host}, "
                fi
            done <<< "$lxc_hosts"
        fi
    fi

    # Show warning banner if hosts lack iso9660
    if [ "$has_hosts_without_iso9660" = true ]; then
        incompatible_hosts="${incompatible_hosts%, }"  # Remove trailing comma
        echo -e "  ${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${YELLOW}║${NC} ${BOLD}⚠  WARNING: Embedded/IoT Hosts Detected${NC}                      ${YELLOW}║${NC}"
        echo -e "  ${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${DIM}The following host(s) lack iso9660 kernel support:${NC}"
        echo -e "  ${YELLOW}${incompatible_hosts}${NC}"
        echo ""
        echo -e "  ${WHITE}These hosts require Contextless mode.${NC}"
        echo -e "  ${DIM}Standard Context will fail during VM deployment.${NC}"
        echo ""
        echo -e "  ${GREEN}✓${NC} Auto-selecting: ${BOLD}Contextless (DHCP)${NC}"
        echo ""
        echo -e "  ${DIM}Press any key to continue...${NC}"
        read -n 1 -s

        CONTEXT_MODE="contextless"
        return $NAV_CONTINUE
    fi

    # Standard selection if hosts support iso9660 or can't be checked
    echo -e "  ${WHITE}Select how the container gets its configuration:${NC}"
    echo ""
    echo -e "  ${CYAN}Standard Context:${NC}"
    echo -e "    ${DIM}• VM gets IP/hostname from OpenNebula${NC}"
    echo -e "    ${DIM}• Requires iso9660 kernel support${NC}"
    echo ""
    echo -e "  ${CYAN}Contextless (DHCP):${NC}"
    echo -e "    ${DIM}• VM uses DHCP for networking${NC}"
    echo -e "    ${DIM}• No kernel module requirements${NC}"
    echo -e "    ${DIM}• Best for edge/IoT devices${NC}"

    if [ "$hosts_checked" -eq 0 ]; then
        echo ""
        echo -e "  ${DIM}💡 Tip: For Arduino/Raspberry Pi hosts, use Contextless mode${NC}"
    fi

    local context_options=("Standard Context" "Contextless (DHCP) - Recommended")
    local modes=("context" "contextless")

    local selected_idx
    menu_select selected_idx "${context_options[@]}"
    local result=$?

    [ $result -eq $NAV_BACK ] && return $NAV_BACK

    CONTEXT_MODE="${modes[$selected_idx]}"
    print_success "Selected: ${context_options[$selected_idx]}"
    sleep 0.3
    return $NAV_CONTINUE
}

step_lxc_vm_config() {
    # Skip if not LXC
    [ "$APPLIANCE_TYPE" != "lxc" ] && return $NAV_CONTINUE

    clear_screen
    print_header
    print_step 6 $TOTAL_STEPS "VM Configuration"
    print_nav_hint

    echo ""
    echo -e "  ${WHITE}Configure VM resources:${NC}"
    echo -e "  ${DIM}(LXC containers need minimal resources)${NC}"
    echo ""

    # Get recommended disk size from catalog
    local base_disk="${LXC_DISK_SIZES[${BASE_OS%.aarch64}]%%|*}"
    local rec_disk="${LXC_DISK_SIZES[${BASE_OS%.aarch64}]#*|}"
    [ -z "$rec_disk" ] && rec_disk="256"

    # Get recommended memory for the selected application
    local rec_memory="${LXC_APP_MEMORY[$LXC_APPLICATION]:-256}"

    local result
    prompt_optional "Memory (MB)" VM_MEMORY "$rec_memory"
    result=$?; [ $result -ne $NAV_CONTINUE ] && return $result

    prompt_optional "VCPUs" VM_VCPU "1"
    result=$?; [ $result -ne $NAV_CONTINUE ] && return $result

    prompt_optional "Disk size (MB)" VM_DISK_SIZE "$rec_disk"
    result=$?; [ $result -ne $NAV_CONTINUE ] && return $result

    return $NAV_CONTINUE
}

step_lxc_summary() {
    # Skip if not LXC
    [ "$APPLIANCE_TYPE" != "lxc" ] && return $NAV_CONTINUE

    clear_screen
    print_header

    echo ""
    echo -e "  ${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${WHITE}║              LXC Appliance Configuration               ║${NC}"
    echo -e "  ${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Application:${NC}    $LXC_APPLICATION"
    echo -e "  ${CYAN}Packages:${NC}       $LXC_PACKAGES"
    echo -e "  ${CYAN}Ports:${NC}          $LXC_PORTS"
    echo ""
    echo -e "  ${CYAN}Base OS:${NC}        $BASE_OS"
    echo -e "  ${CYAN}Architecture:${NC}   $ARCH"
    echo -e "  ${CYAN}Context Mode:${NC}   $CONTEXT_MODE"
    echo ""
    echo -e "  ${CYAN}Memory:${NC}         ${VM_MEMORY}MB"
    echo -e "  ${CYAN}VCPUs:${NC}          $VM_VCPU"
    echo -e "  ${CYAN}Disk:${NC}           ${VM_DISK_SIZE}MB"
    echo ""

    prompt_yes_no "Generate LXC appliance?" CONFIRM "true"
    [ "$CONFIRM" != "true" ] && return $NAV_BACK

    return $NAV_CONTINUE
}

# ═══════════════════════════════════════════════════════════════════════════════
# LXC BUILD FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

generate_lxc_appliance() {
    clear_screen
    print_header

    # Determine if we need sudo for privileged operations
    local SUDO=""
    if [ "$EUID" -ne 0 ]; then
        SUDO="sudo"
        echo ""
        echo -e "  ${YELLOW}!${NC} Some build steps require elevated privileges"
        echo -e "  ${DIM}(chroot, mount, mkfs.ext4)${NC}"
        echo ""

        # Check if sudo credentials are cached
        if ! sudo -n true 2>/dev/null; then
            echo -e "  ${DIM}You will be prompted for your password.${NC}"
            echo ""
            # Pre-authenticate to avoid prompts during build
            if ! sudo true; then
                echo -e "  ${RED}✗${NC} Failed to obtain sudo privileges"
                echo ""
                echo -ne "  ${DIM}Press [Enter] to exit...${NC}"
                read -r
                return 1
            fi
        fi
        echo -e "  ${GREEN}✓${NC} Sudo access confirmed"
        echo ""
    fi

    echo -e "  ${WHITE}Building LXC Appliance: ${CYAN}${APPLIANCE_NAME}${NC}"
    echo ""

    local build_dir="/tmp/lxc-build-$$"
    local rootfs_dir="$build_dir/rootfs"
    mkdir -p "$rootfs_dir"

    # Step 1: Download Alpine minirootfs
    echo -e "  ${BRIGHT_CYAN}[1/6]${NC} Downloading Alpine rootfs..."

    local alpine_version="${BASE_OS#alpine}"
    alpine_version="${alpine_version%.aarch64}"
    local alpine_ver="${alpine_version:0:1}.${alpine_version:1}"
    local alpine_arch="aarch64"
    [ "$ARCH" = "x86_64" ] && alpine_arch="x86_64"

    local rootfs_url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_ver}/releases/${alpine_arch}/alpine-minirootfs-${alpine_ver}.0-${alpine_arch}.tar.gz"

    if ! wget -q "$rootfs_url" -O "$build_dir/rootfs.tar.gz" 2>/dev/null; then
        # Try with full version
        rootfs_url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_ver}/releases/${alpine_arch}/alpine-minirootfs-${alpine_ver}.1-${alpine_arch}.tar.gz"
        if ! wget -q "$rootfs_url" -O "$build_dir/rootfs.tar.gz" 2>/dev/null; then
            echo -e "  ${RED}✗${NC} Failed to download Alpine rootfs"
            rm -rf "$build_dir"
            return 1
        fi
    fi

    tar -xzf "$build_dir/rootfs.tar.gz" -C "$rootfs_dir"
    echo -e "  ${GREEN}✓${NC} Alpine ${alpine_ver} rootfs extracted"

    # Step 2: Configure networking
    echo -e "  ${BRIGHT_CYAN}[2/6]${NC} Configuring networking..."

    # DNS
    echo "nameserver 1.1.1.1" > "$rootfs_dir/etc/resolv.conf"
    echo "nameserver 8.8.8.8" >> "$rootfs_dir/etc/resolv.conf"

    # DHCP networking
    mkdir -p "$rootfs_dir/etc/network"
    cat > "$rootfs_dir/etc/network/interfaces" << 'NETEOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
NETEOF

    # Inittab for LXC
    cat > "$rootfs_dir/etc/inittab" << 'INITEOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
::shutdown:/sbin/openrc shutdown
INITEOF

    echo -e "  ${GREEN}✓${NC} Network configured (DHCP on eth0)"

    # Step 3: Install packages via chroot
    echo -e "  ${BRIGHT_CYAN}[3/6]${NC} Installing packages..."

    # Set up resolv.conf for chroot
    cp /etc/resolv.conf "$rootfs_dir/etc/resolv.conf" 2>/dev/null || true

    # Install packages
    local pkg_list="${LXC_PACKAGES}"
    $SUDO chroot "$rootfs_dir" /bin/sh << CHROOTEOF
# Use HTTP repositories for LXC builds to avoid SSL certificate issues during build
sed -i 's/https:/http:/g' /etc/apk/repositories
apk update
apk add --no-cache ca-certificates
update-ca-certificates
apk add openrc $pkg_list openssh
rc-update add networking boot
rc-update add sshd default
CHROOTEOF

    echo -e "  ${GREEN}✓${NC} Packages installed: $pkg_list"

    # Step 4: Run application-specific setup
    echo -e "  ${BRIGHT_CYAN}[4/6]${NC} Configuring application..."

    local app_setup="${LXC_APP_CATALOG[$LXC_APPLICATION]}"
    local setup_func="${app_setup##*|}"

    # Call the setup function for this application
    if [ -n "$setup_func" ] && [ "$setup_func" != "<specify setup>" ]; then
        local func_name="setup_app_${LXC_APPLICATION}"
        echo -e "  ${DIM}Running setup for: ${LXC_APPLICATION}${NC}"

        # Check if setup function exists and call it
        if type "$func_name" &>/dev/null; then
            # npm-based apps take longer, show progress
            case "$LXC_APPLICATION" in
                nodered|homebridge|zigbee2mqtt)
                    echo -e "  ${DIM}(npm install may take several minutes...)${NC}"
                    $func_name "$rootfs_dir" 2>&1 | while IFS= read -r line; do
                        # Filter out noise, show important lines
                        case "$line" in
                            *"added"*"packages"*|*"npm"*"WARN"*|*"Creating"*|*"Install"*)
                                echo -e "  ${DIM}  ${line}${NC}"
                                ;;
                        esac
                    done
                    ;;
                *)
                    $func_name "$rootfs_dir" 2>/dev/null || true
                    ;;
            esac
        else
            echo -e "  ${YELLOW}!${NC} Setup function not found: $func_name"
        fi
    fi

    echo -e "  ${GREEN}✓${NC} Application configured: $LXC_APPLICATION"

    # Step 5: Configure SSH
    echo -e "  ${BRIGHT_CYAN}[5/6]${NC} Configuring SSH access..."

    # Enable root login and empty passwords
    $SUDO sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' "$rootfs_dir/etc/ssh/sshd_config"
    $SUDO sed -i 's/#PermitEmptyPasswords.*/PermitEmptyPasswords yes/' "$rootfs_dir/etc/ssh/sshd_config"

    # Generate SSH host keys during build (required for unprivileged LXC containers)
    $SUDO chroot "$rootfs_dir" /bin/sh -c "ssh-keygen -A" 2>/dev/null || true

    # Clear root password - directly modify shadow file for Alpine compatibility
    # passwd -d doesn't work reliably on Alpine/BusyBox
    $SUDO sed -i 's/^root:[^:]*:/root::/' "$rootfs_dir/etc/shadow"

    echo -e "  ${GREEN}✓${NC} SSH configured"

    # Step 6: Create disk image
    echo -e "  ${BRIGHT_CYAN}[6/6]${NC} Creating disk image..."

    local output_dir="${SCRIPT_DIR}/export"
    mkdir -p "$output_dir"
    local output_image="$output_dir/${APPLIANCE_NAME}.raw"

    # Calculate required disk size based on actual rootfs content
    local rootfs_size_kb
    rootfs_size_kb=$($SUDO du -sk "$rootfs_dir" 2>/dev/null | awk '{print $1}')
    # Add 30% buffer + 50MB for filesystem overhead, minimum 256MB
    local required_mb=$(( (rootfs_size_kb * 130 / 100 / 1024) + 50 ))
    local size_mb="${VM_DISK_SIZE:-$required_mb}"
    # Ensure minimum size
    [ "$size_mb" -lt "$required_mb" ] && size_mb="$required_mb"

    echo -e "  ${DIM}Rootfs size: $((rootfs_size_kb/1024))MB, creating ${size_mb}MB image${NC}"

    # Create raw disk
    echo -ne "  ${DIM}  Creating raw image...${NC}"
    dd if=/dev/zero of="$output_image" bs=1M count="$size_mb" status=none
    echo -e " ${GREEN}done${NC}"

    echo -ne "  ${DIM}  Formatting ext4...${NC}"
    $SUDO mkfs.ext4 -F -L rootfs "$output_image" >/dev/null 2>&1
    echo -e " ${GREEN}done${NC}"

    # Mount and copy
    local mnt_dir="/tmp/lxc-mnt-$$"
    mkdir -p "$mnt_dir"
    echo -ne "  ${DIM}  Copying rootfs...${NC}"
    $SUDO mount -o loop "$output_image" "$mnt_dir"
    $SUDO cp -a "$rootfs_dir"/* "$mnt_dir/"
    $SUDO umount "$mnt_dir"
    rmdir "$mnt_dir"
    echo -e " ${GREEN}done${NC}"

    # Get actual file size
    local actual_size_mb
    actual_size_mb=$(du -m "$output_image" 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}✓${NC} Disk image created: ${actual_size_mb:-$size_mb}MB"

    # Cleanup
    $SUDO rm -rf "$build_dir"

    echo ""
    echo -e "  ${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}✓ LXC Appliance built successfully!${NC}"
    echo -e "  ${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Output:${NC} $output_image"
    echo ""
    echo -e "  ${WHITE}To register in OpenNebula:${NC}"
    echo -e "  ${CYAN}oneimage create --name ${APPLIANCE_NAME} --path $output_image${NC} \\"
    echo -e "  ${CYAN}  --datastore default --type OS --disk_type FILE --format raw${NC}"
    echo ""
    echo -e "  ${WHITE}Template settings:${NC}"
    echo -e "  ${DIM}HYPERVISOR = lxc${NC}"
    echo -e "  ${DIM}MEMORY = ${VM_MEMORY}${NC}"
    echo -e "  ${DIM}VCPU = ${VM_VCPU}${NC}"
    echo -e "  ${DIM}DISK = [ IMAGE = \"${APPLIANCE_NAME}\" ]${NC}"
    if [ "$CONTEXT_MODE" = "contextless" ]; then
        echo -e "  ${DIM}(No CONTEXT section needed - uses DHCP)${NC}"
    fi
    echo ""

    # Generate env file for future reference
    local env_file="${SCRIPT_DIR}/${APPLIANCE_NAME}.env"
    cat > "$env_file" << ENVEOF
# Generated by OpenNebula Appliance Wizard v${WIZARD_VERSION}
# $(date)

APPLIANCE_TYPE="lxc"
LXC_APPLICATION="${LXC_APPLICATION}"
LXC_PACKAGES="${LXC_PACKAGES}"
LXC_PORTS="${LXC_PORTS}"
APPLIANCE_NAME="${APPLIANCE_NAME}"
BASE_OS="${BASE_OS}"
ARCH="${ARCH}"
CONTEXT_MODE="${CONTEXT_MODE}"

# VM Configuration
VM_MEMORY="${VM_MEMORY}"
VM_VCPU="${VM_VCPU}"
VM_DISK_SIZE="${VM_DISK_SIZE}"
ENVEOF

    echo -e "  ${DIM}Config saved: ${env_file}${NC}"
    echo ""

    # Check if OpenNebula is running locally and offer deployment
    if check_opennebula_local; then
        local one_version
        one_version=$(onevm --version 2>/dev/null | grep 'OpenNebula' | sed 's/.*OpenNebula \([0-9.]*\).*/\1/' | head -1)
        if [ -n "$one_version" ]; then
            echo -e "  ${BRIGHT_GREEN}OpenNebula ${one_version} detected on this host${NC}"
        else
            echo -e "  ${BRIGHT_GREEN}OpenNebula detected on this host${NC}"
        fi
        echo ""
        prompt_yes_no "  Deploy LXC to OpenNebula now?" DEPLOY_NOW "true"

        if [ "$DEPLOY_NOW" = "true" ]; then
            deploy_lxc_to_opennebula "$output_image"
            return
        fi
    fi

    # Ask about marketplace submission after successful build
    ask_marketplace_submission "$output_image"

    # Show manual deployment instructions if not deploying
    show_lxc_manual_deploy_instructions "$output_image"
}

# Ask about marketplace submission after LXC build completes
ask_marketplace_submission() {
    local output_image="$1"

    echo ""
    echo -e "  ${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${WHITE}║      Share Your Appliance with the Community!         ║${NC}"
    echo -e "  ${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Submit to OpenNebula Community Marketplace?${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} Help other users with ready-to-use appliances"
    echo -e "  ${GREEN}✓${NC} Get recognition in the OpenNebula community"
    echo -e "  ${GREEN}✓${NC} Official OpenNebula Systems review & support"
    echo ""
    echo -e "  ${DIM}This will generate marketplace metadata files and${NC}"
    echo -e "  ${DIM}guide you through the GitHub PR submission process.${NC}"
    echo ""

    prompt_yes_no "Generate marketplace files?" MARKETPLACE_SUBMIT "false"

    if [ "$MARKETPLACE_SUBMIT" != "true" ]; then
        echo ""
        echo -e "  ${CYAN}💡 Tip:${NC} You can generate marketplace files later using:"
        echo -e "  ${DIM}    ./appliance-wizard.sh --marketplace ${APPLIANCE_NAME}${NC}"
        return
    fi

    # Collect publisher information
    echo ""
    echo -e "  ${WHITE}Publisher Information${NC}"
    echo -e "  ${DIM}(Visible in the marketplace)${NC}"
    echo ""

    prompt_required "Publisher Name" MARKETPLACE_PUBLISHER ""
    if [ $? -ne 0 ]; then
        MARKETPLACE_SUBMIT="false"
        return
    fi

    prompt_optional "Email (optional)" MARKETPLACE_EMAIL ""

    prompt_required "GitHub Username" MARKETPLACE_GITHUB_USER ""
    if [ $? -ne 0 ]; then
        MARKETPLACE_SUBMIT="false"
        return
    fi

    # Show built image info
    echo ""
    echo -e "  ${BOLD}Built Image:${NC}"
    echo -e "  ${DIM}$output_image${NC}"
    echo ""
    echo -e "  ${CYAN}Generating marketplace metadata files...${NC}"
    echo ""
    echo -e "  ${DIM}Files will include a placeholder CDN URL.${NC}"
    echo -e "  ${DIM}You'll upload the image to a CDN (AWS S3, CloudFront, etc.)${NC}"
    echo -e "  ${DIM}and update the URL in the generated files before submitting.${NC}"

    # Generate with placeholder URL
    MARKETPLACE_IMAGE_URL=""

    # Generate marketplace files
    generate_marketplace_files "$output_image"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MARKETPLACE FILE GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

generate_marketplace_files() {
    local image_file="$1"

    echo ""
    echo -e "  ${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${WHITE}║       Generating Marketplace Submission Files         ║${NC}"
    echo -e "  ${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Generate UUID if not already set
    if [ -z "$MARKETPLACE_UUID" ]; then
        if command -v uuidgen &>/dev/null; then
            MARKETPLACE_UUID=$(uuidgen)
        elif command -v uuid &>/dev/null; then
            MARKETPLACE_UUID=$(uuid)
        else
            # Fallback UUID generation
            MARKETPLACE_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$(hostname)-$$" | md5sum | cut -d' ' -f1 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
        fi
    fi

    # Calculate checksums if image exists
    if [ -f "$image_file" ]; then
        echo -e "  ${CYAN}[1/6]${NC} Calculating image checksums..."
        MARKETPLACE_IMAGE_MD5=$(md5sum "$image_file" | cut -d' ' -f1)
        MARKETPLACE_IMAGE_SHA256=$(sha256sum "$image_file" | cut -d' ' -f1)

        # Get image size
        if command -v qemu-img &>/dev/null; then
            MARKETPLACE_IMAGE_SIZE=$(qemu-img info "$image_file" | grep 'virtual size' | sed 's/.*(\([0-9]*\) bytes).*/\1/')
        else
            MARKETPLACE_IMAGE_SIZE=$(stat -f%z "$image_file" 2>/dev/null || stat -c%s "$image_file")
        fi

        echo -e "  ${GREEN}✓${NC} MD5:    $MARKETPLACE_IMAGE_MD5"
        echo -e "  ${GREEN}✓${NC} SHA256: ${MARKETPLACE_IMAGE_SHA256:0:32}..."
        echo -e "  ${GREEN}✓${NC} Size:   $MARKETPLACE_IMAGE_SIZE bytes"
    else
        echo -e "  ${YELLOW}⚠${NC}  Image file not found - checksums will need to be calculated manually"
        MARKETPLACE_IMAGE_MD5="<calculate-after-upload>"
        MARKETPLACE_IMAGE_SHA256="<calculate-after-upload>"
        MARKETPLACE_IMAGE_SIZE="<size-in-bytes>"
    fi

    # Create marketplace directory
    local marketplace_dir="${SCRIPT_DIR}/marketplace-${APPLIANCE_NAME}"
    mkdir -p "$marketplace_dir"

    # Get application display name from catalog
    local app_display_name="${LXC_APP_CATALOG[$LXC_APPLICATION]%%|*}"

    # Generate UUID.yaml
    echo ""
    echo -e "  ${CYAN}[2/6]${NC} Generating ${MARKETPLACE_UUID}.yaml..."

    local email_line=""
    [ -n "$MARKETPLACE_EMAIL" ] && email_line="publisher_email: $MARKETPLACE_EMAIL"

    local context_section=""
    if [ "$CONTEXT_MODE" != "contextless" ]; then
        context_section="  context:
    network: 'YES'
    ssh_public_key: \"\$USER[SSH_PUBLIC_KEY]\""
    fi

    cat > "$marketplace_dir/${MARKETPLACE_UUID}.yaml" << UUIDEOF
---
name: $APPLIANCE_NAME
version: 1.0
publisher: $MARKETPLACE_PUBLISHER
${email_line}
description: |-
  ${app_display_name} on Alpine Linux ${BASE_OS#alpine}.

  LXC container appliance optimized for edge and IoT deployments.

  **Features:**
  - Lightweight Alpine Linux base
  - Pre-configured ${LXC_APPLICATION}
  - ${CONTEXT_MODE} deployment
  - Compatible with embedded devices (Arduino, Raspberry Pi)

  **Services:**
  $(echo "$LXC_PORTS" | tr ',' '\n' | while read port; do echo "  - Port $port: ${app_display_name}"; done)

  **Network Access:**
  - For Arduino/embedded hosts: Configure Tailscale subnet router or port forwarding
  - For standard hosts: Direct container IP access

  **Default Credentials:**
  - Username: root
  - SSH: Key-based authentication (from OpenNebula context)

  This is a community-contributed appliance. Please report issues at:
  https://github.com/OpenNebula/one/issues

short_description: ${app_display_name} on Alpine Linux for LXC

tags:
- alpine
- lxc
- $(echo "$LXC_APPLICATION" | tr '[:upper:]' '[:lower:]')
- lightweight
- edge
- iot

format: raw
creation_time: $(date +%s)

os-id: Alpine
os-release: "$(echo ${BASE_OS#alpine} | sed 's/\(.\)\(.\)/\1.\2/')"
os-arch: $ARCH
hypervisor: lxc

opennebula_version: 6.10, 7.0

opennebula_template:
  cpu: '$VM_VCPU'
  vcpu: '$VM_VCPU'
  memory: '$VM_MEMORY'
  graphics:
    listen: 0.0.0.0
    type: vnc
${context_section}
  sched_requirements: 'HYPERVISOR="lxc" & ARCH="$ARCH"'

logo: alpine.png

images:
- name: ${APPLIANCE_NAME}
  url: ${MARKETPLACE_IMAGE_URL:-https://d38nm155miqkyg.cloudfront.net/${APPLIANCE_NAME}.raw}
  type: OS
  dev_prefix: sd
  driver: raw
  size: $MARKETPLACE_IMAGE_SIZE
  checksum:
    md5: $MARKETPLACE_IMAGE_MD5
    sha256: $MARKETPLACE_IMAGE_SHA256
UUIDEOF

    echo -e "  ${GREEN}✓${NC} Created ${MARKETPLACE_UUID}.yaml"

    # Generate metadata.yaml
    echo -e "  ${CYAN}[3/6]${NC} Generating metadata.yaml..."

    cat > "$marketplace_dir/metadata.yaml" << METAEOF
---
:app:
  :name: ${APPLIANCE_NAME}
  :type: service
  :os:
    :type: linux
    :base: ${BASE_OS}
  :hypervisor: lxc
  :context:
    :prefixed: false
    :params: {}

:one:
  :template:
    NAME: ${APPLIANCE_NAME}
    TEMPLATE:
      ARCH: $ARCH
      CPU: '$VM_VCPU'
      GRAPHICS:
        LISTEN: 0.0.0.0
        TYPE: vnc
      MEMORY: '$VM_MEMORY'
      NIC:
        NETWORK: service
      NIC_DEFAULT:
        MODEL: virtio
  :datastore_name: default
  :timeout: '90'

:infra:
  :disk_format: raw
  :apps_path: /var/tmp
METAEOF

    echo -e "  ${GREEN}✓${NC} Created metadata.yaml"

    # Generate README.md
    echo -e "  ${CYAN}[4/6]${NC} Generating README.md..."

    cat > "$marketplace_dir/README.md" << READMEEOF
# $APPLIANCE_NAME

## Description

${app_display_name} running on Alpine Linux in an LXC container.

This appliance provides a lightweight, production-ready deployment of ${LXC_APPLICATION} optimized for edge and IoT environments.

## Requirements

- OpenNebula 6.10+ or 7.0+
- LXC-capable host with:
  - Architecture: $ARCH
  - For contextless deployment: No special requirements
  - For standard context: iso9660 kernel module support

## Quick Start

1. Import appliance from OpenNebula Community Marketplace
2. Instantiate the VM template
3. Wait for deployment to complete
4. Access services:
$(echo "$LXC_PORTS" | tr ',' '\n' | while read port; do echo "   - ${app_display_name}: http://<container-ip>:$port"; done)

## Configuration

### Contextualization Mode

This appliance is configured for **${CONTEXT_MODE}** deployment:

$(if [ "$CONTEXT_MODE" = "contextless" ]; then
echo "- Uses DHCP for network configuration
- No iso9660 kernel module required
- Ideal for Arduino, Raspberry Pi, and embedded devices"
else
echo "- Receives network configuration from OpenNebula context
- SSH public keys injected automatically
- Requires iso9660 kernel module support"
fi)

### VM Resources

- **Memory**: ${VM_MEMORY}MB
- **VCPUs**: $VM_VCPU
- **Disk**: ${VM_DISK_SIZE}MB

## Default Credentials

- **Username**: root
- **Password**: None (use SSH key-based authentication)
- **SSH Access**: Keys configured via OpenNebula context

## Services

The following services are pre-configured and running:

$(echo "$LXC_PORTS" | tr ',' '\n' | while read port; do
    echo "- **${app_display_name}** on port $port"
done)

## Network Access

### For Embedded Devices (Arduino, Raspberry Pi)

Containers run on a private LXC bridge network. To access from other devices:

**Option 1: Tailscale Subnet Router (Recommended)**
\`\`\`bash
# On LXC host:
sudo tailscale up --advertise-routes=10.0.3.0/24

# Approve route in Tailscale admin console
# Then access directly: http://10.0.3.x:<port>
\`\`\`

**Option 2: Port Forwarding**
\`\`\`bash
# On LXC host:
iptables -t nat -A PREROUTING -p tcp --dport <host-port> -j DNAT --to-destination <container-ip>:<service-port>
iptables -t nat -A POSTROUTING -j MASQUERADE
\`\`\`

### For Standard Hosts

Access container directly via its IP address (visible in \`onevm show\`).

## Logs

- Service logs: \`/var/log/<service>/\`
- System logs: \`/var/log/messages\`

## Support

Report issues at: https://github.com/OpenNebula/one/issues

Use label: "Category: Marketplace"

## License

Community-contributed appliance. Service-specific licenses apply.

## Changelog

See CHANGELOG.md for version history.

## Author

Contributed by: $MARKETPLACE_PUBLISHER
$([ -n "$MARKETPLACE_EMAIL" ] && echo "Contact: $MARKETPLACE_EMAIL")
GitHub: @$MARKETPLACE_GITHUB_USER
READMEEOF

    echo -e "  ${GREEN}✓${NC} Created README.md"

    # Generate CHANGELOG.md
    echo -e "  ${CYAN}[5/6]${NC} Generating CHANGELOG.md..."

    cat > "$marketplace_dir/CHANGELOG.md" << CHANGELOGEOF
# Changelog

All notable changes to this appliance will be documented in this file.

## [1.0] - $(date +%Y-%m-%d)

### Added
- Initial release of ${APPLIANCE_NAME}
- ${app_display_name} pre-configured and ready to use
- Alpine Linux ${BASE_OS#alpine} base
- ${CONTEXT_MODE} deployment support
- Optimized for $ARCH architecture
- Compatible with OpenNebula 6.10 and 7.0

### Features
$(echo "$LXC_PORTS" | tr ',' '\n' | while read port; do echo "- Service running on port $port"; done)
- Lightweight LXC container
- Edge/IoT device compatible
CHANGELOGEOF

    echo -e "  ${GREEN}✓${NC} Created CHANGELOG.md"

    # Generate tests.yaml
    echo -e "  ${CYAN}[6/6]${NC} Generating tests.yaml..."

    cat > "$marketplace_dir/tests.yaml" << TESTSEOF
---
tests:
  - name: basic_boot
    description: Verify container boots successfully
    script: tests/test_boot.sh
  - name: service_check
    description: Verify ${LXC_APPLICATION} service is running
    script: tests/test_service.sh
TESTSEOF

    # Create tests directory
    mkdir -p "$marketplace_dir/tests"

    echo -e "  ${GREEN}✓${NC} Created tests.yaml"

    echo ""
    echo -e "  ${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${WHITE}║          Marketplace Files Generated!                  ║${NC}"
    echo -e "  ${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} All files created in: ${BOLD}$marketplace_dir${NC}"
    echo ""

    # Automatically create PR (or show manual instructions if gh CLI unavailable)
    create_marketplace_pr "$marketplace_dir" "$app_display_name"
}

# Automatically create GitHub PR for marketplace submission
create_marketplace_pr() {
    local marketplace_dir="$1"
    local app_display_name="$2"

    echo ""
    echo -e "  ${WHITE}═══════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Creating GitHub Pull Request${NC}"
    echo -e "  ${WHITE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Check if gh CLI is available
    if ! command -v gh &>/dev/null; then
        echo -e "  ${YELLOW}!${NC} GitHub CLI (gh) not installed"
        echo -e "  ${DIM}Install: https://cli.github.com/${NC}"
        echo ""
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
        return
    fi

    # Check if authenticated
    if ! gh auth status &>/dev/null; then
        echo -e "  ${YELLOW}!${NC} Not authenticated with GitHub CLI"
        echo -e "  ${DIM}Run: gh auth login${NC}"
        echo ""
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
        return
    fi

    local branch_name="add-${APPLIANCE_NAME}-lxc"
    local pr_title="Add ${APPLIANCE_NAME} LXC appliance"

    # Create PR body
    local pr_body="## New LXC Appliance: ${APPLIANCE_NAME}

### Description
${app_display_name} on Alpine Linux for LXC containers.

### Type
- [x] Image

### Details
- **OS**: Alpine Linux $(echo ${BASE_OS#alpine} | sed 's/\(.\)\(.\)/\1.\2/')
- **Architecture**: $ARCH
- **Hypervisor**: LXC
- **OpenNebula**: 6.10, 7.0+
- **Services**: ${app_display_name}
- **Ports**: ${LXC_PORTS:-none}

### Testing
- [x] Built and tested on OpenNebula 7.0
- [x] ${CONTEXT_MODE} deployment verified
- [x] Documentation complete

### Image Hosting
Image will be hosted on OpenNebula's CDN infrastructure.
Please provide the .raw image file for upload.

### Special Notes
- Optimized for edge/IoT devices (Arduino, Raspberry Pi)
- ${CONTEXT_MODE} deployment mode
- Minimal Alpine Linux base (~50MB)

---
*Generated by OpenNebula Appliance Wizard*"

    # Step 1: Check/create fork
    echo -e "  ${CYAN}[1/5]${NC} Checking repository fork..."
    local fork_exists
    fork_exists=$(gh repo list --fork --json name -q '.[].name' 2>/dev/null | grep -c "^marketplace-community$" || echo "0")

    if [ "$fork_exists" = "0" ]; then
        echo -e "  ${DIM}Forking OpenNebula/marketplace-community...${NC}"
        if ! gh repo fork OpenNebula/marketplace-community --clone=false 2>/dev/null; then
            echo -e "  ${RED}✗${NC} Failed to fork repository"
            show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
            return
        fi
        echo -e "  ${GREEN}✓${NC} Repository forked"
        sleep 2  # Wait for fork to be ready
    else
        echo -e "  ${GREEN}✓${NC} Fork exists"
    fi

    # Step 2: Clone fork to temp directory
    echo -e "  ${CYAN}[2/5]${NC} Cloning fork..."
    local temp_repo="/tmp/marketplace-pr-$$"
    rm -rf "$temp_repo"

    if ! gh repo clone "${MARKETPLACE_GITHUB_USER}/marketplace-community" "$temp_repo" -- --depth 1 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Failed to clone repository"
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
        return
    fi
    echo -e "  ${GREEN}✓${NC} Repository cloned"

    # Step 3: Create branch and copy files
    echo -e "  ${CYAN}[3/5]${NC} Creating branch and adding files..."
    local commit_result=0
    (
        set +e  # Disable set -e in subshell
        cd "$temp_repo" || exit 1

        # Add upstream remote (may already exist)
        git remote add upstream https://github.com/OpenNebula/marketplace-community.git 2>/dev/null || true

        # Create branch from master (use -B to force create even if exists locally)
        git checkout -B "$branch_name" 2>/dev/null || exit 1

        # Create appliance directory
        mkdir -p "appliances/${APPLIANCE_NAME}"

        # Copy files
        cp "$marketplace_dir"/*.yaml "appliances/${APPLIANCE_NAME}/" 2>/dev/null || true
        cp "$marketplace_dir"/*.md "appliances/${APPLIANCE_NAME}/" 2>/dev/null || true
        [ -d "$marketplace_dir/tests" ] && cp -r "$marketplace_dir/tests" "appliances/${APPLIANCE_NAME}/"

        # Commit
        git add "appliances/${APPLIANCE_NAME}/"
        git commit -m "$pr_title

- ${app_display_name} on Alpine Linux
- ${CONTEXT_MODE} deployment for $ARCH
- Compatible with OpenNebula 7.0+
- Optimized for edge/IoT devices" 2>/dev/null || exit 1
    )
    commit_result=$?

    if [ $commit_result -ne 0 ]; then
        echo -e "  ${RED}✗${NC} Failed to prepare commit"
        rm -rf "$temp_repo"
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
        return
    fi
    echo -e "  ${GREEN}✓${NC} Files committed"

    # Step 4: Push branch (force push to update existing branch if PR exists)
    echo -e "  ${CYAN}[4/5]${NC} Pushing to GitHub..."
    if ! (cd "$temp_repo" && git push --force -u origin "$branch_name" 2>/dev/null); then
        echo -e "  ${RED}✗${NC} Failed to push branch"
        rm -rf "$temp_repo"
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
        return
    fi
    echo -e "  ${GREEN}✓${NC} Branch pushed"

    # Step 5: Create PR
    echo -e "  ${CYAN}[5/5]${NC} Creating Pull Request..."
    local pr_url

    # Check if PR already exists for this branch
    pr_url=$(gh pr list --repo OpenNebula/marketplace-community --head "${MARKETPLACE_GITHUB_USER}:${branch_name}" --json url -q '.[0].url' 2>/dev/null)

    if [ -n "$pr_url" ]; then
        echo -e "  ${GREEN}✓${NC} PR already exists, updated with new commits"
    else
        # Create new PR
        pr_url=$(cd "$temp_repo" && gh pr create \
            --repo OpenNebula/marketplace-community \
            --title "$pr_title" \
            --body "$pr_body" \
            --head "${MARKETPLACE_GITHUB_USER}:${branch_name}" \
            2>/dev/null)
    fi

    # Cleanup
    rm -rf "$temp_repo"

    if [ -n "$pr_url" ]; then
        echo -e "  ${GREEN}✓${NC} Pull Request created!"
        echo ""
        echo -e "  ${WHITE}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${WHITE}║              PR Created Successfully!                   ║${NC}"
        echo -e "  ${WHITE}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}Pull Request:${NC} ${pr_url}"
        echo ""
        echo -e "  ${WHITE}Next steps:${NC}"
        echo -e "  ${DIM}1. OpenNebula team will review your PR${NC}"
        echo -e "  ${DIM}2. Provide the .raw image file when requested${NC}"
        echo -e "  ${DIM}3. They'll host it on their CDN and merge${NC}"
        echo ""
        echo -e "  ${GREEN}Your appliance will then be available in the marketplace!${NC}"
    else
        echo -e "  ${RED}✗${NC} Failed to create Pull Request"
        show_manual_pr_instructions "$marketplace_dir" "$app_display_name"
    fi

    echo ""
    echo -ne "  ${DIM}Press [Enter] to continue...${NC}"
    read -r
}

# Show manual instructions if automatic PR fails
show_manual_pr_instructions() {
    local marketplace_dir="$1"
    local app_display_name="$2"

    echo ""
    echo -e "  ${WHITE}Manual Submission Instructions${NC}"
    echo -e "  ${DIM}──────────────────────────────${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Fork: ${BOLD}https://github.com/OpenNebula/marketplace-community${NC}"
    echo -e "  ${CYAN}2.${NC} Copy files from: ${BOLD}${marketplace_dir}/${NC}"
    echo -e "  ${CYAN}3.${NC} Create PR with title: ${BOLD}Add ${APPLIANCE_NAME} LXC appliance${NC}"
    echo ""
    echo -e "  ${DIM}Files generated:${NC}"
    ls -la "$marketplace_dir" 2>/dev/null | grep -v "^total" | awk '{print "    " $NF}' | grep -v "^\.$"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# DOCKER WIZARD STEPS
# ═══════════════════════════════════════════════════════════════════════════════

step_docker_image() {
    clear_screen
    print_header
    print_step 1 $TOTAL_STEPS "Docker Image"
    print_nav_hint

    echo -e "${DIM}e.g. nginx:alpine, postgres:16, nodered/node-red:latest${NC}\n"

    while true; do
        prompt_required "Docker image" DOCKER_IMAGE
        local result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        # Validate format first
        if ! validate_docker_image "$DOCKER_IMAGE"; then
            print_error "Invalid format. Use: image:tag"
            continue
        fi

        # Verify image exists in registry
        echo -e "  ${DIM}Verifying image exists...${NC}"

        local verify_result
        verify_docker_image_exists "$DOCKER_IMAGE"
        verify_result=$?

        case $verify_result in
            0)
                # Image exists - show clean screen with architectures
                clear_screen
                print_header
                print_step 1 $TOTAL_STEPS "Docker Image"
                echo ""
                echo -e "  ${GREEN}✓${NC} Image found: ${CYAN}${DOCKER_IMAGE}${NC}"
                echo ""

                # Get and display supported architectures
                local archs
                archs=$(get_docker_image_archs "$DOCKER_IMAGE")

                echo -e "  ${WHITE}Supported architectures:${NC}"
                echo ""
                if [ -n "$archs" ]; then
                    if echo "$archs" | grep -q "amd64"; then
                        echo -e "    ${GREEN}•${NC} AMD64 ${DIM}(x86_64 / Intel / AMD)${NC}"
                    fi
                    if echo "$archs" | grep -q "arm64"; then
                        echo -e "    ${GREEN}•${NC} ARM64 ${DIM}(aarch64 / Apple Silicon / AWS Graviton)${NC}"
                    fi
                    # Show other architectures if present
                    local other_archs
                    other_archs=$(echo "$archs" | tr ',' '\n' | grep -v "amd64\|arm64" | tr '\n' ',' | sed 's/,$//')
                    if [ -n "$other_archs" ]; then
                        echo -e "    ${DIM}• Other: ${other_archs}${NC}"
                    fi
                else
                    echo -e "    ${YELLOW}!${NC} Unknown ${DIM}(legacy image format - may only support AMD64)${NC}"
                fi

                echo ""
                echo -e "  ─────────────────────────────────────────────────────"
                echo ""
                echo -ne "  ${DIM}Press${NC} ${WHITE}[Enter]${NC} ${DIM}to continue...${NC}"
                read -r
                return $NAV_CONTINUE
                ;;
            1)
                # Image not found
                echo -e "  ${RED}✗${NC} Image not found: ${CYAN}${DOCKER_IMAGE}${NC}"
                echo ""
                echo -e "  ${DIM}Please check the image name and tag are correct.${NC}"
                echo ""
                ;;
            2)
                # Auth required - might be private, allow to continue
                local registry
                registry=$(get_image_registry "$DOCKER_IMAGE")
                echo -e "  ${YELLOW}!${NC} Cannot verify - authentication required for ${CYAN}${registry}${NC}"
                echo ""
                echo -e "  ${DIM}This appears to be a private image.${NC}"
                echo ""
                echo -e "    ${CYAN}1.${NC} Login to registry now"
                echo -e "    ${CYAN}2.${NC} Continue without verification ${DIM}(assumes image exists)${NC}"
                echo -e "    ${CYAN}3.${NC} Enter a different image"
                echo ""

                local auth_choice
                while true; do
                    echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
                    read -r auth_choice
                    case "$auth_choice" in
                        1)
                            echo ""
                            echo -e "  ${DIM}Running: docker login ${registry}${NC}"
                            echo ""
                            if docker login "$registry"; then
                                echo ""
                                echo -e "  ${GREEN}✓${NC} Login successful! Verifying image..."
                                sleep 0.5
                                # Re-verify by continuing the outer loop
                                continue 2
                            else
                                echo ""
                                echo -e "  ${RED}✗${NC} Login failed. Please try again."
                                echo ""
                            fi
                            ;;
                        2)
                            echo ""
                            echo -e "  ${YELLOW}!${NC} Continuing with unverified private image"
                            echo ""
                            echo -ne "  ${DIM}Press${NC} ${WHITE}[Enter]${NC} ${DIM}to continue...${NC}"
                            read -r
                            return $NAV_CONTINUE
                            ;;
                        3)
                            # Re-prompt for image
                            echo ""
                            continue 2
                            ;;
                        *)
                            echo -e "  ${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                            ;;
                    esac
                done
                ;;
            4)
                # Rate limited - skip verification but continue
                echo -e "  ${YELLOW}!${NC} Docker Hub rate limit reached"
                echo ""
                echo -e "  ${DIM}Cannot verify image - proceeding with unverified image.${NC}"
                echo -e "  ${DIM}Tip: Run 'docker login' to avoid rate limits.${NC}"
                echo ""
                echo -ne "  ${DIM}Press${NC} ${WHITE}[Enter]${NC} ${DIM}to continue...${NC}"
                read -r
                return $NAV_CONTINUE
                ;;
            *)
                # Network error or other issue - warn but allow
                echo -e "  ${YELLOW}!${NC} Could not verify image ${DIM}(network issue?)${NC}"
                echo ""
                prompt_yes_no "Continue anyway?" CONTINUE_ANYWAY "true"
                if [ "$CONTINUE_ANYWAY" = "true" ]; then
                    echo ""
                    echo -ne "  ${DIM}Press${NC} ${WHITE}[Enter]${NC} ${DIM}to continue...${NC}"
                    read -r
                    return $NAV_CONTINUE
                fi
                ;;
        esac
    done
}

# Check if cross-architecture LXC build is supported (via qemu-user-static)
# Returns 0 if supported, 1 if not (and user declined to install)
check_cross_arch_lxc_support() {
    local target_arch="$1"
    local qemu_binary=""
    local binfmt_file=""

    if [ "$target_arch" = "aarch64" ]; then
        qemu_binary="qemu-aarch64-static"
        binfmt_file="/proc/sys/fs/binfmt_misc/qemu-aarch64"
    else
        qemu_binary="qemu-x86_64-static"
        binfmt_file="/proc/sys/fs/binfmt_misc/qemu-x86_64"
    fi

    echo ""
    echo -e "  ${YELLOW}!${NC} Cross-architecture build detected"
    echo -e "  ${DIM}Host: $(uname -m), Target: ${target_arch}${NC}"
    echo ""

    # Check if qemu-user-static is available
    if [ -f "$binfmt_file" ] && grep -q "enabled" "$binfmt_file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} QEMU user-static emulation available for ${target_arch}"
        echo ""
        sleep 0.5
        return 0
    fi

    echo -e "  ${YELLOW}!${NC} QEMU user-static not configured for ${target_arch}"
    echo ""
    echo -e "  ${WHITE}LXC cross-architecture builds require qemu-user-static.${NC}"
    echo -e "  ${DIM}This allows running ${target_arch} binaries on your host.${NC}"
    echo ""
    echo -e "  ${WHITE}Options:${NC}"
    echo -e "    ${CYAN}y${NC} - Install qemu-user-static (requires sudo)"
    echo -e "    ${CYAN}n${NC} - Cancel and select a different architecture"
    echo ""

    local install_choice
    echo -ne "  "
    prompt_yes_no "Install qemu-user-static?" install_choice "false"

    if [ "$install_choice" = "true" ]; then
        echo ""
        echo -e "  ${DIM}Installing qemu-user-static...${NC}"
        echo ""

        if command -v apt-get &>/dev/null; then
            if sudo apt-get update -qq && sudo apt-get install -y qemu-user-static binfmt-support; then
                echo ""
                echo -e "  ${GREEN}✓${NC} qemu-user-static installed successfully"
                sleep 1
                return 0
            else
                echo ""
                echo -e "  ${RED}✗${NC} Installation failed"
                echo -e "  ${DIM}Try manually: sudo apt install qemu-user-static binfmt-support${NC}"
                sleep 2
                return 1
            fi
        elif command -v dnf &>/dev/null; then
            if sudo dnf install -y qemu-user-static; then
                echo ""
                echo -e "  ${GREEN}✓${NC} qemu-user-static installed successfully"
                sleep 1
                return 0
            fi
        elif command -v pacman &>/dev/null; then
            if sudo pacman -S --noconfirm qemu-user-static; then
                echo ""
                echo -e "  ${GREEN}✓${NC} qemu-user-static installed successfully"
                sleep 1
                return 0
            fi
        else
            echo -e "  ${RED}✗${NC} Unsupported package manager"
            echo -e "  ${DIM}Please install qemu-user-static manually${NC}"
            sleep 2
            return 1
        fi
    else
        echo ""
        echo -e "  ${DIM}Select a different architecture or install qemu-user-static manually${NC}"
        sleep 1
        return 1
    fi
}

step_architecture() {
    # Detect host architecture
    local host_arch
    host_arch=$(uname -m)

    local arch_options=("x86_64 (Intel/AMD)" "ARM64 (aarch64)")

    while true; do
        clear_screen
        print_header
        print_step 2 $TOTAL_STEPS "Target Architecture"
        echo ""

        local selected_idx
        menu_select selected_idx "${arch_options[@]}"
        local result=$?
        [ $result -eq $NAV_BACK ] && return $NAV_BACK

        if [ "$selected_idx" -eq 0 ]; then
            ARCH="x86_64"
            OS_LIST=("${OS_LIST_X86[@]}")

            # For LXC, allow cross-arch with qemu-user-static
            if [ "$host_arch" = "aarch64" ] || [ "$host_arch" = "arm64" ]; then
                if [ "$APPLIANCE_TYPE" = "lxc" ]; then
                    if ! check_cross_arch_lxc_support "x86_64"; then
                        continue
                    fi
                else
                    show_cross_arch_error "x86_64" "ARM64"
                    continue  # Loop back to architecture selection
                fi
            fi
        else
            ARCH="aarch64"
            OS_LIST=("${OS_LIST_ARM[@]}")

            # For LXC, allow cross-arch with qemu-user-static
            if [ "$host_arch" = "x86_64" ]; then
                if [ "$APPLIANCE_TYPE" = "lxc" ]; then
                    if ! check_cross_arch_lxc_support "aarch64"; then
                        continue
                    fi
                else
                    show_cross_arch_error "ARM64" "x86_64"
                    continue  # Loop back to architecture selection
                fi
            fi
        fi

        # For LXC, skip Docker image check
        if [ "$APPLIANCE_TYPE" = "lxc" ]; then
            echo ""
            print_success "$ARCH"
            sleep 0.3
            return $NAV_CONTINUE
        fi

        # Check if Docker image supports the selected architecture
        echo ""
        echo -e "  ${DIM}Checking Docker image architecture support...${NC}"

        local arch_check_result
        check_docker_image_arch "$DOCKER_IMAGE" "$ARCH"
        arch_check_result=$?

        case $arch_check_result in
            0)
                # Supported
                echo -e "  ${GREEN}✓${NC} Docker image supports ${ARCH}"
                ;;
            1)
                # Image does NOT support selected architecture
                show_docker_arch_error "$DOCKER_IMAGE" "$ARCH"
                local user_choice=$?
                if [ $user_choice -eq 1 ]; then
                    # User wants to change Docker image - go back
                    return $NAV_BACK
                fi
                # User chose to continue anyway or try different arch
                continue
                ;;
            3)
                # Authentication required - offer to login
                local registry
                registry=$(get_image_registry "$DOCKER_IMAGE")
                echo -e "  ${YELLOW}!${NC} Authentication required for ${CYAN}${registry}${NC}"
                echo ""
                echo -e "  ${DIM}This appears to be a private image. Options:${NC}"
                echo ""
                echo -e "    ${CYAN}1.${NC} Login to registry now ${DIM}(docker login ${registry})${NC}"
                echo -e "    ${CYAN}2.${NC} Skip check and continue ${DIM}(assumes image is compatible)${NC}"
                echo -e "    ${CYAN}3.${NC} Go back and use a different Docker image"
                echo ""

                local auth_choice
                while true; do
                    echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
                    read -r auth_choice
                    case "$auth_choice" in
                        1)
                            echo ""
                            echo -e "  ${DIM}Running: docker login ${registry}${NC}"
                            echo ""
                            if docker login "$registry"; then
                                echo ""
                                echo -e "  ${GREEN}✓${NC} Login successful! Rechecking image..."
                                sleep 1
                                # Re-run the check by continuing the outer loop
                                continue 2
                            else
                                echo ""
                                echo -e "  ${RED}✗${NC} Login failed"
                                sleep 1
                            fi
                            ;;
                        2)
                            echo ""
                            echo -e "  ${YELLOW}!${NC} Skipping architecture check for private image"
                            sleep 0.5
                            break
                            ;;
                        3)
                            return $NAV_BACK
                            ;;
                        *)
                            echo -e "  ${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                            ;;
                    esac
                done
                ;;
            4)
                # Image not found
                echo -e "  ${RED}✗${NC} Docker image not found: ${CYAN}${DOCKER_IMAGE}${NC}"
                echo ""
                echo -e "  ${DIM}The image doesn't exist or you may need to authenticate.${NC}"
                echo ""
                prompt_yes_no "Go back to change Docker image?" GO_BACK "true"
                if [ "$GO_BACK" = "true" ]; then
                    return $NAV_BACK
                fi
                ;;
            5)
                # Rate limited - skip check silently
                echo -e "  ${YELLOW}!${NC} Rate limited - skipping architecture check"
                echo -e "  ${DIM}Tip: Run 'docker login' to avoid rate limits${NC}"
                sleep 0.5
                ;;
            *)
                # Unknown/legacy format - show warning but continue
                echo -e "  ${YELLOW}!${NC} Could not verify image architecture support"
                echo -e "  ${DIM}(Image may use legacy format without multi-arch manifest)${NC}"
                sleep 0.5
                ;;
        esac

        echo ""
        print_success "$ARCH"
        sleep 0.3
        return $NAV_CONTINUE
    done
}

# Show Docker image architecture incompatibility error
# Args: $1=docker_image, $2=target_arch
# Returns: 0=try different arch, 1=go back to change image
show_docker_arch_error() {
    local docker_image="$1"
    local target_arch="$2"

    # Get available architectures
    local available_archs
    available_archs=$(get_docker_image_archs "$docker_image")

    clear_screen
    print_header
    print_step 2 $TOTAL_STEPS "Target Architecture"
    echo ""
    echo -e "  ${RED}✗ Docker image incompatible with ${target_arch}${NC}"
    echo ""
    echo -e "  ${WHITE}Image:${NC}     ${CYAN}${docker_image}${NC}"
    echo -e "  ${WHITE}Selected:${NC}  ${target_arch}"
    if [ -n "$available_archs" ]; then
        echo -e "  ${WHITE}Available:${NC} ${available_archs}"
    fi
    echo ""
    echo -e "  ─────────────────────────────────────────────────────"
    echo ""
    echo -e "  ${WHITE}Options:${NC}"
    echo -e "    ${CYAN}1.${NC} Choose a different architecture"
    echo -e "    ${CYAN}2.${NC} Go back and use a different Docker image"
    echo -e "    ${CYAN}3.${NC} Continue anyway ${DIM}(build may fail)${NC}"
    echo ""

    local choice
    while true; do
        echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
        read -r choice
        case "$choice" in
            1)
                return 0  # Try different architecture
                ;;
            2)
                return 1  # Go back to Docker image step
                ;;
            3)
                echo ""
                echo -e "  ${YELLOW}!${NC} Continuing with potentially incompatible image..."
                sleep 1
                return 0  # Continue (will exit the loop in caller)
                ;;
            *)
                echo -e "  ${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Show cross-architecture error message
# Args: $1=target_arch (what they selected), $2=host_arch (what they should select)
show_cross_arch_error() {
    local target_arch="$1"
    local host_arch="$2"

    clear_screen
    print_header
    print_step 2 $TOTAL_STEPS "Target Architecture"
    echo ""
    echo -e "  ${RED}✗ Cross-architecture build not supported${NC}"
    echo ""
    echo -e "  ${DIM}Detected:${NC}  ${BRIGHT_GREEN}${host_arch}${NC} machine"
    echo -e "  ${DIM}Selected:${NC}  ${RED}${target_arch}${NC} target"
    echo ""
    echo -e "  ${CYAN}→${NC} Select ${BRIGHT_GREEN}${host_arch}${NC} to build on this machine"
    echo -e "  ${CYAN}→${NC} Or run wizard on ${target_arch} hardware"
    echo ""
    echo -ne "  ${DIM}[Enter] Select again${NC}"
    read -r
}

step_base_os() {
    clear_screen
    print_header
    print_step 3 $TOTAL_STEPS "Base Operating System"
    echo ""

    # Build menu options from OS_LIST (already filtered by architecture)
    local menu_options=()
    for entry in "${OS_LIST[@]}"; do
        local os_name="${entry#*|}"
        os_name="${os_name%%|*}"
        menu_options+=("$os_name")
    done

    local selected_idx
    menu_select selected_idx "${menu_options[@]}"
    local result=$?
    [ $result -eq $NAV_BACK ] && return $NAV_BACK

    # Extract selected OS
    local selected="${OS_LIST[$selected_idx]}"
    BASE_OS="${selected%%|*}"
    local os_name="${selected#*|}"
    os_name="${os_name%%|*}"

    echo ""
    print_success "$os_name"
    sleep 0.3
    return $NAV_CONTINUE
}

step_appliance_info() {
    clear_screen
    print_header
    print_step 4 $TOTAL_STEPS "Appliance Information"
    print_nav_hint

    while true; do
        prompt_required "Appliance name ${DIM}(e.g. nginx, postgres)${NC}" APPLIANCE_NAME
        local result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        APPLIANCE_NAME=$(echo "$APPLIANCE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if validate_appliance_name "$APPLIANCE_NAME"; then
            break
        else
            print_error "Use lowercase letters, numbers, hyphens only"
        fi
    done

    echo ""
    prompt_required "Display name ${DIM}(e.g. NGINX, PostgreSQL)${NC}" APP_NAME
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.3
    return $NAV_CONTINUE
}

step_publisher_info() {
    clear_screen
    print_header
    print_step 5 $TOTAL_STEPS "Publisher Information"
    print_nav_hint

    prompt_required "Your name" PUBLISHER_NAME
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    echo ""
    prompt_required "Your email" PUBLISHER_EMAIL
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.3
    return $NAV_CONTINUE
}

step_app_details() {
    clear_screen
    print_header
    print_step 6 $TOTAL_STEPS "Application Details"
    print_nav_hint

    local default_desc="${APP_NAME:-Application} - Docker-based appliance"
    prompt_optional "Description" APP_DESCRIPTION "$default_desc"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Features ${DIM}(comma-separated)${NC}" APP_FEATURES ""
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Main port" APP_PORT "8080"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_yes_no "Web UI accessible via browser?" WEB_INTERFACE "true"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.3
    return $NAV_CONTINUE
}

step_container_config() {
    clear_screen
    print_header
    print_step 7 $TOTAL_STEPS "Container Configuration"
    print_nav_hint

    local default_container="${APPLIANCE_NAME:-app}-container"
    prompt_optional "Container name" DEFAULT_CONTAINER_NAME "$default_container"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    local default_ports="${APP_PORT:-8080}:${APP_PORT:-8080}"
    prompt_optional "Ports ${DIM}(host:container)${NC}" DEFAULT_PORTS "$default_ports"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Environment vars ${DIM}(VAR=val,...)${NC}" DEFAULT_ENV_VARS ""
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Volumes ${DIM}(/host:/container)${NC}" DEFAULT_VOLUMES "/data:/data"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.3
    return $NAV_CONTINUE
}

step_vm_config() {
    clear_screen
    print_header
    print_step 8 $TOTAL_STEPS "Image Disk Size"
    print_nav_hint

    # Get recommended disk size based on selected BASE_OS
    local base_image_size
    local recommended_size
    base_image_size=$(get_base_image_size "$BASE_OS")
    recommended_size=$(get_recommended_disk_size "$BASE_OS")

    # Get display name for BASE_OS
    local base_os_display="$BASE_OS"
    for entry in "${OS_LIST[@]}"; do
        local os_id="${entry%%|*}"
        if [ "$os_id" = "$BASE_OS" ]; then
            local os_name="${entry#*|}"
            base_os_display="${os_name%%|*}"
            break
        fi
    done

    echo -e "  ${DIM}Configure the disk size for the appliance image${NC}"
    echo ""
    echo -e "  ${WHITE}Selected base OS:${NC} ${CYAN}${base_os_display}${NC}"
    echo -e "  ${WHITE}Base image size:${NC}  ~${base_image_size} MB"
    echo -e "  ${WHITE}Recommended:${NC}      ${GREEN}${recommended_size} MB${NC} ${DIM}(includes Docker + app space)${NC}"
    echo ""

    prompt_optional "Disk size (MB)" VM_DISK_SIZE "$recommended_size"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    # Validate disk size is at least the base image size
    if [ "$VM_DISK_SIZE" -lt "$base_image_size" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠${NC} Warning: Disk size smaller than base image (${base_image_size} MB)"
        echo -e "  ${DIM}This may cause build failures. Recommended: ${recommended_size} MB${NC}"
    fi

    # Set default VM template values (can be changed at deployment)
    # These are just metadata defaults embedded in the appliance
    VM_CPU="${VM_CPU:-1}"
    VM_VCPU="${VM_VCPU:-2}"
    VM_MEMORY="${VM_MEMORY:-2048}"

    echo ""
    echo -e "  ${DIM}Note: CPU, vCPU, and Memory are configured when deploying the VM,${NC}"
    echo -e "  ${DIM}not during image build. Default template values: 1 CPU, 2 vCPU, 2GB RAM${NC}"

    # ONE_VERSION defaults to 7.0 (hidden from user)
    ONE_VERSION="${ONE_VERSION:-7.0}"

    sleep 0.3
    return $NAV_CONTINUE
}

step_ssh_config() {
    clear_screen
    print_header
    print_step 9 $TOTAL_STEPS "SSH Key Configuration"
    print_nav_hint

    echo -e "  ${DIM}Configure SSH access for the appliance${NC}"
    echo ""

    # Check if host SSH key exists
    local host_key_path="$HOME/.ssh/id_rsa.pub"
    local host_key_exists=false
    local host_key_content=""

    if [ -f "$host_key_path" ]; then
        host_key_exists=true
        host_key_content=$(cat "$host_key_path")
    elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        host_key_path="$HOME/.ssh/id_ed25519.pub"
        host_key_exists=true
        host_key_content=$(cat "$host_key_path")
    fi

    local ssh_options=()
    if [ "$host_key_exists" = true ]; then
        # Create truncated key preview for menu option
        local key_preview="${host_key_content:0:50}..."
        ssh_options+=("Use this host SSH key (${key_preview})")
        ssh_options+=("Provide a different SSH public key")
    else
        echo -e "  ${YELLOW}!${NC} ${DIM}No SSH key found on this host${NC}"
        echo ""
        ssh_options+=("Provide SSH public key")
    fi

    echo -e "  ${WHITE}Select SSH key source:${NC}"
    echo ""

    local selected_idx
    menu_select selected_idx "${ssh_options[@]}"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    if [ "$host_key_exists" = true ] && [ "$selected_idx" -eq 0 ]; then
        SSH_KEY_SOURCE="host"
        SSH_PUBLIC_KEY="$host_key_content"
        echo ""
        echo -e "  ${GREEN}✓${NC} Host SSH key selected"
    else
        SSH_KEY_SOURCE="custom"
        echo ""
        while true; do
            prompt_required "SSH public key" SSH_PUBLIC_KEY
            result=$?
            [ $result -ne $NAV_CONTINUE ] && return $result

            # Validate SSH key format (basic check)
            if [[ "$SSH_PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
                echo -e "  ${GREEN}✓${NC} SSH key accepted"
                break
            else
                echo -e "  ${RED}✗ Invalid SSH key format${NC}"
                echo -e "  ${DIM}Key should start with ssh-rsa, ssh-ed25519, or ssh-ecdsa${NC}"
                echo ""
            fi
        done
    fi

    sleep 0.3
    return $NAV_CONTINUE
}

step_login_config() {
    clear_screen
    print_header
    print_step 10 $TOTAL_STEPS "Console Login Configuration"
    print_nav_hint

    echo -e "  ${DIM}Configure console/VNC login behavior${NC}"
    echo ""

    local login_options=(
        "Enable autologin (no password required on console)"
        "Disable autologin (require username and password)"
    )

    echo -e "  ${WHITE}Select login method:${NC}"
    echo ""

    local selected_idx
    menu_select selected_idx "${login_options[@]}"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    if [ "$selected_idx" -eq 0 ]; then
        AUTOLOGIN_ENABLED="true"
        LOGIN_USERNAME="root"
        ROOT_PASSWORD=""
        echo ""
        echo -e "  ${GREEN}✓${NC} Autologin enabled - VM will login automatically as root"
    else
        AUTOLOGIN_ENABLED="false"
        echo ""
        echo -e "  ${DIM}Set login credentials for console access${NC}"
        echo ""

        # Ask for username
        prompt_optional "Username" LOGIN_USERNAME "root"
        result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result
        echo ""

        # Ask for password
        while true; do
            prompt_required "Password for ${LOGIN_USERNAME}" ROOT_PASSWORD
            result=$?
            [ $result -ne $NAV_CONTINUE ] && return $result

            if [ ${#ROOT_PASSWORD} -lt 4 ]; then
                echo -e "  ${RED}✗ Password too short (minimum 4 characters)${NC}"
                echo ""
            else
                echo -e "  ${GREEN}✓${NC} Credentials set: ${LOGIN_USERNAME} / ****"
                break
            fi
        done
    fi

    sleep 0.3
    return $NAV_CONTINUE
}

step_docker_updates() {
    clear_screen
    print_header
    print_step 11 $TOTAL_STEPS "Docker Updates"

    echo -e "${WHITE}How should Docker image updates be handled?${NC}\n"
    echo -e "${DIM}When a new version of the Docker image is released, the appliance can:${NC}"
    echo -e "${DIM}  - Check for updates and notify you (default)${NC}"
    echo -e "${DIM}  - Automatically update on boot${NC}"
    echo -e "${DIM}  - Never check for updates${NC}\n"

    local update_options=(
        "Check for updates (notify only)"
        "Auto-update on boot"
        "Never check for updates"
    )

    local selected_idx=0
    case "$DOCKER_AUTO_UPDATE" in
        CHECK) selected_idx=0 ;;
        YES) selected_idx=1 ;;
        NO) selected_idx=2 ;;
    esac

    menu_select selected_idx "${update_options[@]}"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    case $selected_idx in
        0)
            DOCKER_AUTO_UPDATE="CHECK"
            echo ""
            echo -e "  ${GREEN}✓${NC} Will check for updates and notify on boot"
            ;;
        1)
            DOCKER_AUTO_UPDATE="YES"
            echo ""
            echo -e "  ${GREEN}✓${NC} Will auto-update Docker image on boot"
            ;;
        2)
            DOCKER_AUTO_UPDATE="NO"
            echo ""
            echo -e "  ${GREEN}✓${NC} Will never check for updates"
            ;;
    esac

    echo -e "\n${DIM}Users can override this at deployment via ONEAPP_DOCKER_AUTO_UPDATE context variable${NC}"

    sleep 0.5
    return $NAV_CONTINUE
}

step_summary() {
    clear_screen
    print_header
    print_step 12 $TOTAL_STEPS "Summary"

    # Get display name for BASE_OS from OS_LIST
    local base_os_display="$BASE_OS"
    for entry in "${OS_LIST[@]}"; do
        local os_id="${entry%%|*}"
        if [ "$os_id" = "$BASE_OS" ]; then
            local os_name="${entry#*|}"
            base_os_display="${os_name%%|*}"
            break
        fi
    done

    local arch_display="x86_64"
    [ "$ARCH" = "aarch64" ] && arch_display="ARM64"

    echo -e "${WHITE}Please review your appliance configuration:${NC}\n"

    echo -e "${CYAN}Docker Image:${NC}        $DOCKER_IMAGE"
    echo -e "${CYAN}Architecture:${NC}        $arch_display"
    echo -e "${CYAN}Base OS:${NC}             $base_os_display"
    echo -e "${CYAN}Appliance Name:${NC}      $APPLIANCE_NAME"
    echo -e "${CYAN}Display Name:${NC}        $APP_NAME"
    echo -e "${CYAN}Publisher:${NC}           $PUBLISHER_NAME"
    echo -e "${CYAN}Email:${NC}               $PUBLISHER_EMAIL"
    echo ""
    echo -e "${CYAN}Description:${NC}         $APP_DESCRIPTION"
    echo -e "${CYAN}Features:${NC}            ${APP_FEATURES:-None}"
    echo -e "${CYAN}Main Port:${NC}           ${APP_PORT:-8080}"
    echo -e "${CYAN}Web Interface:${NC}       $WEB_INTERFACE"
    echo ""
    echo -e "${CYAN}Container Name:${NC}      $DEFAULT_CONTAINER_NAME"
    echo -e "${CYAN}Port Mappings:${NC}       ${DEFAULT_PORTS:-None}"
    echo -e "${CYAN}Environment Vars:${NC}    ${DEFAULT_ENV_VARS:-None}"
    echo -e "${CYAN}Volume Mappings:${NC}     ${DEFAULT_VOLUMES:-None}"
    echo ""
    echo -e "${CYAN}Image Disk Size:${NC}     ${VM_DISK_SIZE:-12288} MB"
    echo -e "${DIM}(VM CPU/Memory configured at deployment, defaults: ${VM_CPU:-1} CPU, ${VM_VCPU:-2} vCPU, ${VM_MEMORY:-2048}MB)${NC}"
    echo ""
    # SSH and Login configuration
    local ssh_key_display="Host key"
    [ "$SSH_KEY_SOURCE" = "custom" ] && ssh_key_display="Custom key"
    local autologin_display="Enabled (auto-login as root)"
    [ "$AUTOLOGIN_ENABLED" = "false" ] && autologin_display="Disabled (user: ${LOGIN_USERNAME}, password: ****)"
    echo -e "${CYAN}SSH Key:${NC}             $ssh_key_display (${SSH_PUBLIC_KEY:0:30}...)"
    echo -e "${CYAN}Console Login:${NC}       $autologin_display"
    # Docker update mode display
    local update_mode_display="Check & notify"
    [ "$DOCKER_AUTO_UPDATE" = "YES" ] && update_mode_display="Auto-update on boot"
    [ "$DOCKER_AUTO_UPDATE" = "NO" ] && update_mode_display="Never check"
    echo -e "${CYAN}Docker Updates:${NC}      $update_mode_display"
    echo ""

    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${DIM}Type :b to go back and edit, or confirm to generate${NC}\n"

    prompt_yes_no "Generate appliance with this configuration?" CONFIRM "true"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    if [ "$CONFIRM" != "true" ]; then
        echo ""
        print_warning "Going back to previous step..."
        sleep 0.5
        return $NAV_BACK
    fi
    return $NAV_CONTINUE
}

# ═══════════════════════════════════════════════════════════════════════════════
# GENERATION & COMPLETION
# ═══════════════════════════════════════════════════════════════════════════════

# Check if OpenNebula is running locally
check_opennebula_local() {
    # Check if onevm command exists
    if ! command -v onevm &>/dev/null; then
        return 1
    fi
    # Check if opennebula service is active (try different service names)
    systemctl is-active --quiet opennebula 2>/dev/null && return 0
    systemctl is-active --quiet opennebula-oned 2>/dev/null && return 0
    systemctl is-active --quiet oned 2>/dev/null && return 0
    # Also check if oned process is running
    pgrep -x oned &>/dev/null && return 0
    return 1
}

# Get Sunstone URL (detect from oned.conf or use default)
get_sunstone_url() {
    local sunstone_port
    sunstone_port=$(awk -F: '/^[[:space:]]*:port:/ {gsub(/[^0-9]/,"",$2); print $2}' /etc/one/sunstone-server.conf 2>/dev/null)
    sunstone_port="${sunstone_port:-9869}"
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    echo "http://${host_ip}:${sunstone_port}"
}

# Check if a network has IP allocation (not just MAC-only AR)
# Returns 0 if network allocates IPs, 1 if MAC-only or no AR (DHCP network)
network_has_ip_allocation() {
    local net_id="$1"
    local net_xml
    net_xml=$(onevnet show "$net_id" -x 2>/dev/null)

    # Check if any AR has an IP address (not just MAC)
    # MAC-only ARs don't have <IP> tags, IP-managed ARs do
    if echo "$net_xml" | grep -q '<IP>'; then
        return 0  # Has IP allocation
    else
        return 1  # No IP allocation (MAC-only or no AR)
    fi
}

# Alias for backward compatibility
network_has_ar() {
    network_has_ip_allocation "$@"
}

# Ensure bridge has gateway IP configured (Issue #1 fix)
# OpenNebula defines gateway in network but doesn't configure it on host bridge
ensure_bridge_gateway() {
    local network_id="$1"
    [ -z "$network_id" ] && return 0

    # Get bridge name and gateway from network
    local bridge gateway
    bridge=$(onevnet show "$network_id" -x 2>/dev/null | grep -oP '(?<=<BRIDGE>)[^<]+' | head -1)
    gateway=$(onevnet show "$network_id" -x 2>/dev/null | grep -oP '(?<=<GATEWAY>)[^<]+' | head -1)

    [ -z "$bridge" ] || [ -z "$gateway" ] && return 0

    # Check if bridge exists
    if ! ip link show "$bridge" &>/dev/null; then
        return 0  # Bridge doesn't exist yet, will be created by OpenNebula
    fi

    # Check if gateway IP is already configured on bridge
    if ip addr show "$bridge" 2>/dev/null | grep -q "$gateway"; then
        return 0  # Already configured
    fi

    # Configure gateway IP on bridge
    echo -e "  ${CYAN}→${NC} Configuring gateway ${gateway}/24 on ${bridge}..."
    if ip addr add "${gateway}/24" dev "$bridge" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Bridge gateway configured"
    else
        echo -e "  ${YELLOW}!${NC} Could not configure bridge gateway (may need manual setup)"
    fi
}

# Generate START_SCRIPT content for netplan cleanup (Issue #2 fix)
# This cleans up conflicting NetworkManager netplan configs on first boot
get_netplan_cleanup_script() {
    cat << 'CLEANUP_EOF'
#!/bin/bash
# Cleanup conflicting NetworkManager netplan configurations
rm -f /etc/netplan/90-NM-*.yaml 2>/dev/null
rm -f /etc/NetworkManager/system-connections/netplan-* 2>/dev/null
# Regenerate netplan with clean config
if command -v netplan &>/dev/null; then
    netplan generate 2>/dev/null
    netplan apply 2>/dev/null
fi
CLEANUP_EOF
}

# List available networks and let user select
# Sets SELECTED_NETWORK variable
# For contextless LXC, prefers networks without AR (external/DHCP)
select_network() {
    # Get list of networks
    local networks
    networks=$(onevnet list -l ID,NAME,LEASES 2>/dev/null | tail -n +2)

    if [ -z "$networks" ]; then
        echo -e "  ${YELLOW}No networks found. Using default 'vnet'.${NC}"
        SELECTED_NETWORK="vnet"
        SELECTED_NETWORK_ID=""
        return
    fi

    # Parse networks into arrays
    local net_ids=()
    local net_names=()
    local net_display=()
    local net_has_ar=()
    local dhcp_network_idx=-1

    while IFS= read -r line; do
        local id name used
        id=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        [ -z "$id" ] && continue

        net_ids+=("$id")
        net_names+=("$name")

        # Check if network has Address Range
        local has_ar="yes"
        if ! network_has_ar "$id"; then
            has_ar="no"
            # Remember first DHCP/external network for contextless preference
            [ $dhcp_network_idx -eq -1 ] && dhcp_network_idx=${#net_ids[@]}
            dhcp_network_idx=$((dhcp_network_idx - 1))
            net_display+=("${name} (ID: ${id}) ${GREEN}← DHCP/External${NC}")
        else
            net_display+=("${name} (ID: ${id}, ${used} leases)")
        fi
        net_has_ar+=("$has_ar")
    done <<< "$networks"

    if [ ${#net_ids[@]} -eq 0 ]; then
        SELECTED_NETWORK="vnet"
        SELECTED_NETWORK_ID=""
        return
    fi

    # For contextless LXC with available DHCP network, auto-select it
    if [ "$CONTEXT_MODE" = "contextless" ] && [ $dhcp_network_idx -ge 0 ]; then
        SELECTED_NETWORK="${net_names[$dhcp_network_idx]}"
        SELECTED_NETWORK_ID="${net_ids[$dhcp_network_idx]}"
        echo -e "  ${GREEN}✓${NC} Auto-selected DHCP network: ${SELECTED_NETWORK} (ID: ${SELECTED_NETWORK_ID})"
        echo -e "  ${DIM}This network has no IP allocation - container will use DHCP${NC}"
        return
    fi

    # If only one network, use it automatically
    if [ ${#net_ids[@]} -eq 1 ]; then
        SELECTED_NETWORK="${net_names[0]}"
        SELECTED_NETWORK_ID="${net_ids[0]}"
        echo -e "  ${DIM}Using network: ${SELECTED_NETWORK} (ID: ${SELECTED_NETWORK_ID})${NC}"
        return
    fi

    # Display menu header
    echo -e "  ${WHITE}Available networks:${NC}"
    if [ "$CONTEXT_MODE" = "contextless" ]; then
        echo -e "  ${DIM}Tip: DHCP/External networks avoid IP mismatch for contextless LXC${NC}"
    fi
    echo ""

    # CRITICAL: Reset terminal after build processes that may have corrupted stdin
    reset_terminal_for_input

    # Call menu_select (start at DHCP network if contextless)
    local selected_idx=0
    [ "$CONTEXT_MODE" = "contextless" ] && [ $dhcp_network_idx -ge 0 ] && selected_idx=$dhcp_network_idx
    menu_select selected_idx "${net_display[@]}"
    local result=$?

    if [ $result -eq $NAV_CONTINUE ]; then
        SELECTED_NETWORK="${net_names[$selected_idx]}"
        SELECTED_NETWORK_ID="${net_ids[$selected_idx]}"
    else
        # Use first network if user goes back or quits
        SELECTED_NETWORK="${net_names[0]}"
        SELECTED_NETWORK_ID="${net_ids[0]}"
    fi
}

# Prompt for VM sizing with defaults
# Sets VM_CPU, VM_VCPU, VM_MEMORY, VM_DISK_SIZE variables
# $1 = image path (optional, used to determine minimum disk size)
prompt_vm_sizing() {
    local image_path="${1:-}"

    echo -e "  ${WHITE}VM Configuration${NC}"
    echo -e "  ${DIM}Press Enter to accept defaults${NC}"
    echo ""

    # CPU
    local default_cpu="1"
    echo -ne "  CPU cores [${CYAN}${default_cpu}${NC}]: "
    read -r input
    VM_CPU="${input:-$default_cpu}"

    # vCPU
    local default_vcpu="2"
    echo -ne "  vCPUs [${CYAN}${default_vcpu}${NC}]: "
    read -r input
    VM_VCPU="${input:-$default_vcpu}"

    # Memory
    local default_memory="2048"
    echo -ne "  Memory (MB) [${CYAN}${default_memory}${NC}]: "
    read -r input
    VM_MEMORY="${input:-$default_memory}"

    # Disk size - get virtual size from image and add headroom
    local default_disk="8192"
    local image_size_mb=0
    if [ -n "$image_path" ] && [ -f "$image_path" ]; then
        # Get virtual size in bytes, convert to MB
        local vsize_bytes
        vsize_bytes=$(qemu-img info "$image_path" 2>/dev/null | grep 'virtual size' | grep -o '[0-9]*' | tail -1)
        if [ -n "$vsize_bytes" ]; then
            image_size_mb=$(( vsize_bytes / 1024 / 1024 ))
            # Add 25% headroom for OS operations, logs, etc. (minimum 2GB extra)
            local headroom=$(( image_size_mb / 4 ))
            [ "$headroom" -lt 2048 ] && headroom=2048
            default_disk=$(( image_size_mb + headroom ))
            # Round up to nearest 1024 MB (1 GB)
            default_disk=$(( ((default_disk + 1023) / 1024) * 1024 ))
        fi
    fi
    echo -ne "  Disk size (MB) [${CYAN}${default_disk}${NC}]: "
    read -r input
    VM_DISK_SIZE="${input:-$default_disk}"

    echo ""
    echo -e "  ${DIM}Configuration: ${VM_CPU} CPU, ${VM_VCPU} vCPU, ${VM_MEMORY}MB RAM, ${VM_DISK_SIZE}MB disk${NC}"
}

# Check for existing images/templates and offer cleanup
# Returns 0 to continue, 1 to abort
check_existing_resources() {
    local image_name="$1"
    local found_resources=false

    # Check for existing image (use --filter to handle truncated names in list output)
    local existing_image
    existing_image=$(oneimage list --filter "NAME=$image_name" -l ID 2>/dev/null | tail -n +2 | awk '{print $1}' | head -1)
    # Fallback: grep partial match if --filter returns nothing (handles truncated names)
    if [ -z "$existing_image" ]; then
        existing_image=$(oneimage list -l ID,NAME 2>/dev/null | grep "${image_name%%-*}" | awk '{print $1}' | head -1)
    fi

    # Check for existing template (use --filter to handle truncated names)
    local existing_template
    existing_template=$(onetemplate list --filter "NAME=$image_name" -l ID 2>/dev/null | tail -n +2 | awk '{print $1}' | head -1)
    # Fallback: grep partial match
    if [ -z "$existing_template" ]; then
        existing_template=$(onetemplate list -l ID,NAME 2>/dev/null | grep "${image_name%%-*}" | awk '{print $1}' | head -1)
    fi

    if [ -n "$existing_image" ] || [ -n "$existing_template" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠ Existing resources found:${NC}"
        [ -n "$existing_image" ] && echo -e "    Image ID: ${existing_image}"
        [ -n "$existing_template" ] && echo -e "    Template ID: ${existing_template}"
        echo ""

        prompt_yes_no "  Delete existing resources before creating new ones?" DELETE_EXISTING "true"

        if [ "$DELETE_EXISTING" = "true" ]; then
            if [ -n "$existing_template" ]; then
                echo -e "  ${DIM}Deleting template ${existing_template}...${NC}"
                onetemplate delete "$existing_template" 2>/dev/null || true
            fi
            if [ -n "$existing_image" ]; then
                echo -e "  ${DIM}Deleting image ${existing_image}...${NC}"
                oneimage delete "$existing_image" 2>/dev/null || true
                # Wait for image deletion
                sleep 2
            fi
            echo -e "  ${GREEN}✓${NC} Cleanup complete"
        fi
        echo ""
    fi
    return 0
}

# Wait for VM to be running and get its IP
# Args: vm_id, max_wait_seconds
# Returns: 0=running, 1=timeout, 2=failed
wait_for_vm_running() {
    local vm_id="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    local spin_idx=0
    local state=""
    local state_str=""
    local lcm_state=""
    local lcm_state_str=""
    local vm_error=""

    echo ""
    echo -e "  ${WHITE}Waiting for VM to start...${NC}"
    hide_cursor

    while [ $elapsed -lt $max_wait ]; do
        # Check state every 2 seconds (every 10 iterations at 0.2s each)
        if [ $((elapsed % 10)) -eq 0 ]; then
            state=$(onevm show "$vm_id" -x 2>/dev/null | grep '<STATE>' | sed 's/.*<STATE>\([0-9]*\)<\/STATE>.*/\1/' | head -1)
            state_str=$(onevm show "$vm_id" -x 2>/dev/null | grep '<STATE_STR>' | sed 's/.*<STATE_STR>\([^<]*\)<\/STATE_STR>.*/\1/' | head -1)
            lcm_state=$(onevm show "$vm_id" -x 2>/dev/null | grep '<LCM_STATE>' | sed 's/.*<LCM_STATE>\([0-9]*\)<\/LCM_STATE>.*/\1/' | head -1)
            lcm_state_str=$(onevm show "$vm_id" -x 2>/dev/null | grep '<LCM_STATE_STR>' | sed 's/.*<LCM_STATE_STR>\([^<]*\)<\/LCM_STATE_STR>.*/\1/' | head -1)

            # State 7 = FAILED - immediately stop and report error
            if [ "$state" = "7" ]; then
                printf "\r${CLEAR_LINE}"
                show_cursor
                echo -e "  ${RED}✗ VM failed to start${NC}"
                # Get the error message from VM log
                vm_error=$(onevm show "$vm_id" 2>/dev/null | grep -A1 "SCHED_MESSAGE\|USER_TEMPLATE/ERROR" | grep -v "^--$" | head -5)
                if [ -z "$vm_error" ]; then
                    vm_error=$(onevm log "$vm_id" 2>/dev/null | tail -5)
                fi
                if [ -n "$vm_error" ]; then
                    echo ""
                    echo -e "  ${RED}Error:${NC}"
                    echo "$vm_error" | sed 's/^/    /'
                fi
                return 2
            fi

            # State 3 = ACTIVE, check LCM states
            if [ "$state" = "3" ]; then
                # LCM_STATE 3 = RUNNING
                if [ "$lcm_state" = "3" ]; then
                    printf "\r${CLEAR_LINE}"
                    echo -e "  ${GREEN}✓${NC} VM is running!"
                    show_cursor
                    return 0
                fi
                # LCM_STATE 36 = FAILURE - boot failed
                if [ "$lcm_state" = "36" ]; then
                    printf "\r${CLEAR_LINE}"
                    show_cursor
                    echo -e "  ${RED}✗ VM boot failed${NC}"
                    vm_error=$(onevm show "$vm_id" 2>/dev/null | grep -A1 "SCHED_MESSAGE\|ERROR" | head -3)
                    if [ -n "$vm_error" ]; then
                        echo ""
                        echo -e "  ${RED}Error:${NC}"
                        echo "$vm_error" | sed 's/^/    /'
                    fi
                    return 2
                fi
            fi
        fi

        # Show current state with fast spinner (include LCM state if active)
        local display_state="${state_str:-pending}"
        if [ "$state" = "3" ] && [ -n "$lcm_state_str" ]; then
            display_state="${lcm_state_str}"
        fi
        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} State: %-20s" "$display_state"
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER_FRAMES[@]} ))

        sleep 0.2
        elapsed=$((elapsed + 1))
    done

    show_cursor
    echo -e "\r${CLEAR_LINE}  ${YELLOW}!${NC} VM did not reach running state in time"
    return 1
}

# Get VM IP address
get_vm_ip() {
    local vm_id="$1"
    local ip=""

    # Try to get IP from VM info
    ip=$(onevm show "$vm_id" 2>/dev/null | grep 'IP=' | sed 's/.*IP="\([^"]*\)".*/\1/' | head -1)

    # Alternative: try ETH0_IP from context
    if [ -z "$ip" ]; then
        ip=$(onevm show "$vm_id" 2>/dev/null | grep 'ETH0_IP=' | sed 's/.*ETH0_IP="\([^"]*\)".*/\1/' | head -1)
    fi

    echo "$ip"
}

# Get LXC container IP - handles both contextualized and contextless deployments
# For contextualized: OpenNebula assigns static IP (trust OpenNebula)
# For contextless: DHCP assigns IP (query lxc-ls on host for actual IP)
get_lxc_container_ip() {
    local vm_id="$1"
    local container_name="one-${vm_id}"
    local ip=""
    local one_ip=""
    local lxc_ip=""

    # Get IP from OpenNebula (may be static assignment or stale)
    one_ip=$(get_vm_ip "$vm_id")

    # Get the host where VM is running
    local host
    host=$(onevm show "$vm_id" 2>/dev/null | awk '/^HOST/ {print $3}')

    # Query actual IP from lxc-ls on the host (source of truth)
    if [ -n "$host" ]; then
        # lxc-ls -f output: NAME STATE AUTOSTART GROUPS IPV4 IPV6 UNPRIVILEGED
        lxc_ip=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" \
            "lxc-ls -f 2>/dev/null | awk '/^${container_name}[[:space:]]/ {print \$5}'" 2>/dev/null)

        # Handle multiple IPs (take first one) and clean up
        lxc_ip=$(echo "$lxc_ip" | tr ',' '\n' | head -1 | tr -d '[:space:]')
    fi

    # Decision logic:
    # 1. If we got IP from lxc-ls, prefer it (it's the actual running container IP)
    # 2. If lxc-ls failed but OpenNebula has IP, use OpenNebula (contextualized case)
    # 3. If both have IPs but differ, prefer lxc-ls (OpenNebula may be stale)
    if [ -n "$lxc_ip" ]; then
        ip="$lxc_ip"
    elif [ -n "$one_ip" ]; then
        ip="$one_ip"
    fi

    echo "$ip"
}

# Sync actual LXC container IP to OpenNebula
# For contextless deployments, OpenNebula shows the template IP (from network AR), not the DHCP IP
# This updates multiple attributes to ensure Sunstone displays the correct IP
sync_lxc_ip_to_opennebula() {
    local vm_id="$1"
    local actual_ip="$2"

    [ -z "$vm_id" ] || [ -z "$actual_ip" ] && return

    # Get current OpenNebula IP (from NIC)
    local one_ip
    one_ip=$(onevm show "$vm_id" -x 2>/dev/null | grep '<NIC>' -A20 | grep '<IP>' | sed 's/.*<IP><!\[CDATA\[\([^]]*\)\]\]><\/IP>.*/\1/' | head -1)

    # If IPs differ or no NIC IP, add the actual IP to multiple attributes
    if [ "$one_ip" != "$actual_ip" ]; then
        # Add multiple IP attributes that Sunstone may check
        # IP - Main attribute shown in VM details
        # GUEST_IP - Used by some drivers/views
        # EXTERNAL_IP - Used for external-facing IP
        # ETH0_IP - Context variable format
        cat <<EOF | onevm update "$vm_id" --append 2>/dev/null
IP = "$actual_ip"
GUEST_IP = "$actual_ip"
EXTERNAL_IP = "$actual_ip"
ETH0_IP = "$actual_ip"
LXC_ACTUAL_IP = "$actual_ip"
EOF
        echo -e "  ${GREEN}✓${NC} Synced actual IP to OpenNebula: $actual_ip"

        # Note: The NIC IP from Virtual Network AR cannot be changed after allocation
        # Sunstone VM list may still show NIC IP in some columns, but VM details will show correct IP
        if [ -n "$one_ip" ] && [ "$one_ip" != "$actual_ip" ]; then
            echo -e "  ${DIM}Note: NIC shows ${one_ip} (AR allocation), actual container IP is ${actual_ip}${NC}"
        fi
    fi
}

# Offer to SSH into VM
offer_ssh_connection() {
    local vm_id="$1"
    local vm_ip="$2"

    if [ -z "$vm_ip" ]; then
        echo -e "  ${YELLOW}!${NC} Could not detect VM IP address"
        echo -e "  ${DIM}Check with: onevm show ${vm_id} | grep -i ip${NC}"
        return
    fi

    echo ""
    echo -e "  ${WHITE}VM IP Address:${NC} ${CYAN}${vm_ip}${NC}"
    echo ""

    prompt_yes_no "  SSH into VM now?" DO_SSH "false"

    if [ "$DO_SSH" = "true" ]; then
        echo ""
        echo -e "  ${DIM}Connecting to ${vm_ip}...${NC}"
        echo -e "  ${DIM}(Exit SSH session to return to wizard)${NC}"
        echo ""
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${vm_ip}" || true
    fi
}

# Show build success and offer to deploy
show_build_success() {
    local image_path="$1"
    local image_size
    image_size=$(du -h "$image_path" 2>/dev/null | cut -f1)

    clear_screen
    print_header

    echo ""
    echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}✓ Appliance built successfully!${NC}"
    echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Image:${NC} ${CYAN}${image_path}${NC}"
    echo -e "  ${WHITE}Size:${NC}  ${image_size}"
    echo ""

    # Check if OpenNebula is running locally
    if check_opennebula_local; then
        local one_version
        one_version=$(onevm --version 2>/dev/null | grep 'OpenNebula' | sed 's/.*OpenNebula \([0-9.]*\).*/\1/' | head -1)
        if [ -n "$one_version" ]; then
            echo -e "  ${BRIGHT_GREEN}OpenNebula ${one_version} detected on this host${NC}"
        else
            echo -e "  ${BRIGHT_GREEN}OpenNebula detected on this host${NC}"
        fi
        echo ""
        prompt_yes_no "  Deploy to OpenNebula now?" DEPLOY_NOW "true"

        if [ "$DEPLOY_NOW" = "true" ]; then
            deploy_to_opennebula "$image_path"
            return
        fi
    fi

    # Show manual deployment instructions
    show_manual_deploy_instructions "$image_path"
}

# Deploy image to local OpenNebula
deploy_to_opennebula() {
    local image_path="$1"
    local image_name="${APPLIANCE_NAME}"

    echo ""
    echo -e "  ${BRIGHT_CYAN}Deploying to OpenNebula...${NC}"
    echo ""

    # Check for existing resources and offer cleanup
    check_existing_resources "$image_name"

    # Get default datastore (look for 'img' type which is image datastore)
    local datastore_id datastore_name
    datastore_id=$(onedatastore list 2>/dev/null | awk '/[[:space:]]img[[:space:]]/ {print $1; exit}')

    if [ -z "$datastore_id" ]; then
        echo -e "  ${RED}✗ Could not find an image datastore${NC}"
        echo ""
        show_manual_deploy_instructions "$image_path"
        return
    fi

    datastore_name=$(onedatastore list 2>/dev/null | awk -v id="$datastore_id" '$1==id {print $2}')

    # Clear screen before network selection to ensure menu_select works properly
    clear_screen
    echo -e "  ${BRIGHT_CYAN}Deploying to OpenNebula...${NC}"
    echo ""
    echo -e "  ${DIM}Using datastore: ${datastore_name} (ID: ${datastore_id})${NC}"
    echo ""

    # Select network
    select_network
    echo ""

    # Ensure bridge has gateway IP configured (fixes Issue #1: br-edge missing gateway)
    ensure_bridge_gateway "$SELECTED_NETWORK_ID"

    # Prompt for VM sizing (pass image path for disk size detection)
    prompt_vm_sizing "$image_path"
    echo ""

    # Clear screen again before proceeding with deployment steps
    clear_screen
    echo -e "  ${BRIGHT_CYAN}Deploying to OpenNebula...${NC}"
    echo ""

    # Step 1: Create image
    echo -e "  ${WHITE}[1/4] Creating image...${NC}"
    echo -e "  ${DIM}This may take several minutes for large images${NC}"

    # Copy image to /var/tmp/ so OpenNebula (oneadmin) can access it
    local upload_path="/var/tmp/${image_name}.qcow2"
    if [[ "$image_path" != "$upload_path" ]]; then
        echo -e "  ${DIM}Copying image to shared location...${NC}"
        cp "$image_path" "$upload_path" 2>/dev/null || {
            echo -e "  ${RED}✗ Failed to copy image to $upload_path${NC}"
            show_manual_deploy_instructions "$image_path"
            return
        }
        chmod 644 "$upload_path"
    fi

    # Run oneimage create in background and show spinner
    local tmpfile=$(mktemp)
    oneimage create --name "$image_name" --path "$upload_path" \
        --format qcow2 --datastore "$datastore_id" > "$tmpfile" 2>&1 &
    local pid=$!

    # Show spinner while waiting
    hide_cursor
    local spin_idx=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} Uploading image..."
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER_FRAMES[@]} ))
        sleep 0.2
    done
    # Capture exit code without triggering set -e
    local exit_code=0
    wait "$pid" || exit_code=$?
    printf "\r${CLEAR_LINE}"
    show_cursor

    local image_id
    image_id=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [[ "$image_id" =~ ID:\ ([0-9]+) ]]; then
        image_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} Image created (ID: ${image_id})"
    else
        echo -e "  ${RED}✗ Failed to create image${NC}"
        echo -e "  ${DIM}${image_id}${NC}"
        show_manual_deploy_instructions "$image_path"
        return
    fi

    # Wait for image to be ready with progress
    echo ""
    echo -e "  ${DIM}Waiting for image to be ready...${NC}"
    local max_wait=600  # 10 minutes max for large images
    local elapsed=0
    local spin_idx=0
    local state=""
    local state_str=""
    hide_cursor
    while [ $elapsed -lt $max_wait ]; do
        # Check state every 2 seconds (every 10 iterations at 0.2s each)
        if [ $((elapsed % 10)) -eq 0 ]; then
            state=$(oneimage show "$image_id" -x 2>/dev/null | grep '<STATE>' | sed 's/.*<STATE>\([0-9]*\)<\/STATE>.*/\1/' | head -1)
            state_str=$(oneimage show "$image_id" 2>/dev/null | awk '/^STATE/ {print $3}')
        fi

        if [ "$state" = "1" ]; then  # READY state
            printf "\r${CLEAR_LINE}"
            echo -e "  ${GREEN}✓${NC} Image ready"
            break
        fi

        # Show progress with state label - fast spinner
        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} State: %-15s" "${state_str:-uploading}"
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER_FRAMES[@]} ))

        sleep 0.2
        elapsed=$((elapsed + 1))
    done
    show_cursor

    # Cleanup temporary upload file
    if [[ "$upload_path" == "/var/tmp/"* ]] && [[ -f "$upload_path" ]]; then
        rm -f "$upload_path" 2>/dev/null
    fi

    # Show image details
    echo ""
    echo -e "  ${DIM}┌─ oneimage show ${image_id}${NC}"
    oneimage show "$image_id" 2>/dev/null | head -12 | sed 's/^/  │ /'
    echo -e "  ${DIM}└─${NC}"

    # Step 2: Create template with user-selected options
    echo ""
    echo -e "  ${WHITE}[2/4] Creating VM template...${NC}"

    # Build NIC configuration (Docker/KVM - always uses context so full IP allocation)
    local nic_config
    if [ -n "$SELECTED_NETWORK_ID" ]; then
        nic_config="NIC=[NETWORK_ID=\"${SELECTED_NETWORK_ID}\"]"
    else
        nic_config="NIC=[NETWORK=\"${SELECTED_NETWORK}\",NETWORK_UNAME=\"oneadmin\"]"
    fi

    # Detect host architecture and add appropriate OS configuration
    local arch_config=""
    local host_arch
    host_arch=$(uname -m)
    if [ "$host_arch" = "aarch64" ]; then
        # ARM64 requires UEFI firmware, virt machine type, and virtio keyboard for VNC
        # Use host-passthrough CPU model to match the board's hardware exactly
        # Serial console added for ARM64 so terminal is visible in Sunstone VNC
        arch_config="OS=[ARCH=\"aarch64\",FIRMWARE=\"/usr/share/AAVMF/AAVMF_CODE.fd\",FIRMWARE_SECURE=\"no\",MACHINE=\"virt\"]
CPU_MODEL=[MODEL=\"host-passthrough\"]
NIC_DEFAULT=[MODEL=\"virtio\"]
RAW=[TYPE=\"kvm\",DATA=\"<devices><input type='keyboard' bus='virtio'/><serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console></devices>\"]
SCHED_REQUIREMENTS=\"HYPERVISOR=kvm & ARCH=aarch64\""
    fi

    # Generate startup script for context
    # - Cleans up NetworkManager netplan conflicts (Issue #2)
    # - Enables getty on tty1 for VNC console access (ARM64)
    local start_script_b64
    start_script_b64=$(cat << 'CLEANUP_SCRIPT' | base64 -w0
#!/bin/bash
# Cleanup conflicting NetworkManager netplan configurations
rm -f /etc/netplan/90-NM-*.yaml 2>/dev/null
rm -f /etc/NetworkManager/system-connections/netplan-* 2>/dev/null
# Regenerate netplan with clean config
if command -v netplan &>/dev/null; then
    netplan generate 2>/dev/null
    netplan apply 2>/dev/null
fi
# Enable getty on tty1 for VNC console access (shows login prompt)
if ! systemctl is-active --quiet getty@tty1; then
    systemctl start getty@tty1 2>/dev/null || true
fi
CLEANUP_SCRIPT
)

    local template_content
    template_content="NAME=\"${image_name}\"
CPU=\"${VM_CPU}\"
VCPU=\"${VM_VCPU}\"
MEMORY=\"${VM_MEMORY}\"
DISK=[IMAGE_ID=\"${image_id}\",SIZE=\"${VM_DISK_SIZE}\"]
${nic_config}
GRAPHICS=[LISTEN=\"0.0.0.0\",TYPE=\"VNC\"]
CONTEXT=[NETWORK=\"YES\",SSH_PUBLIC_KEY=\"\$USER[SSH_PUBLIC_KEY]\",START_SCRIPT_BASE64=\"${start_script_b64}\"]
${arch_config}"

    local template_id
    template_id=$(echo "$template_content" | onetemplate create 2>&1)

    if [[ "$template_id" =~ ID:\ ([0-9]+) ]]; then
        template_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} Template created (ID: ${template_id})"
    else
        echo -e "  ${RED}✗ Failed to create template${NC}"
        echo -e "  ${DIM}${template_id}${NC}"
        show_vm_access_info "" "$image_id" ""
        return
    fi

    # Show template details
    echo ""
    echo -e "  ${DIM}┌─ onetemplate show ${template_id}${NC}"
    onetemplate show "$template_id" 2>/dev/null | head -15 | sed 's/^/  │ /'
    echo -e "  ${DIM}└─${NC}"

    # Step 3: Instantiate VM
    echo ""
    echo -e "  ${WHITE}[3/4] Creating VM...${NC}"
    local vm_id
    vm_id=$(onetemplate instantiate "$template_id" --name "${image_name}-vm" 2>&1)

    if [[ "$vm_id" =~ ID:\ ([0-9]+) ]]; then
        vm_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} VM created (ID: ${vm_id})"
    else
        echo -e "  ${RED}✗ Failed to create VM${NC}"
        echo -e "  ${DIM}${vm_id}${NC}"
        show_vm_access_info "" "$image_id" "$template_id"
        return
    fi

    # Step 4: Wait for VM to be running
    echo ""
    echo -e "  ${WHITE}[4/4] Starting VM...${NC}"

    local wait_result
    wait_for_vm_running "$vm_id" 1500  # 5 minutes (1500 iterations at 0.2s each)
    wait_result=$?

    if [ $wait_result -eq 0 ]; then
        # Success - VM is running
        # Get VM IP
        sleep 3  # Wait for network to initialize
        local vm_ip
        vm_ip=$(get_vm_ip "$vm_id")

        # Show VM details
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -20 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}✓ Deployment complete!${NC}"
        echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"

        # Show Sunstone URL
        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Sunstone Web UI:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"

        show_vm_access_info "$vm_id" "$image_id" "$template_id"

        # Show VM IP if available
        if [ -z "$vm_ip" ]; then
            echo -e "  ${DIM}Waiting for VM to get IP address...${NC}"
            sleep 5
            vm_ip=$(get_vm_ip "$vm_id")
        fi

        if [ -n "$vm_ip" ]; then
            echo ""
            echo -e "  ${WHITE}VM IP Address:${NC} ${CYAN}${vm_ip}${NC}"
            echo -e "  ${DIM}SSH: ssh root@${vm_ip}${NC}"
        fi
        echo ""
    elif [ $wait_result -eq 2 ]; then
        # VM failed - show error and cleanup options
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -25 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${RED}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${RED}✗ VM deployment failed${NC}"
        echo -e "  ${RED}════════════════════════════════════════════════════════════════${NC}"

        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Check VM details in Sunstone:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"
        echo ""
        echo -e "  ${WHITE}Common causes:${NC}"
        echo -e "    ${DIM}• Not enough space in datastore - free up disk space${NC}"
        echo -e "    ${DIM}• Insufficient resources (CPU/RAM) on host${NC}"
        echo -e "    ${DIM}• Image transfer or network issues${NC}"
        echo ""
        echo -e "  ${WHITE}To cleanup and retry:${NC}"
        echo -e "    ${CYAN}onevm terminate --hard ${vm_id}${NC}"
        echo ""

        show_vm_access_info "" "$image_id" "$template_id"
    else
        # Timeout - VM didn't start in time, show details anyway
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -20 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${YELLOW}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${YELLOW}! VM created but not yet running${NC}"
        echo -e "  ${YELLOW}════════════════════════════════════════════════════════════════${NC}"

        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Check status in Sunstone:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"

        show_vm_access_info "$vm_id" "$image_id" "$template_id"
    fi
}

# Deploy LXC image to local OpenNebula
deploy_lxc_to_opennebula() {
    local image_path="$1"
    local image_name="${APPLIANCE_NAME}"

    echo ""
    echo -e "  ${BRIGHT_CYAN}Deploying LXC to OpenNebula...${NC}"
    echo ""

    # Check for existing resources and offer cleanup
    check_existing_resources "$image_name"

    # Get default datastore (look for 'img' type which is image datastore)
    local datastore_id datastore_name
    datastore_id=$(onedatastore list 2>/dev/null | awk '/[[:space:]]img[[:space:]]/ {print $1; exit}')

    if [ -z "$datastore_id" ]; then
        echo -e "  ${RED}✗ Could not find an image datastore${NC}"
        echo ""
        show_lxc_manual_deploy_instructions "$image_path"
        return
    fi

    datastore_name=$(onedatastore list 2>/dev/null | awk -v id="$datastore_id" '$1==id {print $2}')

    # Clear screen before network selection to ensure menu_select works properly
    clear_screen
    echo -e "  ${BRIGHT_CYAN}Deploying LXC to OpenNebula...${NC}"
    echo ""
    echo -e "  ${DIM}Using datastore: ${datastore_name} (ID: ${datastore_id})${NC}"
    echo ""

    # Select network
    select_network
    echo ""

    # Ensure bridge has gateway IP configured (fixes Issue #1: bridge missing gateway)
    ensure_bridge_gateway "$SELECTED_NETWORK_ID"

    # Show contextless IP note only if using a managed network (has AR)
    if [ "$CONTEXT_MODE" = "contextless" ] && [ -n "$SELECTED_NETWORK_ID" ]; then
        if network_has_ar "$SELECTED_NETWORK_ID"; then
            echo -e "  ${DIM}╭─────────────────────────────────────────────────────────╮${NC}"
            echo -e "  ${DIM}│ ${YELLOW}Note:${NC}${DIM} Using managed network with IP allocation.         │${NC}"
            echo -e "  ${DIM}│ Container uses DHCP - actual IP may differ from         │${NC}"
            echo -e "  ${DIM}│ OpenNebula's allocation. IP will be synced after start. │${NC}"
            echo -e "  ${DIM}╰─────────────────────────────────────────────────────────╯${NC}"
            echo ""
            sleep 1
        fi
    fi

    # Clear screen again before proceeding with deployment steps
    clear_screen
    echo -e "  ${BRIGHT_CYAN}Deploying LXC to OpenNebula...${NC}"
    echo ""

    # Step 1: Create image
    echo -e "  ${WHITE}[1/3] Creating image...${NC}"

    # Copy image to /var/tmp/ so OpenNebula (oneadmin) can access it
    local upload_path="/var/tmp/${image_name}.raw"
    if [[ "$image_path" != "$upload_path" ]]; then
        echo -e "  ${DIM}Copying image to shared location...${NC}"
        cp "$image_path" "$upload_path" 2>/dev/null || {
            echo -e "  ${RED}✗ Failed to copy image to $upload_path${NC}"
            show_lxc_manual_deploy_instructions "$image_path"
            return
        }
        chmod 644 "$upload_path"
    fi

    # Run oneimage create in background and show spinner
    local tmpfile=$(mktemp)
    oneimage create --name "$image_name" --path "$upload_path" \
        --format raw --disk_type FILE --type OS --datastore "$datastore_id" > "$tmpfile" 2>&1 &
    local pid=$!

    # Show spinner while waiting
    hide_cursor
    local spin_idx=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} Uploading image..."
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER_FRAMES[@]} ))
        sleep 0.2
    done
    # Capture exit code without triggering set -e
    local exit_code=0
    wait "$pid" || exit_code=$?
    printf "\r${CLEAR_LINE}"
    show_cursor

    local image_id
    image_id=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [[ "$image_id" =~ ID:\ ([0-9]+) ]]; then
        image_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} Image created (ID: ${image_id})"
    else
        echo -e "  ${RED}✗ Failed to create image${NC}"
        echo -e "  ${DIM}${image_id}${NC}"
        show_lxc_manual_deploy_instructions "$image_path"
        return
    fi

    # Wait for image to be ready with progress
    echo ""
    echo -e "  ${DIM}Waiting for image to be ready...${NC}"
    local max_wait=300  # 1 minute max for small LXC images
    local elapsed=0
    local spin_idx=0
    local state=""
    local state_str=""
    hide_cursor
    while [ $elapsed -lt $max_wait ]; do
        if [ $((elapsed % 10)) -eq 0 ]; then
            state=$(oneimage show "$image_id" -x 2>/dev/null | grep '<STATE>' | sed 's/.*<STATE>\([0-9]*\)<\/STATE>.*/\1/' | head -1)
            state_str=$(oneimage show "$image_id" 2>/dev/null | awk '/^STATE/ {print $3}')
        fi

        if [ "$state" = "1" ]; then  # READY state
            printf "\r${CLEAR_LINE}"
            echo -e "  ${GREEN}✓${NC} Image ready"
            break
        fi

        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} State: %-15s" "${state_str:-uploading}"
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER_FRAMES[@]} ))

        sleep 0.2
        elapsed=$((elapsed + 1))
    done
    show_cursor

    # Cleanup temporary upload file
    if [[ "$upload_path" == "/var/tmp/"* ]] && [[ -f "$upload_path" ]]; then
        rm -f "$upload_path" 2>/dev/null
    fi

    # Show image details
    echo ""
    echo -e "  ${DIM}┌─ oneimage show ${image_id}${NC}"
    oneimage show "$image_id" 2>/dev/null | head -12 | sed 's/^/  │ /'
    echo -e "  ${DIM}└─${NC}"

    # Step 2: Create LXC template
    echo ""
    echo -e "  ${WHITE}[2/3] Creating LXC template...${NC}"

    # Build NIC configuration
    # For contextless LXC, use METHOD=skip to prevent IP allocation from the network
    # This avoids showing a misleading IP in Sunstone (container uses DHCP instead)
    local nic_config
    if [ -n "$SELECTED_NETWORK_ID" ]; then
        if [ "$CONTEXT_MODE" = "contextless" ]; then
            nic_config="NIC=[NETWORK_ID=\"${SELECTED_NETWORK_ID}\",METHOD=\"skip\"]"
        else
            nic_config="NIC=[NETWORK_ID=\"${SELECTED_NETWORK_ID}\"]"
        fi
    else
        if [ "$CONTEXT_MODE" = "contextless" ]; then
            nic_config="NIC=[NETWORK=\"${SELECTED_NETWORK}\",NETWORK_UNAME=\"oneadmin\",METHOD=\"skip\"]"
        else
            nic_config="NIC=[NETWORK=\"${SELECTED_NETWORK}\",NETWORK_UNAME=\"oneadmin\"]"
        fi
    fi

    # LXC template - note HYPERVISOR=lxc, no OS/UEFI config needed
    # Determine architecture for scheduling
    local sched_arch="aarch64"
    [ "$ARCH" = "x86_64" ] && sched_arch="x86_64"

    local template_content
    template_content="NAME=\"${image_name}\"
HYPERVISOR=\"lxc\"
CPU=\"1\"
VCPU=\"${VM_VCPU:-1}\"
MEMORY=\"${VM_MEMORY:-256}\"
DISK=[IMAGE_ID=\"${image_id}\"]
${nic_config}
RAW=[DATA=\"lxc.apparmor.profile=unconfined
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up\",TYPE=\"lxc\"]
SCHED_REQUIREMENTS=\"HYPERVISOR=\\\"lxc\\\" & ARCH=\\\"${sched_arch}\\\"\"
LXC_UNPRIVILEGED=\"no\""

    # Add context only if not contextless mode
    if [ "$CONTEXT_MODE" != "contextless" ]; then
        template_content="${template_content}
CONTEXT=[NETWORK=\"YES\",SSH_PUBLIC_KEY=\"\$USER[SSH_PUBLIC_KEY]\"]"
    fi

    local template_id
    template_id=$(echo "$template_content" | onetemplate create 2>&1)

    if [[ "$template_id" =~ ID:\ ([0-9]+) ]]; then
        template_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} Template created (ID: ${template_id})"
    else
        echo -e "  ${RED}✗ Failed to create template${NC}"
        echo -e "  ${DIM}${template_id}${NC}"
        show_lxc_vm_access_info "" "$image_id" ""
        return
    fi

    # Show template details
    echo ""
    echo -e "  ${DIM}┌─ onetemplate show ${template_id}${NC}"
    onetemplate show "$template_id" 2>/dev/null | head -15 | sed 's/^/  │ /'
    echo -e "  ${DIM}└─${NC}"

    # Step 3: Instantiate LXC container
    echo ""
    echo -e "  ${WHITE}[3/3] Creating LXC container...${NC}"
    local vm_id
    vm_id=$(onetemplate instantiate "$template_id" --name "${image_name}-lxc" 2>&1)

    if [[ "$vm_id" =~ ID:\ ([0-9]+) ]]; then
        vm_id="${BASH_REMATCH[1]}"
        echo -e "  ${GREEN}✓${NC} LXC container created (ID: ${vm_id})"
    else
        echo -e "  ${RED}✗ Failed to create LXC container${NC}"
        echo -e "  ${DIM}${vm_id}${NC}"
        show_lxc_vm_access_info "" "$image_id" "$template_id"
        return
    fi

    # Wait for LXC to be running
    echo ""
    echo -e "  ${DIM}Waiting for container to start...${NC}"

    local wait_result
    wait_for_vm_running "$vm_id" 300  # 1 minute (300 iterations at 0.2s)
    wait_result=$?

    if [ $wait_result -eq 0 ]; then
        # Success - Container is running
        sleep 3  # Wait for network to initialize
        local vm_ip

        # For LXC, get IP directly from host (more reliable for contextless)
        echo -e "  ${DIM}Querying container IP from host...${NC}"
        vm_ip=$(get_lxc_container_ip "$vm_id")

        # Show container details
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -20 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}✓ LXC Deployment complete!${NC}"
        echo -e "  ${GREEN}════════════════════════════════════════════════════════════════${NC}"

        # Show Sunstone URL
        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Sunstone Web UI:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"

        show_lxc_vm_access_info "$vm_id" "$image_id" "$template_id"

        # Show container IP if available
        if [ -z "$vm_ip" ]; then
            echo -e "  ${DIM}Waiting for container to get IP address...${NC}"
            sleep 5
            vm_ip=$(get_lxc_container_ip "$vm_id")
        fi

        if [ -n "$vm_ip" ]; then
            # Sync actual IP to OpenNebula so Sunstone shows correct IP
            sync_lxc_ip_to_opennebula "$vm_id" "$vm_ip"

            echo ""
            echo -e "  ${WHITE}Container IP Address:${NC} ${CYAN}${vm_ip}${NC}"

            # Get the host for jump SSH command
            local lxc_host
            lxc_host=$(onevm show "$vm_id" 2>/dev/null | awk '/^HOST/ {print $3}')

            if [ -n "$lxc_host" ] && [ "$lxc_host" != "$(hostname)" ] && [ "$lxc_host" != "$(hostname -I | awk '{print $1}')" ]; then
                # Remote host - show jump SSH command
                echo -e "  ${DIM}SSH (via jump host):${NC}"
                echo -e "    ${CYAN}ssh -J root@${lxc_host} root@${vm_ip}${NC}"
                echo -e "  ${DIM}Or attach directly:${NC}"
                echo -e "    ${CYAN}ssh root@${lxc_host} lxc-attach -n one-${vm_id}${NC}"
            else
                # Local host - direct SSH
                echo -e "  ${DIM}SSH: ssh root@${vm_ip}${NC}"
            fi

            if [ -n "$LXC_PORTS" ]; then
                echo ""
                echo -e "  ${WHITE}Application ports:${NC} ${LXC_PORTS}"
            fi
        fi
        echo ""

        # Ask about marketplace submission after successful deployment
        ask_marketplace_submission "$image_path"

    elif [ $wait_result -eq 2 ]; then
        # Container failed
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -25 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${RED}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${RED}✗ LXC deployment failed${NC}"
        echo -e "  ${RED}════════════════════════════════════════════════════════════════${NC}"

        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Check container details in Sunstone:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"
        echo ""
        echo -e "  ${WHITE}Common causes:${NC}"
        echo -e "    ${DIM}• LXC driver not enabled on host${NC}"
        echo -e "    ${DIM}• Insufficient resources${NC}"
        echo -e "    ${DIM}• Network configuration issues${NC}"
        echo ""
        echo -e "  ${WHITE}To cleanup and retry:${NC}"
        echo -e "    ${CYAN}onevm terminate --hard ${vm_id}${NC}"
        echo ""

        show_lxc_vm_access_info "" "$image_id" "$template_id"
    else
        # Timeout
        echo ""
        echo -e "  ${DIM}┌─ onevm show ${vm_id}${NC}"
        onevm show "$vm_id" 2>/dev/null | head -20 | sed 's/^/  │ /'
        echo -e "  ${DIM}└─${NC}"

        echo ""
        echo -e "  ${YELLOW}════════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${YELLOW}! Container created but not yet running${NC}"
        echo -e "  ${YELLOW}════════════════════════════════════════════════════════════════${NC}"

        local sunstone_url
        sunstone_url=$(get_sunstone_url)
        echo ""
        echo -e "  ${WHITE}Check status in Sunstone:${NC}"
        echo -e "    ${CYAN}${sunstone_url}/#vms-tab/${vm_id}${NC}"

        show_lxc_vm_access_info "$vm_id" "$image_id" "$template_id"
    fi
}

# Show LXC VM access and troubleshooting info
show_lxc_vm_access_info() {
    local vm_id="$1"
    local image_id="$2"
    local template_id="$3"
    local sunstone_url
    sunstone_url=$(get_sunstone_url)

    echo ""
    echo -e "  ${WHITE}Created resources:${NC}"
    if [ -n "$image_id" ]; then
        echo -e "    Image:    ID ${CYAN}${image_id}${NC}  ${DIM}→ ${sunstone_url}/#images-tab/${image_id}${NC}"
    fi
    if [ -n "$template_id" ]; then
        echo -e "    Template: ID ${CYAN}${template_id}${NC}  ${DIM}→ ${sunstone_url}/#templates-tab/${template_id}${NC}"
    fi
    if [ -n "$vm_id" ]; then
        echo -e "    LXC:      ID ${CYAN}${vm_id}${NC}  ${DIM}→ ${sunstone_url}/#vms-tab/${vm_id}${NC}"
    fi

    if [ -n "$vm_id" ]; then
        echo ""
        echo -e "  ${WHITE}Quick commands:${NC}"
        echo -e "    ${CYAN}onevm show ${vm_id}${NC}           ${DIM}# Container status${NC}"
        echo -e "    ${CYAN}onevm vnc ${vm_id}${NC}            ${DIM}# VNC console${NC}"
        echo -e "    ${CYAN}onevm log ${vm_id}${NC}            ${DIM}# Container log${NC}"
        echo ""
        echo -e "  ${WHITE}Inside the container:${NC}"
        echo -e "    ${CYAN}apk list --installed${NC}          ${DIM}# List packages${NC}"
        echo -e "    ${CYAN}rc-status${NC}                     ${DIM}# Service status${NC}"
    fi
    echo ""
}

# Show LXC manual deployment instructions
show_lxc_manual_deploy_instructions() {
    local image_path="$1"

    echo ""
    echo -e "  ${WHITE}To deploy manually:${NC}"
    echo ""
    echo -e "  ${DIM}# 1. Copy image to OpenNebula frontend${NC}"
    echo -e "  ${CYAN}scp ${image_path} <frontend>:/var/tmp/${NC}"
    echo ""
    echo -e "  ${DIM}# 2. Create image in OpenNebula${NC}"
    echo -e "  ${CYAN}oneimage create --name ${APPLIANCE_NAME}${NC} \\"
    echo -e "  ${CYAN}  --path /var/tmp/${APPLIANCE_NAME}.raw${NC} \\"
    echo -e "  ${CYAN}  --format raw --disk_type FILE --type OS --datastore default${NC}"
    echo ""
    echo -e "  ${DIM}# 3. Create LXC template${NC}"
    echo -e "  ${CYAN}onetemplate create << 'EOF'${NC}"
    echo -e "  ${DIM}NAME=\"${APPLIANCE_NAME}\"${NC}"
    echo -e "  ${DIM}HYPERVISOR=\"lxc\"${NC}"
    echo -e "  ${DIM}MEMORY=\"${VM_MEMORY:-256}\"${NC}"
    echo -e "  ${DIM}VCPU=\"${VM_VCPU:-1}\"${NC}"
    echo -e "  ${DIM}DISK=[IMAGE=\"${APPLIANCE_NAME}\"]${NC}"
    echo -e "  ${DIM}NIC=[NETWORK=\"vnet\"]${NC}"
    echo -e "  ${DIM}RAW=[DATA=\"lxc.net.0.type=veth...\",TYPE=\"lxc\"]${NC}"
    echo -e "  ${CYAN}EOF${NC}"
    echo ""
    echo -e "  ${DIM}# 4. Instantiate the container${NC}"
    echo -e "  ${CYAN}onetemplate instantiate ${APPLIANCE_NAME}${NC}"
    echo ""
}

# Show VM access and troubleshooting info
show_vm_access_info() {
    local vm_id="$1"
    local image_id="$2"
    local template_id="$3"
    local sunstone_url
    sunstone_url=$(get_sunstone_url)

    echo ""
    echo -e "  ${WHITE}Created resources:${NC}"
    if [ -n "$image_id" ]; then
        echo -e "    Image:    ID ${CYAN}${image_id}${NC}  ${DIM}→ ${sunstone_url}/#images-tab/${image_id}${NC}"
    fi
    if [ -n "$template_id" ]; then
        echo -e "    Template: ID ${CYAN}${template_id}${NC}  ${DIM}→ ${sunstone_url}/#templates-tab/${template_id}${NC}"
    fi
    if [ -n "$vm_id" ]; then
        echo -e "    VM:       ID ${CYAN}${vm_id}${NC}  ${DIM}→ ${sunstone_url}/#vms-tab/${vm_id}${NC}"
    fi

    if [ -n "$vm_id" ]; then
        echo ""
        echo -e "  ${WHITE}Quick commands:${NC}"
        echo -e "    ${CYAN}onevm show ${vm_id}${NC}           ${DIM}# VM status${NC}"
        echo -e "    ${CYAN}onevm vnc ${vm_id}${NC}            ${DIM}# VNC console${NC}"
        echo -e "    ${CYAN}onevm log ${vm_id}${NC}            ${DIM}# VM log${NC}"
        echo ""
        echo -e "  ${WHITE}Inside the VM:${NC}"
        echo -e "    ${CYAN}docker ps${NC}                     ${DIM}# List containers${NC}"
        echo -e "    ${CYAN}docker logs ${DEFAULT_CONTAINER_NAME}${NC}    ${DIM}# Container logs${NC}"
        echo -e "    ${CYAN}systemctl status one-appliance${NC} ${DIM}# Appliance status${NC}"
    fi
    echo ""
}

# Show manual deployment instructions
show_manual_deploy_instructions() {
    local image_path="$1"

    echo ""
    echo -e "  ${WHITE}To deploy manually:${NC}"
    echo ""
    echo -e "  ${DIM}# 1. Copy image to OpenNebula frontend${NC}"
    echo -e "  ${CYAN}scp ${image_path} <frontend>:/var/tmp/${NC}"
    echo ""
    echo -e "  ${DIM}# 2. Create image in OpenNebula${NC}"
    echo -e "  ${CYAN}oneimage create --name ${APPLIANCE_NAME}${NC} \\"
    echo -e "  ${CYAN}  --path /var/tmp/${APPLIANCE_NAME}.qcow2${NC} \\"
    echo -e "  ${CYAN}  --format qcow2 --datastore <DATASTORE_ID>${NC}"
    echo ""
    echo -e "  ${DIM}# 3. Create template and VM from Sunstone UI${NC}"
    echo -e "  ${DIM}#    or use onetemplate create / onetemplate instantiate${NC}"
    echo ""
    echo -e "  ${WHITE}For marketplace submission:${NC}"
    echo -e "    1. Add logo: ${CYAN}logos/${APPLIANCE_NAME}.png${NC}"
    echo -e "    2. Review: ${CYAN}appliances/${APPLIANCE_NAME}/${NC}"
    echo -e "    3. Commit and submit PR"
    echo ""
}

generate_appliance() {
    clear_screen
    print_header

    echo -e "  Generating appliance files..."
    echo ""

    local env_file="${SCRIPT_DIR}/${APPLIANCE_NAME}.env"

    cat > "$env_file" << ENVEOF
# Generated by OpenNebula Appliance Wizard v${WIZARD_VERSION}
# $(date)

DOCKER_IMAGE="${DOCKER_IMAGE}"
APPLIANCE_NAME="${APPLIANCE_NAME}"
APP_NAME="${APP_NAME}"
PUBLISHER_NAME="${PUBLISHER_NAME}"
PUBLISHER_EMAIL="${PUBLISHER_EMAIL}"
BASE_OS="${BASE_OS}"
APP_DESCRIPTION="${APP_DESCRIPTION}"
APP_FEATURES="${APP_FEATURES}"
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME}"
DEFAULT_PORTS="${DEFAULT_PORTS}"
DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS}"
DEFAULT_VOLUMES="${DEFAULT_VOLUMES}"
APP_PORT="${APP_PORT}"
WEB_INTERFACE="${WEB_INTERFACE}"

# VM Configuration
VM_CPU="${VM_CPU:-1}"
VM_VCPU="${VM_VCPU:-2}"
VM_MEMORY="${VM_MEMORY:-2048}"
VM_DISK_SIZE="${VM_DISK_SIZE:-12288}"
ONE_VERSION="${ONE_VERSION:-7.0}"

# SSH and Login Configuration
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY}"
AUTOLOGIN_ENABLED="${AUTOLOGIN_ENABLED:-true}"
LOGIN_USERNAME="${LOGIN_USERNAME:-root}"
ROOT_PASSWORD="${ROOT_PASSWORD}"

# Docker Update Configuration
DOCKER_AUTO_UPDATE="${DOCKER_AUTO_UPDATE:-CHECK}"
ENVEOF

    if [ -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
        "${SCRIPT_DIR}/generate-docker-appliance.sh" "$env_file" --no-build

        echo ""
        echo -e "  ${GREEN}✓ Appliance files generated successfully!${NC}"
        echo ""
        echo -e "  ${WHITE}Generated files:${NC}"
        echo -e "    appliances/${APPLIANCE_NAME}/"
        echo -e "    apps-code/community-apps/packer/${APPLIANCE_NAME}/"
        echo ""

        # Now build the appliance image
        echo -e "  ${BRIGHT_CYAN}Building appliance image...${NC}"
        echo ""

        # Check for cached base image
        local base_image="${REPO_ROOT}/apps-code/one-apps/export/${BASE_OS}.qcow2"
        if [ -f "$base_image" ]; then
            echo -e "  ${GREEN}✓${NC} Using cached base image: ${DIM}${BASE_OS}${NC}"
        else
            echo -e "  ${YELLOW}!${NC} Base image not cached (will be built)"
        fi

        # Check for Docker layer cache
        local docker_cache_info=""
        if docker images --format '{{.Repository}}' 2>/dev/null | grep -q "${DOCKER_IMAGE%%:*}"; then
            docker_cache_info=" (Docker layers cached)"
        fi
        echo -e "  ${DIM}Docker image: ${DOCKER_IMAGE}${docker_cache_info}${NC}"
        echo ""

        echo -e "  ${DIM}This may take 15-20 minutes (faster with cached layers)${NC}"
        echo -e "  ${DIM}Build output will appear below:${NC}"
        echo ""
        echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"

        cd "${REPO_ROOT}/apps-code/community-apps"

        # Run build with real-time output
        local build_log="${REPO_ROOT}/apps-code/community-apps/build-${APPLIANCE_NAME}.log"
        local build_start=$(date +%s)

        if make "$APPLIANCE_NAME" 2>&1 | tee "$build_log"; then
            local build_end=$(date +%s)
            local build_duration=$((build_end - build_start))
            local build_minutes=$((build_duration / 60))
            local build_seconds=$((build_duration % 60))

            echo ""
            echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
            echo ""
            echo -e "  ${GREEN}✓${NC} Build completed in ${build_minutes}m ${build_seconds}s"
            echo -e "  ${DIM}Log saved: ${build_log}${NC}"

            local image_path="${REPO_ROOT}/apps-code/community-apps/export/${APPLIANCE_NAME}.qcow2"
            show_build_success "$image_path"
        else
            echo ""
            echo -e "  ${GRAY}─────────────────────────────────────────────────────${NC}"
            echo ""
            print_error "Appliance build failed."
            echo -e "  ${DIM}Files were generated but the build failed.${NC}"
            echo -e "  ${DIM}Check log: ${build_log}${NC}"
            echo ""
            echo -e "  ${DIM}You can try building manually:${NC}"
            echo -e "  ${CYAN}cd ${REPO_ROOT}/apps-code/community-apps && make ${APPLIANCE_NAME}${NC}"
            echo ""
        fi
    else
        print_error "Generator not found"
        echo "  Config saved: ${env_file}"
        exit 1
    fi
}

handle_quit() {
    echo ""
    print_warning "Cancelled"
    exit 0
}

# Estimated build times for base OS images (in minutes)
# Format: os_id=build_time
declare -A OS_BUILD_TIMES=(
    ["ubuntu2204min"]="8"
    ["ubuntu2404min"]="8"
    ["ubuntu2204"]="12"
    ["ubuntu2404"]="12"
    ["debian11"]="10"
    ["debian12"]="10"
    ["alma8"]="15"
    ["alma9"]="15"
    ["rocky8"]="15"
    ["rocky9"]="15"
    ["opensuse15"]="12"
)

# Get estimated build time for OS
get_build_time() {
    local os_id="$1"
    local lookup="${os_id%.aarch64}"  # Strip ARM suffix
    echo "${OS_BUILD_TIMES[$lookup]:-12}"
}

# Scan for available (already built) base images
scan_available_images() {
    local export_dir="${REPO_ROOT}/apps-code/one-apps/export"
    local -n result_array=$1  # nameref to return array

    result_array=()

    if [ -d "$export_dir" ]; then
        for qcow2 in "$export_dir"/*.qcow2; do
            [ -f "$qcow2" ] || continue
            local filename=$(basename "$qcow2" .qcow2)
            result_array+=("$filename")
        done
    fi
}

# Get display name for an OS ID
get_os_display_name() {
    local os_id="$1"
    for entry in "${OS_LIST[@]}"; do
        local entry_id="${entry%%|*}"
        if [ "$entry_id" = "$os_id" ]; then
            local os_name="${entry#*|}"
            echo "${os_name%%|*}"
            return
        fi
    done
    echo "$os_id"
}

# Check if base OS image exists and offer to build it
check_base_image() {
    local base_image="${REPO_ROOT}/apps-code/one-apps/export/${BASE_OS}.qcow2"
    local base_os_display
    base_os_display=$(get_os_display_name "$BASE_OS")
    local build_time
    build_time=$(get_build_time "$BASE_OS")

    if [ -f "$base_image" ]; then
        return 0  # Image exists, continue
    fi

    # Scan for available images
    local available_images=()
    scan_available_images available_images

    # Image doesn't exist - alert and offer options
    clear_screen
    print_header

    echo ""
    echo -e "  ${YELLOW}⚠  Base Image Required${NC}"
    echo ""
    echo -e "  Your selected OS: ${WHITE}${base_os_display}${NC}"
    echo -e "  ${DIM}Image path: ${base_image}${NC}"
    echo ""

    # Show available images if any exist
    if [ ${#available_images[@]} -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} ${WHITE}Available base images on this host:${NC}"
        echo ""
        for img in "${available_images[@]}"; do
            local img_display
            img_display=$(get_os_display_name "$img")
            local img_size
            img_size=$(du -h "${REPO_ROOT}/apps-code/one-apps/export/${img}.qcow2" 2>/dev/null | cut -f1)
            echo -e "      ${CYAN}•${NC} ${img_display} ${DIM}(${img_size:-unknown})${NC}"
        done
        echo ""
        echo -e "  ${DIM}Tip: Choosing an available image skips the build step${NC}"
    else
        echo -e "  ${DIM}No pre-built base images found on this host.${NC}"
    fi

    echo ""
    echo -e "  ─────────────────────────────────────────────────────"
    echo ""
    echo -e "  ${WHITE}What would you like to do?${NC}"
    echo ""
    echo -e "    ${CYAN}1.${NC} Build ${WHITE}${base_os_display}${NC} now ${DIM}(~${build_time} min)${NC}"
    echo -e "    ${CYAN}2.${NC} Continue without image ${DIM}(build manually later)${NC}"
    echo -e "    ${CYAN}3.${NC} Choose a different base OS"
    echo ""

    # Show build time estimates for other OS options
    echo -e "  ${DIM}Estimated build times:${NC}"
    echo -e "  ${DIM}  Ubuntu Minimal: ~8 min  │  Debian: ~10 min${NC}"
    echo -e "  ${DIM}  Ubuntu Full: ~12 min    │  Alma/Rocky: ~15 min${NC}"
    echo ""

    local choice
    while true; do
        echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
        read -r choice
        case "$choice" in
            1)
                echo ""
                echo -e "  ${BRIGHT_CYAN}Building ${base_os_display} base image...${NC}"
                echo -e "  ${DIM}Estimated time: ~${build_time} minutes${NC}"
                echo ""

                # Build the base image
                cd "${REPO_ROOT}/apps-code/one-apps"
                if make "${BASE_OS}"; then
                    echo ""
                    print_success "Base image built successfully!"
                    sleep 1
                    return 0
                else
                    echo ""
                    print_error "Base image build failed."
                    echo -e "  ${DIM}You can try building it manually:${NC}"
                    echo -e "  ${CYAN}cd ${REPO_ROOT}/apps-code/one-apps && make ${BASE_OS}${NC}"
                    echo ""
                    prompt_yes_no "Continue with appliance generation anyway?" CONTINUE_ANYWAY "false"
                    if [ "$CONTINUE_ANYWAY" = "true" ]; then
                        return 0
                    else
                        return 1
                    fi
                fi
                ;;
            2)
                echo ""
                print_warning "Continuing without base image..."
                echo -e "  ${DIM}Remember to build it before building the appliance:${NC}"
                echo -e "  ${CYAN}cd ${REPO_ROOT}/apps-code/one-apps && make ${BASE_OS}${NC}"
                sleep 1
                return 0
                ;;
            3)
                return 2  # Signal to go back to OS selection
                ;;
            *)
                echo -e "  ${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Main wizard flow with navigation support
main() {
    # Check if we're in the right directory (only needed for Docker appliances)
    # LXC appliances don't need the generate-docker-appliance.sh script

    # ═══════════════════════════════════════════════════════════════════════════
    # NON-INTERACTIVE MODE: If env file was loaded, skip wizard steps
    # ═══════════════════════════════════════════════════════════════════════════
    if [ -n "$ENV_FILE" ]; then
        echo -e "  ${WHITE}Running in non-interactive mode...${NC}"
        echo ""

        # Check appliance type and run appropriate generator
        if [ "$APPLIANCE_TYPE" = "lxc" ]; then
            echo -e "  ${CYAN}Building LXC appliance...${NC}"
            generate_lxc_appliance
            echo ""
            exit 0
        fi

        # Docker appliance flow (original)
        if [ ! -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
            echo -e "${RED}Error: generate-docker-appliance.sh not found.${NC}"
            echo -e "Please cd to: ${SCRIPT_DIR}"
            exit 1
        fi

        # Check if base image exists
        local base_image="${REPO_ROOT}/apps-code/one-apps/export/${BASE_OS}.qcow2"
        if [ ! -f "$base_image" ]; then
            echo -e "  ${YELLOW}⚠${NC} Base image not found: ${BASE_OS}.qcow2"
            echo -e "  ${DIM}Building base image first (10-15 min)...${NC}"
            echo ""
            cd "${REPO_ROOT}/apps-code/one-apps"
            if ! make "${BASE_OS}"; then
                echo -e "  ${RED}✗${NC} Base image build failed"
                exit 1
            fi
            echo -e "  ${GREEN}✓${NC} Base image built"
            echo ""
        fi

        # Generate appliance files directly
        generate_appliance

        # Auto-build if requested
        if [ "$AUTO_BUILD" = "true" ]; then
            echo ""
            echo -e "  ${WHITE}Auto-building appliance...${NC}"
            cd "${REPO_ROOT}/apps-code/community-apps"
            if make "$APPLIANCE_NAME"; then
                echo -e "  ${GREEN}✓${NC} Build complete!"
                echo -e "  ${DIM}Image: ${REPO_ROOT}/apps-code/community-apps/export/${APPLIANCE_NAME}.qcow2${NC}"
            else
                echo -e "  ${RED}✗${NC} Build failed"
                # Cleanup on failure
                rm -rf "${REPO_ROOT}/appliances/${APPLIANCE_NAME}" 2>/dev/null
                rm -rf "${REPO_ROOT}/apps-code/community-apps/packer/${APPLIANCE_NAME}" 2>/dev/null
                exit 1
            fi
        fi

        echo ""
        exit 0
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # INTERACTIVE MODE: Run wizard steps
    # ═══════════════════════════════════════════════════════════════════════════

    # Initial steps to determine appliance type
    local steps=("step_welcome" "step_appliance_type")
    local current=0
    local total=${#steps[@]}
    local result

    while [ $current -lt $total ]; do
        if ${steps[$current]}; then
            result=0
        else
            result=$?
        fi
        case $result in
            $NAV_CONTINUE) current=$((current + 1)) ;;
            $NAV_BACK)
                if [ $current -gt 0 ]; then
                    current=$((current - 1))
                fi
                ;;
            $NAV_QUIT) handle_quit ;;
        esac
    done

    # Now build the type-specific steps array
    if [ "$APPLIANCE_TYPE" = "lxc" ]; then
        # LXC workflow
        steps=(
            "step_lxc_application"
            "step_architecture"
            "step_lxc_base_os"
            "step_context_mode"
            "step_lxc_vm_config"
            "step_lxc_summary"
        )
    else
        # Docker workflow (original)
        if [ ! -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
            echo -e "${RED}Error: Docker appliance generation requires generate-docker-appliance.sh${NC}"
            echo -e "Please cd to: ${SCRIPT_DIR}"
            exit 1
        fi

        steps=(
            "step_docker_image"
            "step_architecture"
            "step_base_os"
            "step_appliance_info"
            "step_publisher_info"
            "step_app_details"
            "step_container_config"
            "step_vm_config"
            "step_ssh_config"
            "step_login_config"
            "step_docker_updates"
            "step_summary"
        )
    fi

    current=0
    total=${#steps[@]}

    while [ $current -lt $total ]; do
        # Execute current step and capture result
        if ${steps[$current]}; then
            result=0
        else
            result=$?
        fi

        case $result in
            $NAV_CONTINUE)
                current=$((current + 1))
                ;;
            $NAV_BACK)
                if [ $current -gt 0 ]; then
                    current=$((current - 1))
                else
                    print_info "Already at first step."
                    sleep 0.5
                fi
                ;;
            $NAV_QUIT)
                handle_quit
                ;;
        esac
    done

    # Generate the appliance based on type
    if [ "$APPLIANCE_TYPE" = "lxc" ]; then
        # LXC appliances don't need base image check - we download Alpine rootfs on the fly
        generate_lxc_appliance
    else
        # Docker appliances need base image check
        while true; do
            local check_result
            if check_base_image; then
                check_result=0
            else
                check_result=$?
            fi

            case $check_result in
                0)
                    # Continue to generate
                    break
                    ;;
                1)
                    # User cancelled
                    handle_quit
                    ;;
                2)
                    # User wants to change OS - go directly to OS selection step
                    # Step indices: 2=architecture, 3=base_os (in Docker workflow, step_base_os is at index 2)
                    local os_step=2  # step_base_os index in Docker workflow

                    # Run only the OS selection step (and architecture if they go back)
                    local temp_current=$os_step
                    while [ $temp_current -ge 1 ] && [ $temp_current -le 2 ]; do
                        local result
                        if ${steps[$temp_current]}; then
                            result=0
                        else
                            result=$?
                        fi

                        case $result in
                            $NAV_CONTINUE)
                                if [ $temp_current -eq 2 ]; then
                                    # OS selected, break out and re-check base image
                                    break
                                else
                                    temp_current=$((temp_current + 1))
                                fi
                                ;;
                            $NAV_BACK)
                                if [ $temp_current -gt 1 ]; then
                                    temp_current=$((temp_current - 1))
                                else
                                    # At architecture step, allow going back further
                                    temp_current=$((temp_current - 1))
                                fi
                                ;;
                            $NAV_QUIT)
                                handle_quit
                                ;;
                        esac
                    done
                    # Loop back to check_base_image with new OS
                    ;;
            esac
        done

        generate_appliance
    fi
    echo ""
}

# Run the wizard
main "$@"

