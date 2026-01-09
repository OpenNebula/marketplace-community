#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  OpenNebula Community Marketplace - Appliance Creation Wizard             ║
# ║  Interactive wizard for creating Docker-based appliances                  ║
# ║  Production-ready with arrow-key navigation and step back/forward support ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Author: OpenNebula Community
# License: Apache 2.0
# Version: 1.0.0
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
WIZARD_VERSION="1.0.0"
WIZARD_CODENAME="Nebula"

# Script directory (wizard/ is at repo root level)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Current step tracking for navigation
CURRENT_STEP=0
TOTAL_STEPS=11

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

    # Validate required variables
    REQUIRED_VARS=("DOCKER_IMAGE" "APPLIANCE_NAME" "APP_NAME" "PUBLISHER_NAME" "PUBLISHER_EMAIL")
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
    echo -e "${BRIGHT_CYAN}"
    cat << 'EOF'
       ___                   _   _      _           _
      / _ \ _ __   ___ _ __ | \ | | ___| |__  _   _| | __ _
     | | | | '_ \ / _ \ '_ \|  \| |/ _ \ '_ \| | | | |/ _` |
     | |_| | |_) |  __/ | | | |\  |  __/ |_) | |_| | | (_| |
      \___/| .__/ \___|_| |_|_| \_|\___|_.__/ \__,_|_|\__,_|
           |_|
EOF
    echo -e "${NC}"
}

print_header() {
    print_logo
    echo -e "  ${WHITE}${BOLD}Appliance Wizard${NC} ${DIM}v${WIZARD_VERSION}${NC}"
    echo -e "  ${DIM}Docker → OpenNebula in minutes${NC}"
    echo ""
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
    local result_var=$1
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key=""

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

    while true; do
        IFS= read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') ((selected > 0)) && ((selected--)) ;;
                '[B') ((selected < num_options - 1)) && ((selected++)) ;;
            esac
        elif [ "$key" = "" ]; then
            break
        elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            show_cursor
            echo ""
            print_warning "Cancelled."
            exit 0
        elif [ "$key" = "b" ] || [ "$key" = "B" ]; then
            show_cursor
            eval "$result_var=-1"
            return $NAV_BACK
        elif [ "$key" = "k" ]; then
            ((selected > 0)) && ((selected--))
        elif [ "$key" = "j" ]; then
            ((selected < num_options - 1)) && ((selected++))
        fi

        # Redraw (num_options + 3 lines: empty line, options, empty line, help line)
        for ((i=0; i<num_options+3; i++)); do printf '\033[A'; done

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

    show_cursor
    eval "$result_var=$selected"
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
    print_header

    echo -e "${WHITE}Create a Docker-based OpenNebula appliance${NC}\n"
    echo -e "${DIM}Navigation: [:b] back  [:q] quit  [↑↓] menus${NC}\n"

    echo -en "  Press ${WHITE}[Enter]${NC} to start..."
    read -r
    return $NAV_CONTINUE
}

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

            if [ "$host_arch" = "aarch64" ] || [ "$host_arch" = "arm64" ]; then
                show_cross_arch_error "x86_64" "ARM64"
                continue  # Loop back to architecture selection
            fi
        else
            ARCH="aarch64"
            OS_LIST=("${OS_LIST_ARM[@]}")

            if [ "$host_arch" = "x86_64" ]; then
                show_cross_arch_error "ARM64" "x86_64"
                continue  # Loop back to architecture selection
            fi
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

