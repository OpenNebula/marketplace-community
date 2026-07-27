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

# REG-3: the temp spec path must be visible to the EXIT trap, which runs in the
# shell's GLOBAL scope after generate_appliance() (and main) have returned. A
# `local env_file` would be out of scope by then, so `rm -f "$env_file"` would
# expand to `rm -f ""` and leak the (possibly secret-bearing) spec in $TMPDIR.
# Declare it at script scope and have the single global trap clean it up.
WIZARD_ENV_FILE=""

# Trap to ensure cursor is shown on exit AND the temp spec is removed on the
# normal (successful) exit path, not only on interrupt.
# The trailing `|| true` matters: `stty` fails whenever stdin is not a terminal,
# and under `set -e` a failing last command in the EXIT trap REPLACES the
# script's exit status with 1 -- which would make a successful run report
# failure and hide the deliberate non-zero exits below.
trap 'rm -f "$WIZARD_ENV_FILE"; show_cursor; stty echo 2>/dev/null || true' EXIT INT TERM

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
    echo -e "  ${DIM}[Enter] Next  [b] Back  [q] Quit${NC}"
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
# END-OF-INPUT GUARD
# ═══════════════════════════════════════════════════════════════════════════════
#
# Every prompt in this wizard reads stdin inside a loop. On a non-interactive
# stdin (a pipe, `</dev/null`, CI, `ssh host bash -s`) `read` returns non-zero
# immediately with an empty value. Left unguarded the surrounding loops either
# spin forever ("Required field" / "Invalid choice." in an unbounded loop) or
# silently accept a default the user never chose.
#
# `set -e` cannot save us here: every step runs as `if ${steps[$current]}; then`,
# a condition context, which disables errexit for the whole call tree. So each
# read tests for end of input explicitly and aborts through this helper with
# actionable guidance.
#
# Rule used at every call site: a final line with no trailing newline also makes
# `read` return non-zero but DOES set a value, so only "non-zero AND empty"
# counts as end of input.
abort_on_eof() {
    show_cursor
    stty echo 2>/dev/null || true
    echo ""
    print_error "End of input: the wizard requires an interactive terminal."
    local hint
    for hint in "$@"; do
        print_info "$hint"
    done
    exit 1
}

# Standard hint for the prompts that collect the appliance spec.
NONINTERACTIVE_HINT_1="For non-interactive/CI use, write a spec file and run:"
NONINTERACTIVE_HINT_2="  ./generate-docker-appliance.sh <spec>.env --no-build"

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

    local _ms_rc
    while true; do
        # EOF GUARD: at end of input `read` returns non-zero and leaves $key
        # empty, which the `[ "$key" = "" ]` branch below treats exactly like
        # pressing Enter -- the wizard would silently commit to option 0
        # (ubuntu2204min) as if the user had picked it. Distinguish real EOF.
        _ms_rc=0
        IFS= read -rsn1 key || _ms_rc=$?
        if [ $_ms_rc -ne 0 ] && [ -z "$key" ]; then
            abort_on_eof \
                "For non-interactive/CI use, set BASE_OS in a spec file and run:" \
                "$NONINTERACTIVE_HINT_2"
        fi

        if [ "$key" = $'\x1b' ]; then
            # A bare Esc times out here; that is expected, not an error.
            read -rsn2 -t 0.1 key || true
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
    # INJ-2: assign the numeric selection without eval.
    printf -v "$result_var" '%s' "$selected"
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
        # INJ-2: read the current value via safe indirect expansion, not eval.
        local current_val="${!var_name}"
        local show_default="${current_val:-$default}"

        if [ -n "$show_default" ]; then
            echo -ne "  ${prompt} ${DIM}[${show_default}]${NC}: "
        elif [ "$required" = "true" ]; then
            echo -ne "  ${prompt}${RED}*${NC}: "
        else
            echo -ne "  ${prompt} ${DIM}(optional)${NC}: "
        fi

        # EOF GUARD (see abort_on_eof): without this, a required field with no
        # default never gets a value, so the `required` branch below prints
        # "Required field" and re-prompts in an unbounded loop.
        local _rc=0
        read -r value || _rc=$?
        if [ $_rc -ne 0 ] && [ -z "$value" ]; then
            abort_on_eof "$NONINTERACTIVE_HINT_1" "$NONINTERACTIVE_HINT_2"
        fi

        case "${value,,}" in
            ':b'|':back'|'<') return $NAV_BACK ;;
            ':q'|':quit') return $NAV_QUIT ;;
        esac

        [ -z "$value" ] && value="$show_default"

        if [ "$required" = "true" ] && [ -z "$value" ]; then
            print_error "Required field"
        else
            # INJ-2: assign the literal value without re-parsing it as shell.
            # `printf -v` cannot break out the way `eval "$var='$value'"` can.
            printf -v "$var_name" '%s' "$value"
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

    # INJ-2: read the current value via safe indirect expansion, not eval.
    local current_val="${!var_name}"
    [ -n "$current_val" ] && default="$current_val"

    echo -en "${CYAN}${prompt}${NC} ${DIM}[${default_hint}]${NC}: "
    # EOF GUARD (see abort_on_eof): on end of input `read` returns non-zero with
    # an empty value, which would otherwise fall through to `*)` and silently
    # answer the question with the default. `value` is deliberately local so one
    # prompt cannot leak an answer into the next.
    local value=""
    local _rc=0
    read -r value || _rc=$?
    if [ $_rc -ne 0 ] && [ -z "$value" ]; then
        abort_on_eof "$NONINTERACTIVE_HINT_1" "$NONINTERACTIVE_HINT_2"
    fi

    case "${value,,}" in
        ':b'|':back'|'<') return $NAV_BACK ;;
        ':q'|':quit') return $NAV_QUIT ;;
        # INJ-2: assign literally via printf -v instead of eval.
        y|yes) printf -v "$var_name" '%s' 'true' ;;
        n|no) printf -v "$var_name" '%s' 'false' ;;
        *) printf -v "$var_name" '%s' "$default" ;;
    esac
    return $NAV_CONTINUE
}

