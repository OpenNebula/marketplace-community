#!/bin/bash
#
# OpenNebula Community Marketplace - Appliance Creation Wizard
# Interactive wizard for creating Docker-based appliances
# Production-ready with arrow-key navigation and step back/forward support
#

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
REVERSE='\033[7m'
NC='\033[0m' # No Color

# Cursor control
CURSOR_UP='\033[A'
CURSOR_DOWN='\033[B'
CLEAR_LINE='\033[2K'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Current step tracking for navigation
CURRENT_STEP=0
TOTAL_STEPS=7

# Variables to collect
DOCKER_IMAGE=""
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
declare -a OS_LIST=(
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

# Helper functions
clear_screen() {
    clear
}

# Hide/show cursor
hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

# Trap to ensure cursor is shown on exit
trap 'show_cursor; stty echo 2>/dev/null' EXIT INT TERM

# Navigation result constants - must be defined before functions use them
NAV_CONTINUE=0
NAV_BACK=1
NAV_QUIT=2

print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}║   ${WHITE}OpenNebula Community Marketplace${BLUE}                            ║${NC}"
    echo -e "${BLUE}║   ${CYAN}Docker Appliance Creation Wizard${BLUE}                            ║${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local title=$3
    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Step ${step}/${total}: ${title}${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_nav_hint() {
    echo -e "${DIM}Navigation: [Enter] Continue  [b] Back  [q] Quit${NC}\n"
}

print_info() {
    echo -e "${DIM}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Arrow-key menu selector
# Usage: menu_select result_var "Option 1" "Option 2" "Option 3"
# Returns the selected index (0-based) in the variable named by result_var
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

    # Print all options
    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo -e "  ${REVERSE}${GREEN} › ${options[$i]} ${NC}"
        else
            echo -e "    ${DIM}${options[$i]}${NC}"
        fi
    done

    # Navigation hint
    echo ""
    echo -e "${DIM}  ↑/↓ Navigate  Enter: Select  q: Quit${NC}"

    while true; do
        # Read a single character
        IFS= read -rsn1 key

        # Handle escape sequences (arrow keys)
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') # Up arrow
                    ((selected > 0)) && ((selected--))
                    ;;
                '[B') # Down arrow
                    ((selected < num_options - 1)) && ((selected++))
                    ;;
            esac
        elif [ "$key" = "" ]; then  # Enter key
            break
        elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            show_cursor
            echo ""
            print_warning "Wizard cancelled."
            exit 0
        elif [ "$key" = "k" ]; then  # vim-style up
            ((selected > 0)) && ((selected--))
        elif [ "$key" = "j" ]; then  # vim-style down
            ((selected < num_options - 1)) && ((selected++))
        fi

        # Move cursor up to redraw options
        for ((i=0; i<num_options+2; i++)); do
            printf '\033[A'  # Move up
        done

        # Redraw options
        for i in "${!options[@]}"; do
            printf '\033[2K'  # Clear line
            if [ $i -eq $selected ]; then
                echo -e "  ${REVERSE}${GREEN} › ${options[$i]} ${NC}"
            else
                echo -e "    ${DIM}${options[$i]}${NC}"
            fi
        done
        echo ""
        echo -e "${DIM}  ↑/↓ Navigate  Enter: Select  q: Quit${NC}"
    done

    show_cursor
    eval "$result_var=$selected"
}

# Enhanced prompt with navigation support
# Returns: 0=continue, 1=back, 2=quit
prompt_with_nav() {
    local prompt=$1
    local var_name=$2
    local default=$3
    local required=$4  # "true" or "false"
    local value=""

    while true; do
        local current_val
        eval "current_val=\$$var_name"
        local show_default="${current_val:-$default}"

        if [ -n "$show_default" ]; then
            echo -en "${CYAN}${prompt}${NC} ${DIM}[${show_default}]${NC}: "
        elif [ "$required" = "true" ]; then
            echo -en "${CYAN}${prompt}${NC}: "
        else
            echo -en "${CYAN}${prompt}${NC} ${DIM}(optional)${NC}: "
        fi

        read -r value

        # Check for navigation commands
        case "${value,,}" in
            ':b'|':back'|'<')
                return $NAV_BACK
                ;;
            ':q'|':quit')
                return $NAV_QUIT
                ;;
        esac

        # Use existing value if just Enter pressed
        if [ -z "$value" ]; then
            value="$show_default"
        fi

        if [ "$required" = "true" ] && [ -z "$value" ]; then
            print_error "This field is required. Enter a value or :b to go back."
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

    echo -e "${WHITE}Welcome to the OpenNebula Appliance Creation Wizard!${NC}\n"
    echo -e "This wizard will guide you through creating a Docker-based appliance"
    echo -e "for the OpenNebula Community Marketplace.\n"
    echo -e "${DIM}What you'll create:${NC}"
    echo -e "  • A complete appliance with all necessary files"
    echo -e "  • Packer configuration for building the VM image"
    echo -e "  • Documentation and metadata for the marketplace\n"
    echo -e "${DIM}Prerequisites:${NC}"
    echo -e "  • A Docker image available on Docker Hub (or other registry)"
    echo -e "  • Basic information about your application\n"
    echo -e "${DIM}Navigation:${NC}"
    echo -e "  • Type ${CYAN}:b${NC} or ${CYAN}:back${NC} to go back to previous step"
    echo -e "  • Type ${CYAN}:q${NC} or ${CYAN}:quit${NC} to exit the wizard"
    echo -e "  • Use ${CYAN}↑/↓${NC} arrow keys for menu selections\n"

    echo -en "${YELLOW}Press Enter to continue or Ctrl+C to exit...${NC}"
    read -r
    return $NAV_CONTINUE
}

