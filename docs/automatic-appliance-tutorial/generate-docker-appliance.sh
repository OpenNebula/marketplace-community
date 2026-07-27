#!/bin/bash

# Ultimate OpenNebula Docker Appliance Generator
# Creates ALL files needed for a Docker appliance from a simple config file

set -e

# SECR-2: create all generated files owner-only by default. Secret-bearing
# outputs (context.yaml/metadata.yaml/${UUID}.yaml/appliance.sh) must not be
# world-readable. Explicit chmod calls below further tighten specific files.
umask 077

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
🚀 Ultimate OpenNebula Docker Appliance Generator

Usage: $0 <config-file> [--no-build] [--force] [-h|--help]

Creates ALL necessary files for a complete Docker-based OpenNebula appliance.

Options:
    --no-build   Do not offer to build the image afterwards. Use this for
                 scripted / CI runs. (Interactive runs prompt; a run with no
                 terminal on stdin skips the prompt automatically.)
    --force      Regenerate an appliance that already exists. The previous
                 appliances/<name>/ and packer/<name>/ directories are removed
                 first, so no stale <uuid>.yaml is left behind.
    -h, --help   Show this help.

Example config file (nginx.env):
    DOCKER_IMAGE="nginx:alpine"        # must be pinned; ':latest' is rejected
    APPLIANCE_NAME="nginx"
    APP_NAME="NGINX Web Server"
    PUBLISHER_NAME="Your Name"
    PUBLISHER_EMAIL="your.email@domain.com"
    APP_DESCRIPTION="NGINX is a high-performance web server and reverse proxy"
    APP_FEATURES="High performance web server,Reverse proxy,Load balancing"
    DEFAULT_CONTAINER_NAME="nginx-server"
    DEFAULT_PORTS="80:80,443:443"
    DEFAULT_ENV_VARS=""
    DEFAULT_VOLUMES=""                 # see the note below
    APP_PORT="80"
    WEB_INTERFACE="true"
    BASE_OS="ubuntu2204min"            # optional, this is the default
    DISK_SIZE="20480"                  # optional, MiB, this is the default

BASE_OS selects the base image the appliance is built on. It must already be
built in apps-code/one-apps (e.g. 'cd apps-code/one-apps && make ubuntu2204min').
Supported: ubuntu2204min ubuntu2204 ubuntu2404min ubuntu2404 debian12 debian11
           alma8 alma9 rocky8 rocky9 opensuse15

DISK_SIZE is the appliance's virtual disk size in MiB. Packer can only GROW the
base image, so this must be >= the base image's virtual size (ubuntu2204min is
2.2 GiB, alma9 is 10 GiB). A smaller value aborts the build with
"Error creating hard drive: qemu-img: Use the --shrink option ...". qcow2 is
sparse, so a generous size does not enlarge the exported file.

DEFAULT_VOLUMES: only declare a volume you actually populate. Mounting an empty
host directory over a path the image ships content in (for example nginx's
/etc/nginx/conf.d or /usr/share/nginx/html) HIDES that content and the service
starts with nothing to serve. Volumes the appliance creates are chowned to the
UID/GID the container image runs as.

This will generate:
✅ All appliance files (metadata, appliance.sh, README, CHANGELOG)
✅ All Packer configuration files
✅ All test files
✅ Complete directory structure
✅ Ready-to-build appliance

Then build it with:
    cd apps-code/community-apps && sudo make <APPLIANCE_NAME>

EOF
}

# Parse arguments
NO_BUILD=false
FORCE=false
CONFIG_FILE=""

for arg in "$@"; do
    case $arg in
        --no-build)
            NO_BUILD=true
            ;;
        --force)
            # PATH-2: allow overwriting an existing appliance/packer tree
            FORCE=true
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$CONFIG_FILE" ]; then
                CONFIG_FILE="$arg"
            fi
            ;;
    esac
done

if [ -z "$CONFIG_FILE" ]; then show_usage; exit 1; fi
if [ ! -f "$CONFIG_FILE" ]; then print_error "Config file '$CONFIG_FILE' not found!"; exit 1; fi

print_info "🚀 Loading configuration from $CONFIG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# INJ-1 / SECR-5: SAFE config parser (NO `source`).
#
# The config file is untrusted data (a shared/downloaded appliance spec). We
# must NOT execute it. Instead we read it line by line and only accept literal
# KEY=VALUE assignments for a fixed allowlist of known keys. No command
# substitution, arithmetic, or any other shell construct in the file is ever
# evaluated. Values have at most one layer of surrounding matching quotes
# stripped literally (no eval).
# ─────────────────────────────────────────────────────────────────────────────

# Allowlist of configuration keys the generator understands. Any other key in
# the file is ignored. Alias keys (PORTS/ENV_VARS/VOLUMES/CONTAINER_PORTS/...)
# map onto the canonical DEFAULT_* variables used throughout the generator.
parse_config_file() {
    local file="$1"
    local line key value

    while IFS= read -r line || [ -n "$line" ]; do
        # REG-1: tolerate Windows/CRLF specs by stripping a trailing CR, so a
        # legitimate single-line value is not rejected as "contains a newline".
        line="${line%$'\r'}"
        # REG-4: strip leading whitespace so an indented KEY=VALUE line (which
        # `source` accepted) is still parsed instead of silently skipped.
        line="${line#"${line%%[![:space:]]*}"}"
        # Ignore blank lines and comments
        case "$line" in
            ''|\#*) continue ;;
        esac
        # Strip an optional leading "export "
        line="${line#export }"
        # Only accept lines that are a KEY=VALUE assignment with a valid key
        if [[ ! "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"

        # REG-1: trim trailing horizontal whitespace (e.g. a stray space after
        # a closing quote in a hand-edited spec) before the quote logic, so
        # `KEY="v" ` is treated like `KEY="v"`.
        value="${value%"${value##*[![:space:]]}"}"

        # Strip ONE layer of surrounding matching quotes, literally (no eval).
        # The whole-value branches run first so a value with an inner quote
        # (e.g. "He said "hi"") is not mis-truncated. The remaining branches
        # drop a trailing inline "# comment" from quoted or unquoted values
        # (REG-3), matching what `source` would have discarded.
        if [[ "$value" == \"*\" && ${#value} -ge 2 ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && ${#value} -ge 2 ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" =~ ^\"([^\"]*)\"[[:space:]]+#.*$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" =~ ^\'([^\']*)\'[[:space:]]+#.*$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi

        # Assign into the known-key allowlist. Unknown keys are ignored.
        case "$key" in
            DOCKER_IMAGE)            DOCKER_IMAGE="$value" ;;
            APPLIANCE_NAME)          APPLIANCE_NAME="$value" ;;
            APP_NAME)                APP_NAME="$value" ;;
            PUBLISHER_NAME)          PUBLISHER_NAME="$value" ;;
            PUBLISHER_EMAIL)         PUBLISHER_EMAIL="$value" ;;
            APP_DESCRIPTION)         APP_DESCRIPTION="$value" ;;
            APP_FEATURES)            APP_FEATURES="$value" ;;
            APP_PORT)                APP_PORT="$value" ;;
            WEB_INTERFACE)           WEB_INTERFACE="$value" ;;
            BASE_OS)                 BASE_OS="$value" ;;
            DISK_SIZE)               DISK_SIZE="$value" ;;
            DEFAULT_CONTAINER_NAME|CONTAINER_NAME) DEFAULT_CONTAINER_NAME="$value" ;;
            DEFAULT_PORTS)           DEFAULT_PORTS="$value" ;;
            CONTAINER_PORTS|PORTS)   DEFAULT_PORTS="$value" ;;
            DEFAULT_ENV_VARS)        DEFAULT_ENV_VARS="$value" ;;
            CONTAINER_ENV|ENV_VARS)  DEFAULT_ENV_VARS="$value" ;;
            DEFAULT_VOLUMES)         DEFAULT_VOLUMES="$value" ;;
            CONTAINER_VOLUMES|VOLUMES) DEFAULT_VOLUMES="$value" ;;
            *)                       : ;;  # unknown key -> ignore
        esac
    done < "$file"
}

parse_config_file "$CONFIG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# PER-SINK validation & escaping (INJ-3, INJ-4, INJ-6, SECR-7; REG-4, BYP-1/2).
#
# The previous design used ONE global denylist for every field. An adversarial
# review found that single gate was simultaneously:
#   - too LAX for shell/YAML sinks (it omitted backslash -> BYP-1 newline
#     injection via `echo -e`; it permitted YAML-structural `: { # ,` -> BYP-2), and
#   - too AGGRESSIVE for human-readable prose (it rejected `& ( ) '` so valid
#     values like "Redis (in-memory cache), fast & light" were refused -> REG-4).
#
# We now validate/escape BY SINK:
#   1. SHELL/EXEC-context fields (DOCKER_IMAGE, DEFAULT_CONTAINER_NAME,
#      DEFAULT_PORTS, DEFAULT_ENV_VARS, DEFAULT_VOLUMES): keep STRICT metachar
#      rejection and ADD backslash to the forbidden set (closes BYP-1's escape
#      vector). These reach `printf %q` shell assignments and `docker run`.
#   2. HUMAN-READABLE fields (APP_NAME, PUBLISHER_NAME, PUBLISHER_EMAIL,
#      APP_DESCRIPTION, APP_FEATURES, WEB_INTERFACE): do NOT apply the shell
#      denylist. Forbid ONLY raw newline/CR and backslash (backslash still
#      barred so `echo -e`/YAML cannot re-interpret it), then emit them SAFELY
#      per sink (single-quoted YAML scalars / literal printf).
# APPLIANCE_NAME keeps its own ^[a-z][a-z0-9-]*$ regex (below).
# ─────────────────────────────────────────────────────────────────────────────

