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

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Current step tracking for navigation
CURRENT_STEP=0
TOTAL_STEPS=9

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

menu_select() {
    local result_var=$1
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key=""

    # Find currently selected option if BASE_OS is already set
    if [ -n "$BASE_OS" ]; then
        for i in "${!OS_LIST[@]}"; do
            local os_id="${OS_LIST[$i]%%|*}"
            if [ "$os_id" = "$BASE_OS" ]; then
                selected=$i
                break
            fi
        done
    fi

    hide_cursor

    # Print options
    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo -e "  ${BRIGHT_GREEN}▸${NC} ${WHITE}${options[$i]}${NC}"
        else
            echo -e "    ${DIM}${options[$i]}${NC}"
        fi
    done
    echo ""
    echo -e "  ${DIM}[↑↓] Navigate  [Enter] Select  [q] Quit${NC}"

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
        elif [ "$key" = "k" ]; then
            ((selected > 0)) && ((selected--))
        elif [ "$key" = "j" ]; then
            ((selected < num_options - 1)) && ((selected++))
        fi

        # Redraw
        for ((i=0; i<num_options+2; i++)); do printf '\033[A'; done

        for i in "${!options[@]}"; do
            printf '\033[2K'
            if [ $i -eq $selected ]; then
                echo -e "  ${BRIGHT_GREEN}▸${NC} ${WHITE}${options[$i]}${NC}"
            else
                echo -e "    ${DIM}${options[$i]}${NC}"
            fi
        done
        printf '\033[2K'
        echo ""
        printf '\033[2K'
        echo -e "  ${DIM}[↑↓] Navigate  [Enter] Select  [q] Quit${NC}"
    done

    show_cursor
    eval "$result_var=$selected"
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

    echo -en "${DIM}[Enter] Start${NC}"
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

        if validate_docker_image "$DOCKER_IMAGE"; then
            sleep 0.3
            return $NAV_CONTINUE
        else
            print_error "Invalid format. Use: image:tag"
        fi
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

        echo ""
        print_success "$ARCH"
        sleep 0.3
        return $NAV_CONTINUE
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
    print_step 8 $TOTAL_STEPS "VM Configuration"
    print_nav_hint

    echo -e "  ${DIM}Configure VM resources (press Enter for defaults)${NC}"
    echo ""

    prompt_optional "CPU cores" VM_CPU "1"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "vCPUs" VM_VCPU "2"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Memory (MB)" VM_MEMORY "2048"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_optional "Disk size (MB)" VM_DISK_SIZE "12288"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    # ONE_VERSION defaults to 7.0 (hidden from user)
    ONE_VERSION="${ONE_VERSION:-7.0}"

    sleep 0.3
    return $NAV_CONTINUE
}

step_summary() {
    clear_screen
    print_header
    print_step 9 $TOTAL_STEPS "Summary"

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
    echo -e "${CYAN}CPU Cores:${NC}           ${VM_CPU:-1}"
    echo -e "${CYAN}vCPUs:${NC}               ${VM_VCPU:-2}"
    echo -e "${CYAN}Memory:${NC}              ${VM_MEMORY:-2048} MB"
    echo -e "${CYAN}Disk Size:${NC}           ${VM_DISK_SIZE:-12288} MB"
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
wait_for_vm_running() {
    local vm_id="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    local spin_idx=0
    local state=""
    local state_str=""
    local lcm_state=""

    echo ""
    echo -e "  ${WHITE}Waiting for VM to start...${NC}"
    hide_cursor

    while [ $elapsed -lt $max_wait ]; do
        # Check state every 2 seconds (every 10 iterations at 0.2s each)
        if [ $((elapsed % 10)) -eq 0 ]; then
            state=$(onevm show "$vm_id" -x 2>/dev/null | grep '<STATE>' | sed 's/.*<STATE>\([0-9]*\)<\/STATE>.*/\1/' | head -1)
            state_str=$(onevm show "$vm_id" -x 2>/dev/null | grep '<STATE_STR>' | sed 's/.*<STATE_STR>\([^<]*\)<\/STATE_STR>.*/\1/' | head -1)

            # State 3 = ACTIVE, LCM_STATE 3 = RUNNING
            if [ "$state" = "3" ]; then
                lcm_state=$(onevm show "$vm_id" -x 2>/dev/null | grep '<LCM_STATE>' | sed 's/.*<LCM_STATE>\([0-9]*\)<\/LCM_STATE>.*/\1/' | head -1)
                if [ "$lcm_state" = "3" ]; then
                    printf "\r${CLEAR_LINE}"
                    echo -e "  ${GREEN}✓${NC} VM is running!"
                    show_cursor
                    return 0
                fi
            fi
        fi

        # Show current state with fast spinner
        printf "\r  ${CYAN}${SPINNER_FRAMES[$spin_idx]}${NC} State: %-15s" "${state_str:-pending}"
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

    if wait_for_vm_running "$vm_id" 1500; then  # 5 minutes (1500 iterations at 0.2s each)
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
    else
        # VM didn't start in time, show details anyway
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

# Check if base OS image exists and offer to build it
check_base_image() {
    local base_image="${REPO_ROOT}/apps-code/one-apps/export/${BASE_OS}.qcow2"

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

    if [ -f "$base_image" ]; then
        return 0  # Image exists, continue
    fi

    # Image doesn't exist - alert and offer to build
    clear_screen
    print_header

    echo ""
    echo -e "  ${YELLOW}⚠  Base image not found${NC}"
    echo ""
    echo -e "  The base OS image for ${WHITE}${base_os_display}${NC} hasn't been built yet."
    echo -e "  ${DIM}Required: ${base_image}${NC}"
    echo ""
    echo -e "  ─────────────────────────────────────────────────────"
    echo ""
    echo -e "  ${WHITE}Options:${NC}"
    echo -e "    ${CYAN}1.${NC} Build it now ${DIM}(~10-15 min, recommended)${NC}"
    echo -e "    ${CYAN}2.${NC} Continue anyway ${DIM}(build manually later)${NC}"
    echo -e "    ${CYAN}3.${NC} Go back and choose a different base OS"
    echo ""

    local choice
    while true; do
        echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
        read -r choice
        case "$choice" in
            1)
                echo ""
                echo -e "  ${BRIGHT_CYAN}Building ${base_os_display} base image...${NC}"
                echo -e "  ${DIM}This may take 10-15 minutes${NC}"
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
        echo -e "${RED}Error: This script must be run from the automatic-appliance-tutorial directory.${NC}"
        echo -e "Please cd to: ${SCRIPT_DIR}"
        exit 1
    fi

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
                # Go back to architecture selection (step 2) so user can change arch and OS
                current=2  # step_architecture index
                while [ $current -lt $total ]; do
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