step_docker_image() {
    clear_screen
    print_header
    print_step 1 $TOTAL_STEPS "Docker Image"
    print_nav_hint

    echo -e "Enter the Docker image you want to use for your appliance.\n"
    print_info "Examples:"
    print_info "  • nginx:alpine"
    print_info "  • nodered/node-red:latest"
    print_info "  • nextcloud/all-in-one:latest"
    print_info "  • postgres:16-alpine"
    echo ""

    while true; do
        prompt_required "Docker image" DOCKER_IMAGE
        local result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        if validate_docker_image "$DOCKER_IMAGE"; then
            print_success "Docker image: $DOCKER_IMAGE"
            sleep 0.5
            return $NAV_CONTINUE
        else
            print_error "Invalid Docker image format. Please use format: image:tag or registry/image:tag"
        fi
    done
}

step_base_os() {
    clear_screen
    print_header
    print_step 2 $TOTAL_STEPS "Base Operating System"

    echo -e "Select the base operating system for your appliance VM.\n"
    print_info "The base OS determines which Linux distribution will run your Docker container."
    print_info "Ubuntu 22.04 LTS (Minimal) is recommended for most use cases."
    echo ""

    # Build menu options from OS_LIST
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
    print_success "Base OS: $os_name ($BASE_OS)"
    sleep 0.5
    return $NAV_CONTINUE

}