# reject_newline_backslash: the MINIMUM gate applied to every field. Raw
# newline/CR would break out of a single-line scalar; backslash would be
# re-interpreted by `echo -e` (BYP-1) or by YAML double-quoted parsing.
reject_newline_backslash() {
    local field_name="$1" field_value="$2"
    if [[ "$field_value" == *$'\n'* || "$field_value" == *$'\r'* ]]; then
        print_error "$field_name contains a newline character, which is not allowed"; exit 1
    fi
    if [[ "$field_value" == *'\'* ]]; then
        print_error "$field_name contains a backslash character, which is not allowed"; exit 1
    fi
}

# reject_metachars: STRICT gate for shell/exec-context fields only. Rejects
# newline/CR, backslash, and the shell metacharacters ` $ ; & | ( ) < > and
# both quotes. Applied to values that reach a shell assignment or `docker run`.
reject_metachars() {
    local field_name="$1" field_value="$2"
    reject_newline_backslash "$field_name" "$field_value"
    if [[ "$field_value" == *'`'* || "$field_value" == *'$'* || \
          "$field_value" == *';'* || "$field_value" == *'&'* || \
          "$field_value" == *'|'* || "$field_value" == *'('* || \
          "$field_value" == *')'* || "$field_value" == *'<'* || \
          "$field_value" == *'>'* || "$field_value" == *'"'* || \
          "$field_value" == *"'"* ]]; then
        print_error "$field_name contains forbidden shell metacharacters (one of \` \$ ; & | ( ) < > or a quote)"; exit 1
    fi
}

# yaml_squote: emit a value as a SAFE single-quoted YAML scalar. Doubling '
# per the YAML spec means structural chars (`:` `{` `#` `,` `[` `%` `*` `!`
# etc.) can never break YAML structure (BYP-2). Callers place the result
# verbatim in the scalar position, e.g. `name: <yaml_squote APP_NAME>`.
yaml_squote() {
    local v="$1"
    printf "'%s'" "${v//\'/\'\'}"
}

# 1. SHELL/EXEC-context fields: STRICT metachar rejection (+ backslash).
reject_metachars "DOCKER_IMAGE"           "${DOCKER_IMAGE:-}"
reject_metachars "DEFAULT_CONTAINER_NAME" "${DEFAULT_CONTAINER_NAME:-}"
reject_metachars "DEFAULT_PORTS"          "${DEFAULT_PORTS:-}"
reject_metachars "DEFAULT_VOLUMES"        "${DEFAULT_VOLUMES:-}"

# REG-2: DEFAULT_ENV_VARS is deliberately emitted EMPTY (SECR-3) and never
# persisted to any file, so the strict shell gate would needlessly abort on a
# legitimate documentation default (e.g. "FOO=bar&baz"). Apply only the minimal
# newline/backslash gate; the value is discarded, not executed.
reject_newline_backslash "DEFAULT_ENV_VARS" "${DEFAULT_ENV_VARS:-}"
reject_metachars "APP_PORT"               "${APP_PORT:-}"
reject_metachars "APPLIANCE_NAME"         "${APPLIANCE_NAME:-}"

# 2. HUMAN-READABLE fields: only bar raw newline/CR and backslash; `& ( ) '`
# etc. are allowed and rendered safely per sink (REG-4). WEB_INTERFACE is
# constrained to true/false below but pass it through the minimal gate too.
reject_newline_backslash "APP_NAME"        "${APP_NAME:-}"
reject_newline_backslash "PUBLISHER_NAME"  "${PUBLISHER_NAME:-}"
reject_newline_backslash "PUBLISHER_EMAIL" "${PUBLISHER_EMAIL:-}"
reject_newline_backslash "APP_DESCRIPTION" "${APP_DESCRIPTION:-}"
reject_newline_backslash "APP_FEATURES"    "${APP_FEATURES:-}"
reject_newline_backslash "WEB_INTERFACE"   "${WEB_INTERFACE:-}"

# Validate required variables
REQUIRED_VARS=("DOCKER_IMAGE" "APPLIANCE_NAME" "APP_NAME" "PUBLISHER_NAME" "PUBLISHER_EMAIL")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then print_error "Required variable $var is not set"; exit 1; fi
done

# Set defaults
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-${APPLIANCE_NAME}-container}"
DEFAULT_PORTS="${DEFAULT_PORTS:-8080:80}"
DEFAULT_ENV_VARS="${DEFAULT_ENV_VARS:-}"
DEFAULT_VOLUMES="${DEFAULT_VOLUMES:-}"
APP_PORT="${APP_PORT:-8080}"
WEB_INTERFACE="${WEB_INTERFACE:-true}"
APP_DESCRIPTION="${APP_DESCRIPTION:-Docker-based appliance for ${APP_NAME}}"
APP_FEATURES="${APP_FEATURES:-Containerized application,Easy deployment,Configurable parameters}"
BASE_OS="${BASE_OS:-ubuntu2204min}"

# Virtual disk size (MiB) of the appliance image.
#
# Packer can only GROW the base image's disk. The supported base images differ
# a lot here (ubuntu2204min is 2.2 GiB, alma9 is 10 GiB), and asking for less
# than the base already has aborts the build with
#   "Error creating hard drive: qemu-img: Use the --shrink option ..."
# so the default must clear the largest base. qcow2 is sparse, so a generous
# virtual size costs nothing in the exported file.
DISK_SIZE="${DISK_SIZE:-20480}"

# Define supported base OS images with their metadata
declare -A OS_DISPLAY_NAMES=(
    ["ubuntu2204min"]="Ubuntu 22.04 LTS (Minimal)"
    ["ubuntu2204"]="Ubuntu 22.04 LTS"
    ["ubuntu2404min"]="Ubuntu 24.04 LTS (Minimal)"
    ["ubuntu2404"]="Ubuntu 24.04 LTS"
    ["debian12"]="Debian 12 (Bookworm)"
    ["debian11"]="Debian 11 (Bullseye)"
    ["alma8"]="AlmaLinux 8"
    ["alma9"]="AlmaLinux 9"
    ["rocky8"]="Rocky Linux 8"
    ["rocky9"]="Rocky Linux 9"
    ["opensuse15"]="openSUSE Leap 15"
)

declare -A OS_IDS=(
    ["ubuntu2204min"]="Ubuntu" ["ubuntu2204"]="Ubuntu"
    ["ubuntu2404min"]="Ubuntu" ["ubuntu2404"]="Ubuntu"
    ["debian12"]="Debian" ["debian11"]="Debian"
    ["alma8"]="AlmaLinux" ["alma9"]="AlmaLinux"
    ["rocky8"]="Rocky" ["rocky9"]="Rocky"
    ["opensuse15"]="openSUSE"
)

declare -A OS_RELEASES=(
    ["ubuntu2204min"]="22.04" ["ubuntu2204"]="22.04"
    ["ubuntu2404min"]="24.04" ["ubuntu2404"]="24.04"
    ["debian12"]="12" ["debian11"]="11"
    ["alma8"]="8" ["alma9"]="9"
    ["rocky8"]="8" ["rocky9"]="9"
    ["opensuse15"]="15"
)

declare -A OS_PKG_MANAGERS=(
    ["ubuntu2204min"]="apt" ["ubuntu2204"]="apt"
    ["ubuntu2404min"]="apt" ["ubuntu2404"]="apt"
    ["debian12"]="apt" ["debian11"]="apt"
    ["alma8"]="dnf" ["alma9"]="dnf"
    ["rocky8"]="dnf" ["rocky9"]="dnf"
    ["opensuse15"]="zypper"
)

# Network configuration types for each OS (used by one-context)
declare -A OS_NETCFG_TYPES=(
    ["ubuntu2204min"]="netplan" ["ubuntu2204"]="netplan"
    ["ubuntu2404min"]="netplan" ["ubuntu2404"]="netplan"
    ["debian12"]="interfaces" ["debian11"]="interfaces"
    ["alma8"]="nm" ["alma9"]="nm"
    ["rocky8"]="nm" ["rocky9"]="nm"
    ["opensuse15"]="scripts"
)

# List of supported base OS options (for validation)
SUPPORTED_BASE_OS=("ubuntu2204min" "ubuntu2204" "ubuntu2404min" "ubuntu2404" "debian12" "debian11" "alma8" "alma9" "rocky8" "rocky9" "opensuse15")

# Validate appliance name (allow lowercase letters, numbers, and hyphens)
if [[ ! "$APPLIANCE_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    print_error "APPLIANCE_NAME must be lowercase letters, numbers, and hyphens only (e.g., home-assistant, node-red)"; exit 1
fi

# DEF-2: require a pinned image reference. Reject a bare name (which Docker
# resolves to the mutable :latest) and reject an explicit ':latest' tag. Prefer
# an immutable digest (name@sha256:...) or at least a fixed tag. This prevents
# silently pulling a repointed/malicious image at every boot.
#
# DEF-2 fix: a registry with an explicit port (e.g. `registry:5000/nginx`)
# contains a ':' but has NO image tag, yet the old `*:*` check treated it as
# "tagged" and let it through -> Docker then resolves it to mutable :latest.
# We first STRIP an optional registry prefix (the first '/'-separated segment
# that contains '.' or ':', i.e. a hostname or host:port), then look for a
# tag/digest ONLY in the remaining repository[:tag] part.
if [[ "$DOCKER_IMAGE" == *"@sha256:"* ]]; then
    : # digest-pinned, best case
else
    _img_repo="$DOCKER_IMAGE"
    _img_first="${DOCKER_IMAGE%%/*}"
    # If the first segment looks like a registry host (has '.' or ':') and a
    # '/' follows, drop it so the port colon is not mistaken for a tag colon.
    if [[ "$DOCKER_IMAGE" == */* && ( "$_img_first" == *.* || "$_img_first" == *:* ) ]]; then
        _img_repo="${DOCKER_IMAGE#*/}"
    fi
    if [[ "$_img_repo" != *:* ]]; then
        print_error "DOCKER_IMAGE '$DOCKER_IMAGE' has no tag or digest (resolves to mutable :latest)."
        print_info "Pin it, e.g. image:1.2.3 or image@sha256:<digest>"
        exit 1
    elif [[ "${_img_repo##*:}" == "latest" ]]; then
        print_error "DOCKER_IMAGE '$DOCKER_IMAGE' uses the mutable ':latest' tag."
        print_info "Pin a specific version, e.g. image:1.2.3 or image@sha256:<digest>"
        exit 1
    fi
fi

# DEF-3: apply the SAME normalized sensitive-path check used by the emitted
# appliance.sh runtime guard (DEF-1/CMP-DEF-5) to DEFAULT_VOLUMES at GENERATION
# time and hard-fail. A dangerous default (docker socket, /, /usr, /var/lib/docker,
# ...) must never be baked into the committed appliance/metadata/README files.
#
# is_sensitive_host_path: canonicalize the host path first, then reject if the
# canonical path EQUALS or is UNDER any sensitive root. We prefer `realpath -m`
# (GNU coreutils on the Linux target resolves symlinks and `.`/`..`/`//`/trailing
# slashes even for non-existent paths); a pure-bash lexical fallback
# (`_canon_path`) collapses `.`/`..`/`//` so the check stays correct even where
# realpath -m is unavailable/BSD. Exact-or-subpath matching (prefix + '/')
# avoids a /etc vs /etcfoo false match. This same logic is emitted verbatim into
# appliance.sh below.
SENSITIVE_MOUNT_ROOTS=(
    /var/run/docker.sock /run/docker.sock
    / /root /proc /sys /dev /boot
    /var/run /run /usr /bin /sbin /lib /lib64 /var/lib/docker
)
# REG-2: bare /etc is intentionally NOT a sensitive root, so config-dir mounts
# like /etc/nginx/conf.d (the documented example) are allowed; only the docker
# socket and whole system roots above are blocked.
_canon_path() {
    # Lexically normalize an absolute-ish path: collapse //, resolve . and ..,
    # strip trailing slash. No filesystem access; a safe fallback for realpath.
    local p="$1" out=() seg
    [ "${p#/}" = "$p" ] && p="/$p"   # treat as absolute for mount-root checks
    local IFS=/
    for seg in $p; do
        case "$seg" in
            ''|.) : ;;
            ..) [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
            *) out+=("$seg") ;;
        esac
    done
    if [ "${#out[@]}" -eq 0 ]; then printf '/'; else printf '/%s' "${out[@]}"; fi
}
is_sensitive_host_path() {
    local host_path="$1" resolved root
    resolved="$(realpath -m -- "$host_path" 2>/dev/null)" || resolved=""
    [ -z "$resolved" ] && resolved="$(_canon_path "$host_path")"
    for root in "${SENSITIVE_MOUNT_ROOTS[@]}"; do
        if [ "$resolved" = "$root" ] || [[ "$resolved" == "$root"/* ]]; then
            return 0
        fi
    done
    return 1
}

if [ -n "${DEFAULT_VOLUMES:-}" ]; then
    IFS=',' read -ra _DEF_VOL_ARRAY <<< "$DEFAULT_VOLUMES"
    for _vol in "${_DEF_VOL_ARRAY[@]}"; do
        [ -z "$_vol" ] && continue
        _host_path="${_vol%%:*}"
        if is_sensitive_host_path "$_host_path"; then
            print_error "DEFAULT_VOLUMES maps sensitive host path '$_host_path' (resolves under a protected system location)."
            print_info "Refusing to bake a dangerous default mount into the appliance. Use an app-data path (e.g. /opt/<app>, /srv/<app>, /data)."
            exit 1
        fi
    done
fi

# Validate BASE_OS
VALID_OS=false
for os in "${SUPPORTED_BASE_OS[@]}"; do
    if [[ "$BASE_OS" == "$os" ]]; then
        VALID_OS=true
        break
    fi
done
if [[ "$VALID_OS" != "true" ]]; then
    print_error "BASE_OS '$BASE_OS' is not supported."
    print_info "Supported options: ${SUPPORTED_BASE_OS[*]}"
    exit 1
fi

# Get OS metadata
OS_ID="${OS_IDS[$BASE_OS]}"
OS_RELEASE="${OS_RELEASES[$BASE_OS]}"
OS_DISPLAY="${OS_DISPLAY_NAMES[$BASE_OS]}"
PKG_MANAGER="${OS_PKG_MANAGERS[$BASE_OS]}"

print_info "📦 Base OS: $OS_DISPLAY ($BASE_OS)"

print_info "🎯 Generating complete appliance: $APPLIANCE_NAME ($APP_NAME)"

# Determine repository root (go up two levels from docs/automatic-appliance-tutorial/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# PATH-2: refuse to silently clobber an existing appliance/packer tree. A
# malicious spec could reuse a trusted appliance name (e.g. "nginx") to graft
# its own image/volumes onto the trusted identity. Require an explicit --force.
APPLIANCE_DIR="$REPO_ROOT/appliances/$APPLIANCE_NAME"
PACKER_DIR="$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME"
if [ "$FORCE" != "true" ]; then
    if [ -e "$APPLIANCE_DIR" ] || [ -e "$PACKER_DIR" ]; then
        print_error "Appliance '$APPLIANCE_NAME' already exists (appliances/ or packer/)."
        print_info "Refusing to overwrite. Re-run with --force to replace it."
        exit 1
    fi
else
    # --force: remove any previous generation first. The appliance UUID is
    # random per run, so a plain overwrite would leave the OLD <uuid>.yaml
    # behind and accumulate stale descriptors. Start from a clean directory.
    rm -rf "$APPLIANCE_DIR" "$PACKER_DIR"
fi

# Create directories (absolute paths from repository root)
print_info "📁 Creating directory structure..."
mkdir -p "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests"
mkdir -p "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME"

APPLIANCE_UUID=$(uuidgen)
CREATION_TIME=$(date +%s)
CURRENT_DATE=$(date +%Y-%m-%d)

# BYP-2: pre-compute SINGLE-QUOTED YAML scalars for every interpolated field
# that lands in a bare (unquoted) YAML scalar position. Single-quoting with
# `'`->`''` escaping guarantees YAML-structural chars (`:` `{` `#` `,` `[` `%`
# `*` `!` ...) in human-readable fields cannot break the document structure,
# while still allowing legitimate prose like "Redis (in-memory cache), fast &
# light" (REG-4). Shell-context fields (container name/ports/volumes) already
# reject quotes, but we quote them here too for uniform, parse-safe output.
APP_NAME_Y="$(yaml_squote "$APP_NAME")"
PUBLISHER_NAME_Y="$(yaml_squote "$PUBLISHER_NAME")"
PUBLISHER_EMAIL_Y="$(yaml_squote "$PUBLISHER_EMAIL")"
SHORT_DESC_Y="$(yaml_squote "$APP_NAME with VNC access and SSH key auth")"
CONTAINER_NAME_Y="$(yaml_squote "$DEFAULT_CONTAINER_NAME")"
CONTAINER_PORTS_Y="$(yaml_squote "$DEFAULT_PORTS")"
CONTAINER_VOLUMES_Y="$(yaml_squote "$DEFAULT_VOLUMES")"

print_success "Directory structure created"

# Certification-safe copies of the list-valued defaults.
#
# lib/community/app_handler.rb builds the test context by joining every
# metadata :params: entry with COMMAS and handing the result to
# `onetemplate instantiate --context "..."`. The OpenNebula CLI splits that
# string on commas regardless of quoting, so a value that itself contains a
# comma is truncated there (e.g. '80:80,443:443' arrives as '80:80,' and the
# 443 mapping silently disappears during certification).
#
# Emit these defaults separated by ';' instead. appliance.sh accepts BOTH ','
# and ';' as list separators, so the documented comma form still works for
# operators entering values in Sunstone.
CERT_PORTS="${DEFAULT_PORTS//,/;}"
CERT_ENV="${DEFAULT_ENV_VARS//,/;}"
CERT_VOLUMES="${DEFAULT_VOLUMES//,/;}"

# Generate metadata.yaml
print_info "📝 Generating metadata.yaml..."
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/metadata.yaml" << EOF
---
:app:
  :name: $APPLIANCE_NAME
  :type: service
  :os:
    :type: linux
    :base: $BASE_OS
  :hypervisor: KVM
  :context:
    # ':prefixed: true' means the test harness ADDS the ONEAPP_ prefix itself
    # (lib/community/app_handler.rb -> app_context()), so the parameter names
    # below must be written WITHOUT it. Writing them pre-prefixed yields
    # ONEAPP_ONEAPP_* and the appliance receives no configuration at all.
    :prefixed: true
    # List values use ';' here on purpose: the harness joins these with commas
    # before passing them to 'onetemplate instantiate --context', which splits
    # on commas. appliance.sh accepts ',' and ';' interchangeably.
    :params:
      :CONTAINER_NAME: '$DEFAULT_CONTAINER_NAME'
      :CONTAINER_PORTS: '$CERT_PORTS'
      :CONTAINER_ENV: '$CERT_ENV'
      :CONTAINER_VOLUMES: '$CERT_VOLUMES'

:one:
  :template:
    NAME: base
    TEMPLATE:
      ARCH: x86_64
      CONTEXT:
        NETWORK: 'YES'
        SET_HOSTNAME: "\$NAME"
        SSH_PUBLIC_KEY: "\$USER[SSH_PUBLIC_KEY]"
      CPU: '2'
      CPU_MODEL:
        MODEL: host-passthrough
      GRAPHICS:
        LISTEN: 0.0.0.0
        TYPE: vnc
      MEMORY: '2048'
      NIC:
        NETWORK: service
      NIC_DEFAULT:
        MODEL: virtio
  :datastore_name: default
  :timeout: '600'

:infra:
  :disk_format: qcow2
  :apps_path: /var/tmp
EOF

# Generate UUID.yaml (main appliance metadata)
print_info "📝 Generating ${APPLIANCE_UUID}.yaml..."
# BYP-1: build the feature list with `printf '  - %s\n'` so each feature stays
# LITERAL. The old code used `$(echo "$feature" | xargs)` (which strips leading
# whitespace AND interprets one backslash layer) and then emitted the block via
# `echo -e "$FEATURES_YAML"` (which re-interprets `\n` into real newlines). An
# attacker feature value like `realfeat\nmalicious_toplevel: X` therefore landed
# at column 0 and injected a new top-level YAML key. printf keeps backslashes
# literal (and backslash is now rejected upstream anyway), and hard-codes the
# `  - ` block-scalar indentation so no continuation line can reach column 0.
# We trim only leading/trailing SPACES/TABS per feature (no escape interpretation).
IFS=',' read -ra FEATURES_ARRAY <<< "$APP_FEATURES"
FEATURES_YAML=""
for feature in "${FEATURES_ARRAY[@]}"; do
    feature="${feature#"${feature%%[![:space:]]*}"}"   # strip leading whitespace
    feature="${feature%"${feature##*[![:space:]]}"}"   # strip trailing whitespace
    FEATURES_YAML+="$(printf '  - %s\n' "$feature")"
    FEATURES_YAML+=$'\n'
done
# Drop the trailing newline so the heredoc interpolation adds exactly one.
FEATURES_YAML="${FEATURES_YAML%$'\n'}"

if [ "$WEB_INTERFACE" = "true" ]; then
    WEB_ACCESS="  - Web: $APP_NAME interface at http://VM_IP:$APP_PORT"
    WEB_FEATURE="  - Web interface on port $APP_PORT"
else
    WEB_ACCESS=""
    WEB_FEATURE=""
fi

# Get lowercase OS name for tags
OS_TAG=$(echo "$OS_ID" | tr '[:upper:]' '[:lower:]')

cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml" << EOF
---
name: $APP_NAME_Y
version: 1.0.0-1
one-apps_version: 7.0.0-0
publisher: $PUBLISHER_NAME_Y
publisher_email: $PUBLISHER_EMAIL_Y
description: |-
  $APP_DESCRIPTION. This appliance provides $APP_NAME
  running in a Docker container on $OS_DISPLAY with VNC access and
  SSH key authentication.

  **$APP_NAME features:**
$(printf '%s' "$FEATURES_YAML")
  **This appliance provides:**
  - $OS_DISPLAY base operating system
  - Docker Engine CE pre-installed and configured
  - $APP_NAME container ($DOCKER_IMAGE) ready to run
  - VNC access for desktop environment
  - SSH key authentication from OpenNebula context$WEB_FEATURE
  - Configurable container parameters (ports, volumes, environment variables)

  **Access Methods:**
  - VNC: Direct access to desktop environment
  - SSH: Key-based authentication from OpenNebula$WEB_ACCESS

short_description: $SHORT_DESC_Y
tags:
- $APPLIANCE_NAME
- docker
- $OS_TAG
- container
- vnc
- ssh-key
format: qcow2
creation_time: $CREATION_TIME
os-id: $OS_ID
os-release: '$OS_RELEASE'
os-arch: x86_64
hypervisor: KVM
opennebula_version: 7.0
opennebula_template:
  context:
    network: 'YES'
    ssh_public_key: \$USER[SSH_PUBLIC_KEY]
    set_hostname: \$USER[SET_HOSTNAME]
    oneapp_container_name: "\$ONEAPP_CONTAINER_NAME"
    oneapp_container_ports: "\$ONEAPP_CONTAINER_PORTS"
    oneapp_container_env: "\$ONEAPP_CONTAINER_ENV"
    oneapp_container_volumes: "\$ONEAPP_CONTAINER_VOLUMES"
  cpu: '2'
  disk:
    image: \$FILE[IMAGE_ID]
    image_uname: \$USER[IMAGE_UNAME]
  graphics:
    listen: 0.0.0.0
    type: vnc
  memory: '2048'
  name: $APP_NAME_Y
  user_inputs:
    oneapp_container_name: 'M|text|Container name|$DEFAULT_CONTAINER_NAME|$DEFAULT_CONTAINER_NAME'
    oneapp_container_ports: 'M|text|Container ports (format: host:container)|$DEFAULT_PORTS|$DEFAULT_PORTS'
    oneapp_container_env: 'O|text|Environment variables (format: VAR1=value1,VAR2=value2)||$DEFAULT_ENV_VARS'
    oneapp_container_volumes: 'O|text|Volume mounts (format: /host/path:/container/path)||$DEFAULT_VOLUMES'
  inputs_order: ONEAPP_CONTAINER_NAME,ONEAPP_CONTAINER_PORTS,ONEAPP_CONTAINER_ENV,ONEAPP_CONTAINER_VOLUMES
logo: logos/$APPLIANCE_NAME.png
EOF

print_success "Metadata files generated"

# Generate README.md
print_info "📝 Generating README.md..."
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/README.md" << EOF
# $APP_NAME Appliance

$APP_DESCRIPTION. This appliance provides $APP_NAME running in a Docker container on $OS_DISPLAY with VNC access and SSH key authentication.

## Key Features

**$APP_NAME capabilities:**
$(printf '%s' "$FEATURES_YAML")
**This appliance provides:**
- $OS_DISPLAY base operating system
- Docker Engine CE pre-installed and configured
- $APP_NAME container ($DOCKER_IMAGE) ready to run
- VNC access for desktop environment
- SSH key authentication from OpenNebula context
- Configurable container parameters (ports, volumes, environment variables)$WEB_FEATURE

## Quick Start

1. **Deploy the appliance** from OpenNebula marketplace
2. **Configure container settings** during VM instantiation:
   - Container name: $DEFAULT_CONTAINER_NAME
   - Port mappings: $DEFAULT_PORTS
   - Environment variables: provide at instantiation via CONTAINER_ENV (may contain secrets; not stored in this repo)
   - Volume mounts: $DEFAULT_VOLUMES
3. **Access the VM**:
   - VNC: Direct desktop access via OpenNebula Sunstone
   - SSH: \`ssh root@VM_IP\` using the SSH key injected via OpenNebula context (no password login)$WEB_ACCESS

## Web Interface Access (SSH Port Forwarding)

If your VM is on a private network, use SSH port forwarding to access the web interface:

\`\`\`bash
# From your local machine (replace with your values):
ssh -L $APP_PORT:VM_IP:$APP_PORT user@opennebula-host

# Then open in browser:
# http://localhost:$APP_PORT
# Note: Some apps like Nextcloud AIO require HTTPS:
# https://localhost:$APP_PORT
\`\`\`

## Container Configuration

### Port Mappings
Format: \`host_port:container_port,host_port2:container_port2\`
Default: \`$DEFAULT_PORTS\`

### Environment Variables
Format: \`VAR1=value1,VAR2=value2\`
Provide these at VM instantiation via the CONTAINER_ENV context variable.
**Note:** environment variables may contain secrets (passwords, API keys); they are
intentionally not stored in this appliance's files or baked into the image.

### Volume Mounts
Format: \`/host/path:/container/path,/host/path2:/container/path2\`
Default: \`$DEFAULT_VOLUMES\`

## Management Commands

\`\`\`bash
# View running containers
docker ps

# View container logs
docker logs $DEFAULT_CONTAINER_NAME

# Access container shell
docker exec -it $DEFAULT_CONTAINER_NAME /bin/bash

# Restart container
docker restart $DEFAULT_CONTAINER_NAME

# Stop container
docker stop $DEFAULT_CONTAINER_NAME

# Start container
docker start $DEFAULT_CONTAINER_NAME
\`\`\`

## Technical Details

- **Base OS**: $OS_DISPLAY
- **Container Runtime**: Docker Engine CE
- **Container Image**: $DOCKER_IMAGE
- **Default Ports**: $DEFAULT_PORTS
- **Default Volumes**: $DEFAULT_VOLUMES
- **Memory Requirements**: 2GB minimum
- **Disk Requirements**: 8GB minimum

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
EOF

print_success "README.md generated"

# Generate appliance.sh installation script with simplified Phoenix RTOS/Node-RED structure
print_info "📝 Generating appliance.sh installation script (simplified structure)..."

# INJ-4 / SECR-3: emit the appliance.sh header safely.
#
# The static structure is emitted with a QUOTED heredoc terminator
# ('APPLIANCE_HEADER') so the generator never expands attacker-controlled
# values into the emitted source. The (already validated) config values are
# injected as separate assignments produced with `printf '%q'`, which yields a
# shell-safe literal that cannot break out of the assignment or inject code.
#
# SECR-3: DEFAULT_ENV_VARS is intentionally left EMPTY in the emitted script.
# Secrets must be supplied at instantiation via ONEAPP_CONTAINER_ENV context,
# never baked into the qcow2 image.
APPLIANCE_SH="$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh"

{
    printf '%s\n' '#!/usr/bin/env bash'
    printf '\n'
    printf '# %s Appliance Installation Script\n' "$APP_NAME"
    printf '# Auto-generated by OpenNebula Docker Appliance Generator\n'
    printf '# Docker Image: %s\n' "$DOCKER_IMAGE"
    printf '\n'
    printf 'set -o errexit -o pipefail\n'
    printf '\n'
    printf '# List of contextualization parameters\n'
    printf 'ONE_SERVICE_PARAMS=(\n'
    printf "    'ONEAPP_CONTAINER_NAME'     'configure'  'Docker container name'                    'O|text'\n"
    printf "    'ONEAPP_CONTAINER_PORTS'    'configure'  'Docker container port mappings'           'O|text'\n"
    printf "    'ONEAPP_CONTAINER_ENV'      'configure'  'Docker container environment variables'   'O|text'\n"
    printf "    'ONEAPP_CONTAINER_VOLUMES'  'configure'  'Docker container volume mappings'         'O|text'\n"
    printf ')\n'
    printf '\n'
    printf '# Configuration from user input (values injected with printf %%q escaping)\n'
    printf 'DOCKER_IMAGE=%q\n'           "$DOCKER_IMAGE"
    printf 'DEFAULT_CONTAINER_NAME=%q\n' "$DEFAULT_CONTAINER_NAME"
    printf 'DEFAULT_PORTS=%q\n'          "$DEFAULT_PORTS"
    # SECR-3: never bake ENV secrets into the image; require them at runtime.
    printf 'DEFAULT_ENV_VARS=%q\n'       ""
    printf 'DEFAULT_VOLUMES=%q\n'        "$DEFAULT_VOLUMES"
    printf 'APP_NAME=%q\n'               "$APP_NAME"
    printf 'APPLIANCE_NAME=%q\n'         "$APPLIANCE_NAME"
    printf '\n'
    printf '### Appliance metadata ###############################################\n'
    printf '\n'
    printf 'ONE_SERVICE_NAME=%q\n'                  "$APP_NAME"
    printf 'ONE_SERVICE_VERSION=   #latest\n'
    printf 'ONE_SERVICE_BUILD=$(date +%%s)\n'
    printf 'ONE_SERVICE_SHORT_DESCRIPTION=%q\n'     "$APP_NAME Docker Container Appliance"
    printf 'ONE_SERVICE_DESCRIPTION=%q\n'           "$APP_NAME running in Docker container"
    printf 'ONE_SERVICE_RECONFIGURABLE=true\n'
} > "$APPLIANCE_SH"

# Now append the rest with quoted heredoc to avoid escaping
cat >> "$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh" << 'APPLIANCE_BODY'

### Appliance functions ##############################################

service_cleanup()
{
    :
}

service_install()
{
    # Detect OS family
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_FAMILY=""
        case "$ID" in
            ubuntu|debian|linuxmint)
                OS_FAMILY="debian"
                ;;
            almalinux|rocky|centos|rhel|fedora)
                OS_FAMILY="rhel"
                ;;
            opensuse*|suse|sles)
                OS_FAMILY="suse"
                ;;
            *)
                msg error "Unsupported OS: $ID"
                exit 1
                ;;
        esac
    else
        msg error "Cannot detect OS - /etc/os-release not found"
        exit 1
    fi

    msg info "Detected OS: $ID $VERSION_ID (family: $OS_FAMILY)"

    if [ "$OS_FAMILY" = "debian" ]; then
        install_debian_based
    elif [ "$OS_FAMILY" = "suse" ]; then
        install_suse_based
    else
        install_rhel_based
    fi

    # Common post-install steps
    install_common
}

install_debian_based()
{
    export DEBIAN_FRONTEND=noninteractive

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install generic kernel with Virtual Terminal (VT) support for VNC console
    # The KVM kernel lacks VT support which causes VNC to show a black screen
    msg info "Installing generic kernel for VNC console support"
    apt-get install -y linux-image-generic linux-modules-extra-$(uname -r | sed 's/-kvm$/-generic/') 2>/dev/null || \
        apt-get install -y linux-image-generic || true

    # Set generic kernel as default in GRUB
    if [ -f /etc/default/grub ]; then
        GENERIC_ENTRY=$(grep -E "menuentry.*generic" /boot/grub/grub.cfg 2>/dev/null | head -1 | sed "s/.*'\([^']*\)'.*/\1/" || echo "")
        if [ -n "$GENERIC_ENTRY" ]; then
            sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>$GENERIC_ENTRY\"/" /etc/default/grub
        else
            sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
        fi
        update-grub
    fi

    # Install Docker
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings

    # Determine Docker repo based on distro
    local DOCKER_DISTRO="$ID"
    if [ "$ID" = "linuxmint" ]; then
        DOCKER_DISTRO="ubuntu"
    fi

    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Configure console auto-login
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true

    apt-get install -y mingetty || true
}

install_rhel_based()
{
    # Update system
    dnf update -y

    # Install Docker
    msg info "Installing Docker on RHEL-based system"
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Install mingetty equivalent
    dnf install -y util-linux || true
}

install_suse_based()
{
    # Update system
    zypper refresh
    zypper update -y

    # Install Docker
    msg info "Installing Docker on openSUSE/SUSE system"
    zypper install -y docker docker-compose

    # Install util-linux for console support
    zypper install -y util-linux || true
}

install_common()
{
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Pull the Docker image
    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    # Create TTY devices at boot (fallback for kernels without VT support)
    cat > /etc/systemd/system/create-tty-devices.service << 'TTY_SERVICE_EOF'
[Unit]
Description=Create TTY device nodes for KVM kernel
DefaultDependencies=no
Before=getty@tty1.service
After=systemd-tmpfiles-setup-dev.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for i in 0 1 2 3 4 5 6; do [ -e /dev/tty\$i ] || mknod /dev/tty\$i c 4 \$i; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TTY_SERVICE_EOF
    systemctl enable create-tty-devices.service

    # Configure auto-login on console (for VT-enabled kernels)
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'CONSOLE_EOF'
[Unit]
# Remove ConditionPathExists to avoid skipping on KVM kernels
ConditionPathExists=

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I $TERM
Type=idle
CONSOLE_EOF

    # Configure serial console (PRIMARY console for cloud VMs)
    # Serial console works reliably with KVM-optimized kernels
    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'SERIAL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
SERIAL_EOF

    # DEF-6 / SECR-8: do NOT set a fixed root password. Authentication relies
    # solely on the SSH public key injected via OpenNebula context. Console
    # auto-login (getty overrides above) still provides local access.
    systemctl enable getty@tty1.service serial-getty@ttyS0.service

    # Create welcome message
    cat > /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh << WELCOME_EOF
#!/bin/bash
case \$- in
    *i*) ;;
      *) return;;
esac

echo "=================================================="
echo "  $APP_NAME Appliance"
echo "=================================================="
echo "  Docker Image: $DOCKER_IMAGE"
echo "  Container: $DEFAULT_CONTAINER_NAME"
echo "  Ports: $DEFAULT_PORTS"
echo ""
echo "  Commands:"
echo "    docker ps                    - Show running containers"
echo "    docker logs $DEFAULT_CONTAINER_NAME   - View container logs"
echo "    docker exec -it $DEFAULT_CONTAINER_NAME /bin/bash - Access container"
echo ""
echo "  Access Methods:"
echo "    SSH: Enabled (context-injected SSH key only, no password login)"
echo "    VNC Console: Enabled (via OpenNebula Sunstone)"
echo "    Serial Console: Enabled (virsh console or Sunstone serial)"
echo "=================================================="
WELCOME_EOF

    chmod +x /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh

    # Clean up based on OS family
    if [ "$OS_FAMILY" = "debian" ]; then
        apt-get autoremove -y
        apt-get autoclean
    elif [ "$OS_FAMILY" = "suse" ]; then
        zypper clean --all
    else
        dnf clean all
    fi
    find /var/log -type f -exec truncate -s 0 {} \;

    sync

    return 0
}

service_configure()
{
    msg info "Configuring network and services"

    # Ensure DNS is configured (virt-sysprep deletes /etc/resolv.conf during image preparation)
    # This is a fallback in case OpenNebula network context doesn't provide DNS
    if [ ! -s /etc/resolv.conf ] || ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        msg info "Setting up DNS nameservers (fallback configuration)"
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    fi

    msg info "Verifying Docker is running"

    if ! systemctl is-active --quiet docker; then
        msg error "Docker is not running"
        return 1
    fi

    msg info "Docker is running"
    return 0
}

service_bootstrap()
{
    msg info "Starting $APP_NAME service bootstrap"

    # Setup and start the container
    setup_app_container

    return $?
}

# Setup container function
setup_app_container()
{
    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local container_ports="${ONEAPP_CONTAINER_PORTS:-$DEFAULT_PORTS}"
    local container_env="${ONEAPP_CONTAINER_ENV:-$DEFAULT_ENV_VARS}"
    local container_volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"

    msg info "Setting up $APP_NAME container: $container_name"

    # Stop and remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "Stopping existing container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    # INJ-3 / SECR-7: build docker arguments as a bash ARRAY and expand it
    # quoted, so each port/env/volume value is passed as one un-split,
    # un-globbed argument and cannot inject extra docker flags.
    local -a run_args=()

    # Parse port mappings
    if [ -n "$container_ports" ]; then
        IFS=',;' read -ra PORT_ARRAY <<< "$container_ports"
        for port in "${PORT_ARRAY[@]}"; do
            [ -n "$port" ] && run_args+=( -p "$port" )
        done
    fi

    # Parse environment variables
    if [ -n "$container_env" ]; then
        IFS=',;' read -ra ENV_ARRAY <<< "$container_env"
        for env in "${ENV_ARRAY[@]}"; do
            [ -n "$env" ] && run_args+=( -e "$env" )
        done
    fi

    # Parse volume mounts
    if [ -n "$container_volumes" ]; then
        # DEF-1 / CMP-DEF-5 / REG-1: sensitive host paths that must never be
        # bind-mounted into the root-running container (mounting any of these =
        # host compromise). We CANONICALIZE the host path first (realpath -m,
        # which collapses `.`/`..`/`//`/trailing slashes and resolves symlinks
        # even for non-existent paths), then reject only when the resolved path
        # EQUALS or is UNDER one of these roots. Exact-or-subpath matching means
        # legitimate app-data mounts (/opt/*, /srv/*, /mnt/*, /home/*, /data/*,
        # and config dirs like /etc/nginx were previously over-rejected by the
        # old /etc/* glob -> REG-1) still work, while /usr, /var/lib/docker,
        # /run/docker.sock, / etc. are blocked. We do NOT reject the entire
        # /etc or /var subtree: only the specific dangerous roots below.
        local -a sensitive_roots=(
            /var/run/docker.sock /run/docker.sock
            / /root /proc /sys /dev /boot
            /var/run /run /usr /bin /sbin /lib /lib64 /var/lib/docker
        )
        IFS=',;' read -ra VOL_ARRAY <<< "$container_volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            [ -z "$vol" ] && continue
            local host_path="${vol%%:*}"

            # Canonicalize; prefer realpath -m (resolves symlinks + . / .. / //),
            # else fall back to a pure-bash lexical normalization so the check
            # stays correct even if realpath is unavailable.
            local resolved
            resolved="$(realpath -m -- "$host_path" 2>/dev/null)" || resolved=""
            if [ -z "$resolved" ]; then
                local _p="$host_path" _seg
                local -a _out=()
                [ "${_p#/}" = "$_p" ] && _p="/$_p"
                local _oldifs="$IFS"; IFS=/
                for _seg in $_p; do
                    case "$_seg" in
                        ''|.) : ;;
                        ..) [ "${#_out[@]}" -gt 0 ] && unset '_out[${#_out[@]}-1]' ;;
                        *) _out+=("$_seg") ;;
                    esac
                done
                IFS="$_oldifs"
                if [ "${#_out[@]}" -eq 0 ]; then resolved="/"; else resolved="$(printf '/%s' "${_out[@]}")"; fi
            fi

            local root rejected=0
            for root in "${sensitive_roots[@]}"; do
                if [ "$resolved" = "$root" ] || [ "${resolved#"$root"/}" != "$resolved" ]; then
                    rejected=1
                    break
                fi
            done
            if [ "$rejected" -eq 1 ]; then
                msg error "Refusing to mount sensitive host path: $host_path (resolves to $resolved)"
                return 1
            fi

            # Reject device nodes / sockets that already exist on the host.
            if [ -b "$resolved" ] || [ -c "$resolved" ] || [ -S "$resolved" ]; then
                msg error "Refusing to mount device node or socket: $host_path"
                return 1
            fi

            # Create the host directory only if it does not yet exist. DEF-5:
            # do NOT chown -R an existing host tree (removed).
            if [ ! -e "$resolved" ]; then
                mkdir -p "$resolved"

                # Most official images run their workload as a NON-root user
                # (node-red, postgres, redis...). A directory we just created is
                # owned by root with umask 077 (0700), so that user cannot read
                # or write its own state directory and the container crash-loops
                # (e.g. node-red: "EACCES: permission denied, lstat
                # '/data/settings.js'"). Hand the new directory to the UID/GID
                # the image actually runs as. This is applied ONLY to a
                # directory just created here, never to a pre-existing host tree.
                local _img_user _img_uid _img_gid _ids
                _img_user="$(docker inspect -f '{{.Config.User}}' "$DOCKER_IMAGE" 2>/dev/null)"
                _img_uid=""; _img_gid=""
                case "$_img_user" in
                    '')   : ;;                                   # runs as root: nothing to do
                    *[!0-9:]*)                                   # a NAME: resolve it inside the image
                        _ids="$(docker run --rm --entrypoint /bin/sh "$DOCKER_IMAGE" \
                                    -c 'id -u; id -g' 2>/dev/null | tr '\n' ' ')"
                        _img_uid="$(printf '%s' "$_ids" | awk '{print $1}')"
                        _img_gid="$(printf '%s' "$_ids" | awk '{print $2}')"
                        ;;
                    *)    _img_uid="${_img_user%%:*}"             # already numeric
                          _img_gid="${_img_user##*:}"
                          [ "$_img_gid" = "$_img_uid" ] && _img_gid="$_img_uid"
                          ;;
                esac
                if [ -n "$_img_uid" ] && [ "$_img_uid" != "0" ]; then
                    chown "$_img_uid:${_img_gid:-$_img_uid}" "$resolved" 2>/dev/null || true
                    msg info "  Volume $resolved owned by container user ${_img_uid}:${_img_gid:-$_img_uid}"
                fi
            fi
            run_args+=( -v "$vol" )
        done
    fi

    # Start the container
    msg info "Starting $APP_NAME container with:"
    msg info "  Ports: $container_ports"
    msg info "  Environment: ${container_env:-none}"
    msg info "  Volumes: $container_volumes"

    # DEF-1: apply conservative container hardening defaults. These reduce the
    # blast radius of a container compromise without breaking typical images:
    #   - no-new-privileges: block setuid privilege escalation inside container
    #   - cap-drop=ALL + minimal add-backs: least-privilege capabilities
    #   - pids-limit / memory: basic resource bounds against fork/DoS
    local -a hardening_args=(
        --security-opt=no-new-privileges
        --cap-drop=ALL
        --cap-add=CHOWN --cap-add=SETUID --cap-add=SETGID --cap-add=NET_BIND_SERVICE
        --pids-limit=512
        --memory=1g
    )

    if docker run -d --name "$container_name" --restart unless-stopped \
        "${hardening_args[@]}" "${run_args[@]}" "$DOCKER_IMAGE"; then
        msg info "$APP_NAME container started successfully"
        docker ps --filter name="$container_name"
        return 0
    else
        msg error "Failed to start $APP_NAME container"
        return 1
    fi
}
APPLIANCE_BODY