step_summary() {
    clear_screen
    print_header
    print_step 11 $TOTAL_STEPS "Summary"

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
    command -v onevm &>/dev/null && systemctl is-active --quiet opennebula 2>/dev/null
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

# List available networks and let user select
# Sets SELECTED_NETWORK variable
select_network() {
    echo -e "  ${WHITE}Available networks:${NC}"
    echo ""

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

    while IFS= read -r line; do
        local id name used
        id=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        [ -z "$id" ] && continue

        net_ids+=("$id")
        net_names+=("$name")
        net_display+=("${name} (ID: ${id}, ${used} leases)")
    done <<< "$networks"

    if [ ${#net_ids[@]} -eq 0 ]; then
        SELECTED_NETWORK="vnet"
        SELECTED_NETWORK_ID=""
        return
    fi

    # If only one network, use it automatically
    if [ ${#net_ids[@]} -eq 1 ]; then
        SELECTED_NETWORK="${net_names[0]}"
        SELECTED_NETWORK_ID="${net_ids[0]}"
        echo -e "  ${DIM}Using network: ${SELECTED_NETWORK} (ID: ${SELECTED_NETWORK_ID})${NC}"
        return
    fi

    # Let user select
    local selected_idx=0
    menu_select selected_idx "${net_display[@]}"
    local result=$?

    if [ $result -eq $NAV_CONTINUE ]; then
        SELECTED_NETWORK="${net_names[$selected_idx]}"
        SELECTED_NETWORK_ID="${net_ids[$selected_idx]}"
    else
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

    # Check for existing image
    local existing_image
    existing_image=$(oneimage list -l ID,NAME 2>/dev/null | grep -w "$image_name" | awk '{print $1}' | head -1)

    # Check for existing template
    local existing_template
    existing_template=$(onetemplate list -l ID,NAME 2>/dev/null | grep -w "$image_name" | awk '{print $1}' | head -1)

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
    echo -e "  ${DIM}Using datastore: ${datastore_name} (ID: ${datastore_id})${NC}"
    echo ""

    # Select network
    select_network
    echo ""

    # Prompt for VM sizing (pass image path for disk size detection)
    prompt_vm_sizing "$image_path"
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
    wait "$pid"
    local exit_code=$?
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

    # Build NIC configuration
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
        arch_config="OS=[ARCH=\"aarch64\",FIRMWARE=\"/usr/share/AAVMF/AAVMF_CODE.fd\",FIRMWARE_SECURE=\"no\",MACHINE=\"virt\"]
CPU_MODEL=[MODEL=\"host-passthrough\"]
NIC_DEFAULT=[MODEL=\"virtio\"]
RAW=[TYPE=\"kvm\",DATA=\"<devices><input type='keyboard' bus='virtio'/></devices>\"]
SCHED_REQUIREMENTS=\"HYPERVISOR=kvm & ARCH=aarch64\""
    fi

    local template_content
    template_content="NAME=\"${image_name}\"
CPU=\"${VM_CPU}\"
VCPU=\"${VM_VCPU}\"
MEMORY=\"${VM_MEMORY}\"
DISK=[IMAGE_ID=\"${image_id}\",SIZE=\"${VM_DISK_SIZE}\"]
${nic_config}
GRAPHICS=[LISTEN=\"0.0.0.0\",TYPE=\"VNC\"]
CONTEXT=[NETWORK=\"YES\",SSH_PUBLIC_KEY=\"\$USER[SSH_PUBLIC_KEY]\"]
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
    echo -e "  ${CYAN}oneimage create --name ${APPLIANCE_NAME} \\${NC}"
    echo -e "  ${CYAN}  --path /var/tmp/${APPLIANCE_NAME}.qcow2 \\${NC}"
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
    # Check if we're in the right directory
    if [ ! -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
        echo -e "${RED}Error: This script must be run from the wizard directory.${NC}"
        echo -e "Please cd to: ${SCRIPT_DIR}"
        exit 1
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # NON-INTERACTIVE MODE: If env file was loaded, skip wizard steps
    # ═══════════════════════════════════════════════════════════════════════════
    if [ -n "$ENV_FILE" ]; then
        echo -e "  ${WHITE}Running in non-interactive mode...${NC}"
        echo ""

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

    # Array of step functions
    local steps=(
        "step_welcome"
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
        "step_summary"
    )

    local current=0
    local total=${#steps[@]}

    while [ $current -lt $total ]; do
        # Execute current step and capture result
        # Use subshell + variable to avoid set -e issues
        local result
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

    # Check if base image exists before generating
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
                # Step indices: 2=architecture, 3=base_os
                local os_step=3  # step_base_os index

                # Run only the OS selection step (and architecture if they go back)
                local temp_current=$os_step
                while [ $temp_current -ge 2 ] && [ $temp_current -le 3 ]; do
                    local result
                    if ${steps[$temp_current]}; then
                        result=0
                    else
                        result=$?
                    fi

                    case $result in
                        $NAV_CONTINUE)
                            if [ $temp_current -eq 3 ]; then
                                # OS selected, break out and re-check base image
                                break
                            else
                                temp_current=$((temp_current + 1))
                            fi
                            ;;
                        $NAV_BACK)
                            if [ $temp_current -gt 2 ]; then
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
    echo ""
}

# Run the wizard
main "$@"