step_appliance_info() {
    clear_screen
    print_header
    print_step 3 $TOTAL_STEPS "Appliance Information"
    print_nav_hint

    echo -e "Enter basic information about your appliance.\n"

    # Appliance name (lowercase, no spaces)
    print_info "Appliance name must be lowercase letters, numbers, and hyphens only."
    print_info "Examples: nginx, node-red, nextcloud, postgres"
    echo ""

    while true; do
        prompt_required "Appliance name (lowercase)" APPLIANCE_NAME
        local result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        APPLIANCE_NAME=$(echo "$APPLIANCE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if validate_appliance_name "$APPLIANCE_NAME"; then
            print_success "Appliance name: $APPLIANCE_NAME"
            break
        else
            print_error "Invalid name. Use only lowercase letters, numbers, and hyphens. Must start with a letter."
        fi
    done

    echo ""
    print_info "Display name is what users will see in the marketplace."
    print_info "Examples: NGINX, Node-RED, Nextcloud, PostgreSQL"
    echo ""

    prompt_required "Display name" APP_NAME
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    print_success "Display name: $APP_NAME"
    sleep 0.5
    return $NAV_CONTINUE
}

step_publisher_info() {
    clear_screen
    print_header
    print_step 4 $TOTAL_STEPS "Publisher Information"
    print_nav_hint

    echo -e "Enter your publisher information for the marketplace.\n"

    prompt_required "Your name" PUBLISHER_NAME
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    print_success "Publisher: $PUBLISHER_NAME"

    echo ""
    prompt_required "Your email" PUBLISHER_EMAIL
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    print_success "Email: $PUBLISHER_EMAIL"

    sleep 0.5
    return $NAV_CONTINUE
}

step_app_details() {
    clear_screen
    print_header
    print_step 5 $TOTAL_STEPS "Application Details"
    print_nav_hint

    echo -e "Enter additional details about your application.\n"

    print_info "Enter a brief description of what your application does."
    local default_desc="${APP_NAME:-Application} - A Docker-based application for OpenNebula"
    prompt_optional "Description" APP_DESCRIPTION "$default_desc"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    print_info "Enter key features, separated by commas."
    print_info "Example: Web Server,Reverse Proxy,Load Balancer"
    prompt_optional "Features (comma-separated)" APP_FEATURES ""
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    print_info "Main port where the application is accessible."
    prompt_optional "Main application port" APP_PORT "8080"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    prompt_yes_no "Does this application have a web interface?" WEB_INTERFACE "true"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.5
    return $NAV_CONTINUE
}

step_container_config() {
    clear_screen
    print_header
    print_step 6 $TOTAL_STEPS "Container Configuration"
    print_nav_hint

    echo -e "Configure how the Docker container will run.\n"

    local default_container="${APPLIANCE_NAME:-app}-container"
    print_info "Container name used when running the Docker container."
    prompt_optional "Container name" DEFAULT_CONTAINER_NAME "$default_container"
    local result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    local default_ports="${APP_PORT:-8080}:${APP_PORT:-8080}"
    print_info "Port mappings in format: host:container,host:container"
    print_info "Example: 80:80,443:443 or 8080:8080"
    prompt_optional "Port mappings" DEFAULT_PORTS "$default_ports"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    print_info "Environment variables in format: VAR1=value1,VAR2=value2"
    prompt_optional "Environment variables" DEFAULT_ENV_VARS ""
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result
    echo ""

    print_info "Volume mappings in format: /host:/container,/host2:/container2"
    print_info "Example: /data:/data or /config:/app/config"
    prompt_optional "Volume mappings" DEFAULT_VOLUMES "/data:/data"
    result=$?
    [ $result -ne $NAV_CONTINUE ] && return $result

    sleep 0.5
    return $NAV_CONTINUE
}

step_summary() {
    clear_screen
    print_header
    print_step 7 $TOTAL_STEPS "Summary"

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

    echo -e "${WHITE}Please review your appliance configuration:${NC}\n"

    echo -e "${CYAN}Docker Image:${NC}        $DOCKER_IMAGE"
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

generate_appliance() {
    clear_screen
    print_header

    echo -e "${WHITE}Generating appliance files...${NC}\n"

    # Create .env file
    local env_file="${SCRIPT_DIR}/${APPLIANCE_NAME}.env"

    cat > "$env_file" << ENVEOF
# Generated by OpenNebula Appliance Wizard
# $(date)

# Required variables
DOCKER_IMAGE="${DOCKER_IMAGE}"
APPLIANCE_NAME="${APPLIANCE_NAME}"
APP_NAME="${APP_NAME}"
PUBLISHER_NAME="${PUBLISHER_NAME}"
PUBLISHER_EMAIL="${PUBLISHER_EMAIL}"

# Base operating system
BASE_OS="${BASE_OS}"

# Optional variables
APP_DESCRIPTION="${APP_DESCRIPTION}"
APP_FEATURES="${APP_FEATURES}"
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME}"
DEFAULT_PORTS="${DEFAULT_PORTS}"
DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS}"
DEFAULT_VOLUMES="${DEFAULT_VOLUMES}"
APP_PORT="${APP_PORT}"
WEB_INTERFACE="${WEB_INTERFACE}"
ENVEOF

    print_success "Created configuration: ${env_file}"

    # Run the generator script
    echo ""
    echo -e "${YELLOW}Running appliance generator...${NC}\n"

    if [ -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
        # Run generator without prompting for build
        "${SCRIPT_DIR}/generate-docker-appliance.sh" "$env_file" --no-build

        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                                                                  ║${NC}"
        echo -e "${GREEN}║   ${WHITE}✓ Appliance created successfully!${GREEN}                             ║${NC}"
        echo -e "${GREEN}║                                                                  ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        echo -e "${WHITE}Files created:${NC}"
        echo -e "  ${CYAN}•${NC} appliances/${APPLIANCE_NAME}/"
        echo -e "  ${CYAN}•${NC} apps-code/community-apps/packer/${APPLIANCE_NAME}/"
        echo ""

        echo -e "${WHITE}Next steps:${NC}"
        echo -e "  ${DIM}1.${NC} Review and customize the generated files"
        echo -e "  ${DIM}2.${NC} Build the image: ${CYAN}cd apps-code/community-apps && make ${APPLIANCE_NAME}${NC}"
        echo -e "  ${DIM}3.${NC} Test on OpenNebula"
        echo -e "  ${DIM}4.${NC} Add a logo: ${CYAN}logos/${APPLIANCE_NAME}.png${NC} (256x256)"
        echo -e "  ${DIM}5.${NC} Submit a Pull Request to the marketplace"
        echo ""

        prompt_yes_no "Would you like to build the image now?" BUILD_NOW "false"

        if [ "$BUILD_NOW" = "true" ]; then
            echo ""
            echo -e "${YELLOW}Starting build process...${NC}"
            echo -e "${DIM}This may take 15-20 minutes.${NC}\n"
            cd "${REPO_ROOT}/apps-code/community-apps"
            make "$APPLIANCE_NAME"
        fi
    else
        print_error "Generator script not found: ${SCRIPT_DIR}/generate-docker-appliance.sh"
        echo -e "\n${WHITE}Configuration saved to:${NC} ${env_file}"
        echo -e "You can run the generator manually with:"
        echo -e "  ${CYAN}./generate-docker-appliance.sh ${APPLIANCE_NAME}.env${NC}"
        exit 1
    fi
}

# Handle navigation quit
handle_quit() {
    echo ""
    print_warning "Wizard cancelled."
    exit 0
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
        "step_base_os"
        "step_appliance_info"
        "step_publisher_info"
        "step_app_details"
        "step_container_config"
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

    # All steps completed, generate the appliance
    generate_appliance

    echo ""
    echo -e "${GREEN}Thank you for using the OpenNebula Appliance Wizard!${NC}"
    echo ""
}

# Run the wizard
main "$@"