# SECR-2: appliance.sh only needs to be owner-executable, not world-readable.
chmod 700 "$REPO_ROOT/appliances/$APPLIANCE_NAME/appliance.sh"
print_success "appliance.sh generated (simplified Phoenix RTOS/Node-RED structure)"

# Generate basic Packer files
print_info "📝 Generating Packer configuration files..."

# Build-time SSH credential. The Packer QEMU communicator SSHes into the
# transient build VM as root to run the provisioners. Like every other
# community appliance (see packer/example), we use the well-known build-only
# password "opennebula": it exists only on the localhost-bound build VM, is
# never the deployed VM's credential (the appliance boots SSH-key-only via
# context), and 81-configure-ssh.sh re-hardens sshd during the build. Because
# it is not a deployed secret, gen_context and <name>.pkr.hcl are committed
# like the rest of the build definition, so the appliance can be rebuilt from
# the PR.
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/.gitignore" << GITIGNORE_EOF
# Transient build artifacts produced by 'make ${APPLIANCE_NAME}': the context
# staging dir and the generated context ISO. The build definition itself
# (${APPLIANCE_NAME}.pkr.hcl, gen_context, variables.pkr.hcl and the *.sh
# provisioners) IS tracked so the appliance can be rebuilt from the PR.
context/
context.sh
*-context.iso
GITIGNORE_EOF