validate_docker_image() {
    local image=$1

    # Basic character sanity for a Docker reference. Allow an optional
    # registry host[:port]/ prefix (so `registry:5000/nginx:1.25` is valid),
    # a repository path, an optional :tag, and an optional @sha256 digest.
    # The charset (letters, digits, . _ - / :) matches what the generator's
    # metachar gate permits; the pin policy below enforces the tag/digest rule.
    if [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/:-]*(@sha256:[a-fA-F0-9]{64})?$ ]]; then
        return 1
    fi

    # REG-2: enforce the SAME pin policy as generate-docker-appliance.sh (DEF-2)
    # so the wizard cannot accept an image the generator will later reject and
    # crash on. Reject a bare name and ':latest'; require a fixed :tag or an
    # @sha256 digest. We strip an optional registry prefix (first '/'-segment
    # containing '.' or ':') so a registry PORT colon is not mistaken for a tag.
    if [[ "$image" == *"@sha256:"* ]]; then
        return 0  # digest-pinned, best case
    fi
    local repo="$image" first="${image%%/*}"
    if [[ "$image" == */* && ( "$first" == *.* || "$first" == *:* ) ]]; then
        repo="${image#*/}"
    fi
    if [[ "$repo" != *:* ]]; then
        return 2  # no tag/digest -> resolves to mutable :latest
    elif [[ "${repo##*:}" == "latest" ]]; then
        return 3  # explicit mutable :latest
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
    echo -e "  • A Docker image on Docker Hub (or another registry), pinned to a"
    echo -e "    fixed :tag or an @sha256 digest"
    echo -e "  • Basic information about your application"
    echo -e "  • To BUILD an image: a Linux host with /dev/kvm, run as root, and the"
    echo -e "    one-apps build tooling — packer >= 1.9.4, qemu-utils, qemu-system-x86,"
    echo -e "    libguestfs-tools, make, ruby, rpm, rsync, genisoimage, cloud-utils,"
    echo -e "    cloud-image-utils, plus the 'backports' and 'fpm' gems"
    echo -e "    ${DIM}Full list: https://github.com/OpenNebula/one-apps/wiki/tool_reqs${NC}"
    echo -e "  • Initialised git submodules ${DIM}(the wizard runs this for you)${NC}\n"
    echo -e "${DIM}Navigation:${NC}"
    echo -e "  • Type ${CYAN}:b${NC} or ${CYAN}:back${NC} to go back to previous step"
    echo -e "  • Type ${CYAN}:q${NC} or ${CYAN}:quit${NC} to exit the wizard"
    echo -e "  • Use ${CYAN}↑/↓${NC} arrow keys for menu selections\n"

    echo -en "${YELLOW}Press Enter to continue or Ctrl+C to exit...${NC}"
    # EOF GUARD (see abort_on_eof): fail here with a clear message rather than
    # racing through every step on a non-interactive stdin.
    local _rc=0
    read -r || _rc=$?
    if [ $_rc -ne 0 ] && [ -z "$REPLY" ]; then
        abort_on_eof "$NONINTERACTIVE_HINT_1" "$NONINTERACTIVE_HINT_2"
    fi
    return $NAV_CONTINUE
}