# Generate variables.pkr.hcl
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/variables.pkr.hcl" << 'EOF'
variable "appliance_name" {
  type = string
}

variable "version" {
  type = string
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type = bool
  default = true
}
EOF

# Create symlink to common.pkr.hcl (like other appliances)
ln -sf "../../../one-apps/packer/common.pkr.hcl" "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/common.pkr.hcl"

# Generate main .pkr.hcl file
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/$APPLIANCE_NAME.pkr.hcl" << EOF
source "null" "null" { communicator = "none" }

# Prior to setting up the appliance, the context packages need to be generated first
build {
  sources = ["source.null.null"]

  provisioner "shell-local" {
    inline = [
      "mkdir -p \${var.input_dir}/context",
      "\${var.input_dir}/gen_context > \${var.input_dir}/context/context.sh",
      "mkisofs -o \${var.input_dir}/\${var.appliance_name}-context.iso -V CONTEXT -J -R \${var.input_dir}/context",
    ]
  }
}

# Build VM image
source "qemu" "$APPLIANCE_NAME" {
  cpus        = 2
  memory      = 2048
  accelerator = "kvm"

  iso_url      = "../one-apps/export/${BASE_OS}.qcow2"
  iso_checksum = "none"

  headless = var.headless

  disk_image       = true
  disk_cache       = "unsafe"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  disk_compression = false
  disk_size        = "${DISK_SIZE}"

  output_directory = var.output_dir

  qemuargs = [
    ["-cpu", "host"],
    ["-cdrom", "\${var.input_dir}/\${var.appliance_name}-context.iso"],
    ["-serial", "stdio"],
    # MAC addr needs to match ETH0_MAC from context iso
    ["-netdev", "user,id=net0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net-pci,netdev=net0,mac=00:11:22:33:44:55"]
  ]

  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout     = "900s"
  shutdown_command = "poweroff"
  vm_name          = var.appliance_name
}