step_docker_image() {
    clear_screen
    print_header
    print_step 1 $TOTAL_STEPS "Docker Image"
    print_nav_hint

    echo -e "Enter the Docker image you want to use for your appliance.\n"
    print_info "Pin a specific version (a fixed :tag or an @sha256 digest)."
    print_info "':latest' and untagged names are rejected for reproducible builds."
    print_info "Examples:"
    print_info "  • nginx:1.25.3"
    print_info "  • nodered/node-red:5.0.1"
    print_info "  • redis:7.4.1-alpine"
    print_info "  • postgres:16-alpine"
    print_info "  • nginx@sha256:<64-hex-digest>   (digest pin, strongest)"
    echo ""
    print_warning "Images that manage OTHER containers (nextcloud/all-in-one, portainer,"
    print_warning "watchtower, traefik, ...) need /var/run/docker.sock bind-mounted, which"
    print_warning "the generator rejects as a container-escape vector. Pinning the tag does"
    print_warning "not help: they cannot be turned into an appliance with this tool."
    echo ""

    while true; do
        prompt_required "Docker image" DOCKER_IMAGE
        local result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        # REG-2: surface the specific pin-policy failure so the user fixes it
        # here instead of getting a raw generator [ERROR] after all 7 steps.
        validate_docker_image "$DOCKER_IMAGE"
        local vres=$?
        case $vres in
            0)
                print_success "Docker image: $DOCKER_IMAGE"
                sleep 0.5
                return $NAV_CONTINUE
                ;;
            2)
                print_error "Image '$DOCKER_IMAGE' has no tag/digest (resolves to mutable :latest). Pin it, e.g. image:1.2.3"
                ;;
            3)
                print_error "Image '$DOCKER_IMAGE' uses the mutable ':latest' tag. Pin a specific version, e.g. image:1.2.3"
                ;;
            *)
                print_error "Invalid Docker image format. Use image:tag, registry/image:tag, or image@sha256:<digest>"
                ;;
        esac
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
    print_info "Examples: nginx, node-red, redis, postgres"
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
    print_info "Examples: NGINX, Node-RED, Redis, PostgreSQL"
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
    print_info "Example: /opt/${APPLIANCE_NAME:-app}/data:/var/lib/${APPLIANCE_NAME:-app}"
    print_warning "Leave EMPTY unless the app needs persistence. Mounting an empty host"
    print_warning "directory over a path the image ships (e.g. /etc/nginx/conf.d) HIDES"
    print_warning "that content and the container starts with no configuration."
    echo ""

    # The generator hard-fails (exit 1) on any volume whose host path resolves
    # under a protected system location. Mirror that list here so the user is
    # told at THIS step instead of after all 7 steps and a temp spec have been
    # written. Keep in sync with SENSITIVE_MOUNT_ROOTS in
    # generate-docker-appliance.sh (bare /etc is intentionally NOT listed, so
    # config-dir mounts like /etc/nginx/conf.d stay allowed).
    local _sensitive_roots=(
        /var/run/docker.sock /run/docker.sock
        / /root /proc /sys /dev /boot
        /var/run /run /usr /bin /sbin /lib /lib64 /var/lib/docker
    )
    local _bad _vol _host _root
    local _vols=()
    while true; do
        # Default is EMPTY, matching the generator's own default and the fixed
        # examples/nginx.env. The old "/data:/data" default silently mounted an
        # empty host directory over whatever the image ships at /data.
        prompt_optional "Volume mappings" DEFAULT_VOLUMES ""
        result=$?
        [ $result -ne $NAV_CONTINUE ] && return $result

        _bad=""
        if [ -n "$DEFAULT_VOLUMES" ]; then
            _vols=()
            IFS=',' read -ra _vols <<< "$DEFAULT_VOLUMES"
            for _vol in "${_vols[@]}"; do
                [ -z "$_vol" ] && continue
                _host="${_vol%%:*}"
                for _root in "${_sensitive_roots[@]}"; do
                    if [ "$_host" = "$_root" ] || [[ "$_host" == "$_root"/* ]]; then
                        _bad="$_host"
                        break 2
                    fi
                done
            done
        fi

        [ -z "$_bad" ] && break

        print_error "Host path '$_bad' is a protected system location; the generator rejects it."
        print_info "Mounting the Docker socket or a system directory is a container-escape vector."
        print_info "Use an app-data path instead, e.g. /opt/${APPLIANCE_NAME:-app} or /srv/${APPLIANCE_NAME:-app}."
        # Clear it so pressing Enter does not re-submit the rejected value.
        DEFAULT_VOLUMES=""
    done

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

    # CONFIRM is a global and prompt_yes_no reuses its current value as the next
    # default. After one "n" it would stay "false", so pressing Enter at the
    # summary bounces back to step 6 forever and the documented "[Enter] Next"
    # could never generate. Reset it before every prompt.
    CONFIRM=""
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

# On a failure path, keep the temporary spec instead of letting the EXIT trap
# delete it, and print where it is. The old handler claimed "Your inputs were
# not lost" while `trap 'rm -f "$WIZARD_ENV_FILE"' EXIT` destroyed all 7 steps of
# input and never showed the path.
#
# The spec deliberately stays in $TMPDIR (mode 600) instead of being copied into
# the repository: DEFAULT_ENV_VARS may hold secrets and `*.env` is NOT gitignored
# here (examples/*.env are committed), so a copy inside the tree could be picked
# up by `git add -A`. See SECR-4 above.
preserve_spec() {
    local spec="$1"
    WIZARD_ENV_FILE=""   # disarm the EXIT trap's `rm -f` for this file
    print_info "Your answers were saved to: ${spec}"
    print_info "It is mode 600 and outside the git tree because it may contain the"
    print_info "environment variables you entered. Delete it once you are done."
}

generate_appliance() {
    clear_screen
    print_header

    echo -e "  Generating appliance files..."
    echo ""

    # SECR-4: write the temporary spec via mktemp (mode 600) OUTSIDE the git
    # tree, and remove it on exit. DEFAULT_ENV_VARS may hold secrets, so the
    # file must not be world-readable or left behind in a committed directory.
    # REG-3: store the path in the SCRIPT-scope WIZARD_ENV_FILE (not a `local`)
    # so the global EXIT trap set above actually removes it on normal exit. The
    # trap already restores the cursor/tty, so we do NOT re-arm it here.
    WIZARD_ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/oneapp-wizard.XXXXXX.env")"
    local env_file="$WIZARD_ENV_FILE"
    chmod 600 "$env_file"

    if [ -n "${DEFAULT_ENV_VARS}" ]; then
        print_warning "Environment variables may contain secrets; they are written only to a temporary file and are not committed."
    fi

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
ENVEOF

    if [ -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
        # The generator refuses to overwrite an existing appliance without
        # --force. The wizard had no way to pass it, so a second run for the
        # same name (common after a failed build, and unavoidable after a
        # partially completed generation) was a permanent dead end. Detect the
        # collision here and ask for the overwrite explicitly.
        local gen_args=("$env_file" --no-build)
        if [ -e "${REPO_ROOT}/appliances/${APPLIANCE_NAME}" ] || \
           [ -e "${REPO_ROOT}/apps-code/community-apps/packer/${APPLIANCE_NAME}" ]; then
            print_warning "Appliance '${APPLIANCE_NAME}' already exists and would be replaced."
            if [ -t 0 ]; then
                OVERWRITE=""
                # generate_appliance is called as a plain command, so `set -e` is
                # ACTIVE here. prompt_yes_no returns NAV_BACK(1)/NAV_QUIT(2) when
                # the user types the documented `:b`/`:q`, and errexit would turn
                # that into a silent exit with no message at all. Swallow the nav
                # code and treat it as "do not overwrite".
                prompt_yes_no "Overwrite the existing appliance?" OVERWRITE "false" || OVERWRITE="false"
                if [ "$OVERWRITE" != "true" ]; then
                    echo ""
                    print_error "Aborted. Choose a different appliance name and re-run."
                    preserve_spec "$env_file"
                    return 1
                fi
            else
                echo ""
                print_error "Aborted: '${APPLIANCE_NAME}' exists and stdin is not a terminal."
                print_info "Re-run non-interactively with:"
                print_info "  ./generate-docker-appliance.sh <spec>.env --force --no-build"
                preserve_spec "$env_file"
                return 1
            fi
            gen_args+=(--force)
        fi

        # REG-2: guard the generator call. The wizard runs under `set -e`, so an
        # unguarded non-zero exit would abort mid-flow (skipping the success
        # message and firing the EXIT trap) with only a raw generator [ERROR].
        # Surface the failure gracefully and keep the collected spec available.
        if ! "${SCRIPT_DIR}/generate-docker-appliance.sh" "${gen_args[@]}"; then
            echo ""
            print_error "Appliance generation failed (see the [ERROR] above)."
            preserve_spec "$env_file"
            print_info "Fix the reported issue (commonly an unpinned Docker image, a"
            print_info "sensitive default volume, or an appliance name already in use),"
            print_info "then re-run:"
            print_info "  ./generate-docker-appliance.sh '${env_file}' --no-build"
            # NOT $NAV_CONTINUE (0): returning 0 made the wizard exit 0 after a
            # hard generator failure, so callers and CI saw a false success.
            return 1
        fi

        echo ""
        echo -e "  ${GREEN}✓ Appliance created successfully!${NC}"
        echo ""
        echo -e "  ${WHITE}Files:${NC}"
        echo -e "    appliances/${APPLIANCE_NAME}/"
        echo -e "    apps-code/community-apps/packer/${APPLIANCE_NAME}/"
        echo -e "    apps-code/community-apps/Makefile.config ${DIM}(modified: ${APPLIANCE_NAME} added to SERVICES)${NC}"
        echo ""
        echo -e "  ${WHITE}Next:${NC}"
        echo -e "    1. Review generated files"
        echo -e "    2. Build: ${CYAN}cd apps-code/community-apps && sudo make ${APPLIANCE_NAME}${NC}"
        echo -e "       ${DIM}(needs root: the build chroots. The base OS image is never built"
        echo -e "        for you — if you skipped it: cd apps-code/one-apps && sudo make ${BASE_OS:-<base-os>})${NC}"
        echo -e "    3. Add logo: ${CYAN}logos/${APPLIANCE_NAME}.png${NC}"
        echo -e "    4. Submit PR — ${WHITE}commit Makefile.config too${NC}, otherwise"
        echo -e "       ${DIM}'make ${APPLIANCE_NAME}' is not a valid target for reviewers${NC}"
        echo ""

        # TTY GUARD: generate_appliance() is called as a plain command, so
        # `set -e` is ACTIVE here. On a non-interactive stdin `read` returns
        # non-zero and errexit would kill the wizard with exit 1 even though
        # generation SUCCEEDED. Mirror the guard the generator already uses
        # (`if [ -t 0 ]; then read ...; else REPLY="n"; fi`).
        BUILD_NOW="false"
        if [ -t 0 ]; then
            # `|| BUILD_NOW="false"` for the same errexit reason as the overwrite
            # prompt above: typing `:b`/`:q` here makes prompt_yes_no return a nav
            # code, which under the ACTIVE errexit would kill the wizard with a
            # bare exit 1 immediately after generation SUCCEEDED. Treat it as "no".
            prompt_yes_no "Build now?" BUILD_NOW "false" || BUILD_NOW="false"
        else
            print_info "Non-interactive session: skipping the build prompt."
            print_info "  Build later with: cd ${REPO_ROOT}/apps-code/community-apps && sudo make ${APPLIANCE_NAME}"
        fi

        if [ "$BUILD_NOW" = "true" ]; then
            echo ""
            echo -e "  Building... ${DIM}(~2 min)${NC}"
            cd "${REPO_ROOT}/apps-code/community-apps"
            if ! make "$APPLIANCE_NAME"; then
                echo ""
                print_error "Build failed. See the make output above."
                print_info "Retry with: cd ${REPO_ROOT}/apps-code/community-apps && sudo make ${APPLIANCE_NAME}"
                return 1
            fi
            print_success "Image built: ${REPO_ROOT}/apps-code/community-apps/export/${APPLIANCE_NAME}.qcow2"
        fi
    else
        print_error "Generator not found"
        preserve_spec "$env_file"
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
    echo -e "    ${CYAN}1.${NC} Build it now ${DIM}(~3 min, recommended)${NC}"
    echo -e "    ${CYAN}2.${NC} Continue anyway ${DIM}(build manually later)${NC}"
    echo -e "    ${CYAN}3.${NC} Go back and choose a different base OS"
    echo ""

    local choice
    local _bi_rc
    while true; do
        echo -ne "  ${WHITE}›${NC} Choose [1-3]: "
        # EOF GUARD (see abort_on_eof): with a non-interactive stdin `read`
        # returns non-zero and leaves $choice empty, which falls through to the
        # `*)` branch below and re-prompts forever ("Invalid choice." in an
        # unbounded loop).
        _bi_rc=0
        read -r choice || _bi_rc=$?
        if [ $_bi_rc -ne 0 ] && [ -z "$choice" ]; then
            abort_on_eof \
                "Build the base image first, then re-run the wizard:" \
                "  cd ${REPO_ROOT}/apps-code/one-apps && sudo make ${BASE_OS}"
        fi
        case "$choice" in
            1)
                echo ""
                echo -e "  ${BRIGHT_CYAN}Building ${base_os_display} base image...${NC}"
                echo -e "  ${DIM}This usually takes about 3 minutes${NC}"
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
                    echo -e "  ${DIM}You can try building it manually (needs root — the build chroots):${NC}"
                    echo -e "  ${CYAN}cd ${REPO_ROOT}/apps-code/one-apps && sudo make ${BASE_OS}${NC}"
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
                echo -e "  ${DIM}Remember to build it before building the appliance"
                echo -e "  ('make ${APPLIANCE_NAME}' never builds the base image for you):${NC}"
                echo -e "  ${CYAN}cd ${REPO_ROOT}/apps-code/one-apps && sudo make ${BASE_OS}${NC}"
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

# Preflight: everything the wizard needs before it offers to run `make`.
preflight_checks() {
    local warned=false

    # Check if we're in the right directory
    if [ ! -f "${SCRIPT_DIR}/generate-docker-appliance.sh" ]; then
        echo -e "${RED}Error: This script must be run from the automatic-appliance-tutorial directory.${NC}"
        echo -e "Please cd to: ${SCRIPT_DIR}"
        exit 1
    fi

    # PREFLIGHT 1 - host OS. The generator registers the appliance in
    # apps-code/community-apps/Makefile.config with GNU `sed -i`; BSD/macOS sed
    # fails there ("extra characters at the end of p command") AFTER every file
    # has been written, leaving a half-created tree that then needs --force.
    if [ "$(uname -s)" != "Linux" ]; then
        print_error "This wizard must run on Linux: the generator needs GNU sed and the"
        print_error "image build needs KVM. Detected: $(uname -s)."
        exit 1
    fi

    # PREFLIGHT 2 - submodules. Without them apps-code/one-apps is empty and
    # apps-code/community-apps/packer/build.sh is a dangling symlink, so every
    # `make <target>` fails immediately.
    if [ ! -f "${REPO_ROOT}/apps-code/one-apps/packer/build.sh" ]; then
        print_warning "Git submodules are not initialized (apps-code/one-apps is empty)."
        print_info "Initializing: git submodule update --init --recursive"
        if ! git -C "${REPO_ROOT}" submodule update --init --recursive; then
            print_error "Submodule init failed. Run it manually from ${REPO_ROOT}:"
            print_error "  git submodule update --init --recursive"
            exit 1
        fi
        print_success "Submodules initialized."
        warned=true
    fi

    # PREFLIGHT 3 - build capability. Generation works without these; only the
    # optional `make` steps need them, so warn rather than abort.
    if [ "$(id -u)" -ne 0 ]; then
        print_warning "Not running as root: image builds (which chroot) will fail."
        print_info "Generation still works. To build, re-run the wizard with sudo."
        warned=true
    fi
    if [ ! -e /dev/kvm ]; then
        print_warning "/dev/kvm is missing: Packer cannot build VM images on this host."
        print_info "Generation still works; build on a KVM-capable host."
        warned=true
    fi

    # The first step clears the screen, so give the reader a moment.
    [ "$warned" = "true" ] && sleep 3
    return 0
}

# Main wizard flow with navigation support
main() {
    preflight_checks

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
                # Go back to OS selection (step 2)
                current=2  # step_base_os index
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