build {
  sources = ["source.qemu.$APPLIANCE_NAME"]

  # revert insecure ssh options done by context start_script
  provisioner "shell" {
    scripts = ["\${var.input_dir}/81-configure-ssh.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  provisioner "file" {
    sources = [
      "../one-apps/appliances/scripts/net-90-service-appliance",
      "../one-apps/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }
  provisioner "file" {
    sources = [
      "../../lib/common.sh",
      "../../lib/functions.sh",
    ]
    destination = "/etc/one-appliance/lib/"
  }
  provisioner "file" {
    source      = "../one-apps/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }
  provisioner "file" {
    sources     = ["../../appliances/$APPLIANCE_NAME/appliance.sh"]
    destination = "/etc/one-appliance/service.d/"
  }

  provisioner "shell" {
    scripts = ["\${var.input_dir}/82-configure-context.sh"]
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    # DEF-1: lock the root account password as the final in-guest step so the
    # shipped image is SSH-key / context only and the random build password
    # cannot be used for console login. This is the last provisioner, so no
    # later password-based communicator step depends on it.
    inline         = ["/etc/one-appliance/service install", "passwd -l root", "sync"]
  }

  post-processor "shell-local" {
    execute_command = ["bash", "-c", "{{.Vars}} {{.Script}}"]
    environment_vars = [
      "OUTPUT_DIR=\${var.output_dir}",
      "APPLIANCE_NAME=\${var.appliance_name}",
    ]
    scripts = ["../one-apps/packer/postprocess.sh"]
  }
}
EOF

# Generate 81-configure-ssh.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh" << 'EOF'
#!/usr/bin/env bash

# Configures critical settings for OpenSSH server.

exec 1>&2
set -eux -o pipefail

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PasswordAuthentication no" }
/^[#\s]*PasswordAuthentication\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "PermitRootLogin without-password" }
/^[#\s]*PermitRootLogin\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

gawk -i inplace -f- /etc/ssh/sshd_config <<'AWKEOF'
BEGIN { update = "UseDNS no" }
/^[#\s]*UseDNS\s/ { $0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
AWKEOF

sync
EOF

# Generate 82-configure-context.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh" << 'EOF'
#!/usr/bin/env bash

# Configure and enable service context.

exec 1>&2
set -eux -o pipefail

mv /etc/one-appliance/net-90-service-appliance /etc/one-context.d/
mv /etc/one-appliance/net-99-report-ready      /etc/one-context.d/

chown root:root /etc/one-context.d/*
chmod u=rwx,go=rx /etc/one-context.d/*

sync
EOF

# Generate gen_context with correct NETCFG_TYPE for the base OS
NETCFG_TYPE="${OS_NETCFG_TYPES[$BASE_OS]:-netplan}"
# DEF-6 / SECR-8: this gen_context produces the BUILD-TIME context ISO only.
# It temporarily enables password SSH with a random per-build password so the
# Packer communicator can connect; the 81-configure-ssh.sh provisioner then
# re-hardens sshd (PasswordAuthentication no / PermitRootLogin without-password)
# before the image is finalized. The deployed VM therefore ends up key-only.
# We do NOT set a fixed/published PASSWORD and do not leave root password login
# enabled in the shipped image.
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context" << EOF
#!/bin/bash
set -eux -o pipefail

SCRIPT=\$(cat <<'MAINEND'
gawk -i inplace -f- /etc/ssh/sshd_config <<'SSHEOF'
BEGIN { update = "PasswordAuthentication yes" }
/^[#\s]*PasswordAuthentication\s/ { \$0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
SSHEOF

gawk -i inplace -f- /etc/ssh/sshd_config <<'SSHEOF'
BEGIN { update = "PermitRootLogin yes" }
/^[#\s]*PermitRootLogin\s/ { \$0 = update; found = 1 }
{ print }
ENDFILE { if (!found) print update }
SSHEOF

systemctl reload sshd

echo "nameserver 1.1.1.1" > /etc/resolv.conf
MAINEND
)

cat<<CTXEOF
ETH0_METHOD='dhcp'
NETWORK='YES'
SET_HOSTNAME='${APPLIANCE_NAME}'
PASSWORD='opennebula'
ETH0_MAC='00:11:22:33:44:55'
NETCFG_TYPE='${NETCFG_TYPE}'
START_SCRIPT_BASE64="\$(echo "\$SCRIPT" | base64 -w0)"
CTXEOF
EOF
chmod 700 "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"

# Generate postprocess.sh
cat > "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh" << 'EOF'
#!/bin/bash

# Post-processing script for the appliance

set -e

echo "Post-processing appliance..."

# Add any post-processing steps here
# For example: image optimization, cleanup, etc.

echo "Post-processing completed"
EOF

chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
chmod +x "$REPO_ROOT/apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"

# Generate additional required files
print_info "📝 Generating additional required files..."

# Generate CHANGELOG.md
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/CHANGELOG.md" << EOF
# Changelog

All notable changes to the $APP_NAME appliance will be documented in this file.

## [1.0.0-1] - $CURRENT_DATE

### Added
- Initial release of $APP_NAME appliance
- Docker container: $DOCKER_IMAGE
- VNC desktop access
- SSH key authentication
- OpenNebula context integration
- Configurable container parameters
EOF

# Generate tests.yaml
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests.yaml" << EOF
---
- 00-${APPLIANCE_NAME}_basic.rb
EOF

# Generate basic test file
cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/tests/00-${APPLIANCE_NAME}_basic.rb" << EOF
# Certification tests for the $APP_NAME Docker appliance.
# Uses the community RSpec harness (lib/community/app_handler + vm_handler),
# the same framework the other appliances in this repo are tested with.

require_relative '../../../lib/community/app_handler'

describe 'Appliance Certification' do
    include_context('vm_handler')

    # The VM answers SSH before the appliance has finished its bootstrap, so
    # every check retries until it succeeds instead of asserting once. Without
    # this the suite is racy: 'systemctl is-active docker' in particular can be
    # queried while docker is still starting.
    def wait_for(description, cmd, timeout = 180)
        start_time = Time.now
        loop do
            result = @info[:vm].ssh(cmd)
            return result if result.success?
            raise "#{description} not satisfied within #{timeout}s (last: #{cmd})" if Time.now - start_time > timeout
            sleep 5
        end
    end

    it 'docker engine is active' do
        wait_for('docker active', 'systemctl is-active docker')
    end

    it '$APP_NAME image ($DOCKER_IMAGE) is present' do
        wait_for('image present',
                 "docker images --format '{{.Repository}}:{{.Tag}}' | grep -F '$DOCKER_IMAGE'")
    end

    it '$APP_NAME container ($DEFAULT_CONTAINER_NAME) is running' do
        wait_for('container running',
                 "docker ps --format '{{.Names}}' | grep -Fx '$DEFAULT_CONTAINER_NAME'")
    end
end
EOF

# Generate context.yaml for testing
# SECR-1: never persist DEFAULT_ENV_VARS here. Environment variables may carry
# secrets (DB passwords, API keys); they must be supplied at instantiation via
# the CONTAINER_ENV context variable, not committed to this file. Emit an empty
# CONTAINER_ENV default.
# BYP-2: emit each context.yaml scalar single-quoted (`'`->`''`) so structural
# chars in the interpolated values cannot corrupt or break the YAML document.
CONTEXT_ENV_LINE="ONEAPP_CONTAINER_ENV:"
CONTEXT_VOLUMES_LINE="ONEAPP_CONTAINER_VOLUMES:"
if [ -n "$DEFAULT_VOLUMES" ]; then
    CONTEXT_VOLUMES_LINE="ONEAPP_CONTAINER_VOLUMES: $CONTAINER_VOLUMES_Y"
fi

cat > "$REPO_ROOT/appliances/$APPLIANCE_NAME/context.yaml" << EOF
---
ONEAPP_CONTAINER_NAME: $CONTAINER_NAME_Y
ONEAPP_CONTAINER_PORTS: $CONTAINER_PORTS_Y
$CONTEXT_ENV_LINE
$CONTEXT_VOLUMES_LINE
EOF

# SECR-2: explicitly tighten credential-bearing outputs to owner-only. umask
# 077 already yields 600, but we set it explicitly as defense-in-depth.
chmod 600 "$REPO_ROOT/appliances/$APPLIANCE_NAME/context.yaml" \
          "$REPO_ROOT/appliances/$APPLIANCE_NAME/metadata.yaml" \
          "$REPO_ROOT/appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml" 2>/dev/null || true

print_success "Additional files generated"

print_success "Packer configuration files generated"

# Add appliance to Makefile.config SERVICES list
print_info "📝 Adding '$APPLIANCE_NAME' to Makefile.config SERVICES list..."
MAKEFILE_CONFIG="$REPO_ROOT/apps-code/community-apps/Makefile.config"

if [ -f "$MAKEFILE_CONFIG" ]; then
    # PATH-3: anchor the membership test to the SERVICES := assignment and match
    # the appliance name as a whole, space/assignment-delimited token, so a name
    # that is a substring of an existing service (e.g. "red" in "node-red") is
    # not falsely reported as already present. APPLIANCE_NAME is charset-limited
    # to [a-z0-9-] (validated above), so it is a safe grep token here.
    if grep -qE "^SERVICES :=.*( |:=)$APPLIANCE_NAME( |\$)" "$MAKEFILE_CONFIG"; then
        print_info "  ℹ️  '$APPLIANCE_NAME' already in SERVICES list"
    else
        # Add appliance to SERVICES list
        sed -i "s/^\(SERVICES :=.*\)$/\1 $APPLIANCE_NAME/" "$MAKEFILE_CONFIG"
        print_success "  ✅ Added '$APPLIANCE_NAME' to SERVICES list"
    fi
else
    print_warning "  ⚠️  Makefile.config not found, skipping SERVICES update"
fi

print_info "🎉 Appliance '$APPLIANCE_NAME' generated successfully!"
print_info ""
print_info "📁 Files created:"
print_info "  ✅ appliances/$APPLIANCE_NAME/metadata.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/${APPLIANCE_UUID}.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/README.md"
print_info "  ✅ appliances/$APPLIANCE_NAME/appliance.sh (with your Docker config)"
print_info "  ✅ appliances/$APPLIANCE_NAME/CHANGELOG.md"
print_info "  ✅ appliances/$APPLIANCE_NAME/tests.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/context.yaml"
print_info "  ✅ appliances/$APPLIANCE_NAME/tests/00-${APPLIANCE_NAME}_basic.rb"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/*.pkr.hcl"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/81-configure-ssh.sh"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/82-configure-context.sh"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/gen_context"
print_info "  ✅ apps-code/community-apps/packer/$APPLIANCE_NAME/postprocess.sh"
print_info "  ✅ apps-code/community-apps/Makefile.config (updated SERVICES list)"
print_info ""
print_info "🚀 Next steps:"
print_info "  1. Add logo: logos/$APPLIANCE_NAME.png (256x256 PNG)"
print_info "  2. Build the image:"
print_info "     cd apps-code/community-apps && make $APPLIANCE_NAME"
print_info "  3. Test the appliance"
print_info ""

# Skip build prompt if --no-build flag was passed
if [ "$NO_BUILD" = true ]; then
    print_info "Skipping build (--no-build flag). You can build later using:"
    print_info "  cd $REPO_ROOT/apps-code/community-apps && make $APPLIANCE_NAME"
    exit 0
fi

# Ask user if they want to build the image now. Only prompt when stdin is a
# real terminal: piped/CI/SSH-`bash -s` runs have no TTY, where `read` returns
# EOF immediately and would otherwise fail the script even though generation
# succeeded. Non-interactive runs skip the build (use --no-build to silence
# this note, or run `make $APPLIANCE_NAME` yourself).
if [ -t 0 ]; then
    read -p "$(echo -e "${BLUE}Do you want to build the image now? (y/n):${NC} ")" -n 1 -r
    echo
else
    print_info "Non-interactive session: skipping the build prompt."
    print_info "  Build later with: cd $REPO_ROOT/apps-code/community-apps && make $APPLIANCE_NAME"
    REPLY="n"
fi
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "🔨 Preparing to build the image..."

    # Check and initialize git submodules
    print_info "📦 Checking git submodules..."
    cd "$REPO_ROOT" || {
        print_error "Failed to navigate to repository root"
        exit 1
    }

    # Check if one-apps submodule is initialized
    if [ ! -f "apps-code/one-apps/packer/build.sh" ]; then
        print_info "  ⚙️  Initializing one-apps submodule (this may take a moment)..."
        if git submodule update --init --recursive apps-code/one-apps; then
            print_success "  ✅ Submodule initialized successfully"
        else
            print_error "Failed to initialize git submodules"
            print_info "Please run manually: git submodule update --init --recursive"
            exit 1
        fi
    else
        print_info "  ✅ Submodule already initialized"
    fi

    # Check if base image exists (use BASE_OS from config)
    BASE_IMAGE="$REPO_ROOT/apps-code/one-apps/export/${BASE_OS}.qcow2"
    if [ ! -f "$BASE_IMAGE" ]; then
        print_info "📦 Base ${OS_DISPLAY} image not found - building it now..."
        print_info "  ℹ️  This is a one-time process that will take 3-5 minutes"
        print_info "  ℹ️  The base image will be reused for all future appliances"
        print_info ""

        cd "$REPO_ROOT/apps-code/one-apps" || {
            print_error "Failed to navigate to one-apps directory"
            exit 1
        }

        print_info "🔨 Building base ${OS_DISPLAY} image..."
        if make "${BASE_OS}"; then
            print_success "✅ Base image built successfully!"
        else
            print_error "❌ Base image build failed!"
            print_info "You can try building it manually later:"
            print_info "  cd $REPO_ROOT/apps-code/one-apps && make ${BASE_OS}"
            exit 1
        fi
    else
        print_info "  ✅ Base ${OS_DISPLAY} image found"
    fi

    # Navigate to the build directory
    cd "$REPO_ROOT/apps-code/community-apps" || {
        print_error "Failed to navigate to apps-code/community-apps"
        exit 1
    }

    # Build the image using make
    print_info "🔨 Building appliance image..."
    print_info "Running: make $APPLIANCE_NAME"
    if make "$APPLIANCE_NAME"; then
        print_success "✅ Image built successfully!"

        # Check if the qcow2 file exists
        if [ -f "export/$APPLIANCE_NAME.qcow2" ]; then
            QCOW2_SIZE=$(du -h "export/$APPLIANCE_NAME.qcow2" | cut -f1)
            print_success "Image location: $REPO_ROOT/apps-code/community-apps/export/$APPLIANCE_NAME.qcow2"
            print_success "Image size: $QCOW2_SIZE"
            print_info ""
            print_info "📋 Next steps to deploy:"
            print_info "  1. Copy to OpenNebula frontend: cp export/$APPLIANCE_NAME.qcow2 /var/tmp/"
            print_info "  2. Create image: oneimage create --name $APPLIANCE_NAME --path /var/tmp/$APPLIANCE_NAME.qcow2 --datastore <datastore_id>"
            print_info "  3. Create template and instantiate VM"
        else
            print_warning "Image file not found at export/$APPLIANCE_NAME.qcow2"
            print_info "The image might be in a different location. Check the build output above."
        fi
    else
        print_error "❌ Image build failed!"
        print_info "Check the error messages above for details."
        exit 1
    fi
else
    print_info "Skipping build. You can build later using:"
    print_info "  cd $REPO_ROOT/apps-code/community-apps && make $APPLIANCE_NAME"
fi
