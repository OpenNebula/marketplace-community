#!/usr/bin/env bash

# CernVM-FS Proxy appliance.
#
# One VM with Squid, configured as the site proxy that the CernVM-FS documentation describes.
# Every client of the site sets CVMFS_HTTP_PROXY to this VM, so each file comes from the
# internet once and later clients read it from the cache. The clients can be plain VMs, the
# nodes of a Slurm or Kubernetes cluster, or an Open OnDemand service. The EESSI repositories
# are allowed by default, and any other public repository is allowed by adding its domain.
#
# Sources of the configuration:
#   https://cvmfs.readthedocs.io/en/stable/cpt-squid.html
#   https://www.eessi.io/docs/training-events/2025/tutorial-best-practices-cvmfs-hpc/access/proxy/

ONE_SERVICE_SETUP_DIR="/opt/one-appliance"          ### Install location. Required by bash helpers

### CONTEXT SECTION ###########################################################

ONE_SERVICE_PARAMS=(
    'ONEAPP_ACCESS_CLIENTS_NETWORKS'     'configure' 'Networks that may use the proxy, empty for the network of the first NIC' 'O|text'
    'ONEAPP_ACCESS_DESTINATIONS_DOMAINS' 'configure' 'Domains of the CernVM-FS servers the proxy may download from'          'O|text'
    'ONEAPP_CACHE_SIZE_DISK'             'configure' 'Size of the disk cache in MB'                                         'O|number'
    'ONEAPP_CACHE_SIZE_MEMORY'           'configure' 'Size of the memory cache in MB'                                       'O|number'
    'ONEAPP_CACHE_DISK_ENABLED'          'configure' 'Keep the disk cache on a second disk'                                 'O|boolean'
    'ONEAPP_CACHE_DISK_DEVICE'           'configure' 'Device of the second disk, empty to find it automatically'           'O|text'
)

# An empty value takes the default, so a VM instantiated without the wizard still gets a
# proxy restricted to the CernVM-FS servers and to its own subnet. The domains are the EESSI
# list plus .gridpp.rl.ac.uk, a server of cvmfs-config.cern.ch, the configuration repository
# that the CernVM-FS package makes every client read.
ONEAPP_ACCESS_CLIENTS_NETWORKS="${ONEAPP_ACCESS_CLIENTS_NETWORKS:-}"
ONEAPP_ACCESS_DESTINATIONS_DOMAINS="${ONEAPP_ACCESS_DESTINATIONS_DOMAINS:-.cern.ch .gridpp.rl.ac.uk .opensciencegrid.org .eessi.science}"
ONEAPP_CACHE_SIZE_DISK="${ONEAPP_CACHE_SIZE_DISK:-20000}"
ONEAPP_CACHE_SIZE_MEMORY="${ONEAPP_CACHE_SIZE_MEMORY:-1024}"
ONEAPP_CACHE_DISK_ENABLED="${ONEAPP_CACHE_DISK_ENABLED:-NO}"
ONEAPP_CACHE_DISK_DEVICE="${ONEAPP_CACHE_DISK_DEVICE:-}"

### Appliance metadata ########################################################

ONE_SERVICE_NAME='Service CernVM-FS Proxy - KVM'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Squid proxy that caches CernVM-FS repositories for the clients of a site'
ONE_SERVICE_DESCRIPTION=$(cat <<'DESC'
Squid configured as a CernVM-FS site proxy on port 3128. Clients set
CVMFS_HTTP_PROXY="http://<address of this VM>:3128" and read EESSI or any other allowed
public repository through it. The URL of the proxy is published to OneGate as
CVMFS_PROXY_URL and written to /etc/one-appliance/config.
DESC
)
ONE_SERVICE_RECONFIGURABLE=true

### Fixed settings ############################################################

SQUID_PORT=3128
SQUID_CONF=/etc/squid/squid.conf
CACHE_DIR=/var/spool/squid

# The file that the EESSI documentation fetches to test a proxy. It is small and it changes
# on every publication of the repository, so a 200 proves the path to the internet works.
CHECK_HOST='aws-eu-central-s1.eessi.science'
CHECK_URL="http://${CHECK_HOST}/cvmfs/software.eessi.io/.cvmfspublished"

###############################################################################
### Lifecycle #################################################################
###############################################################################

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq || { msg error "apt-get update failed"; return 1; }
    apt-get install -y -qq squid curl python3 >/dev/null \
        || { msg error "could not install squid"; return 1; }

    # The package starts Squid right away. The image must carry no running proxy, no cache
    # and no log lines from the build, so the proxy starts at boot with the settings of the
    # site.
    systemctl disable --now squid >/dev/null 2>&1
    rm -rf "${CACHE_DIR:?}"/* /var/log/squid/*
    [[ -e "${SQUID_CONF}.dist" ]] || cp "$SQUID_CONF" "${SQUID_CONF}.dist"

    apt-get clean
    rm -rf /var/lib/apt/lists/*

    create_one_service_metadata

    msg info "squid $(dpkg-query -W -f='${Version}' squid) installed"
    return 0
}

service_configure()
{
    load_network_context
    wait_for_network

    CLIENTS="$(client_networks)" || return 1
    DOMAINS="$(destination_domains)" || return 1
    check_sizes || return 1
    setup_cache_disk || return 1
    check_disk_space || return 1
    write_squid_conf || return 1

    cat > "${ONE_SERVICE_REPORT}" <<REPORT
[CernVM-FS Proxy]
url          = ${PROXY_URL}
clients      = ${CLIENTS}
destinations = ${DOMAINS}
disk_cache   = ${ONEAPP_CACHE_SIZE_DISK} MB in ${CACHE_DIR} ($(cache_disk_label))
memory_cache = ${ONEAPP_CACHE_SIZE_MEMORY} MB

On a client, write CVMFS_HTTP_PROXY="${PROXY_URL}" in /etc/cvmfs/default.local and run
cvmfs_config setup. The access log of the proxy is /var/log/squid/access.log.
REPORT
    chmod 600 "${ONE_SERVICE_REPORT}"

    msg info "squid configured for ${CLIENTS}"
    return 0
}

service_bootstrap()
{
    # configure and bootstrap run as two separate processes, so the list is read again.
    load_network_context
    DOMAINS="$(destination_domains)" || return 1

    systemctl enable squid >/dev/null 2>&1
    systemctl restart squid || { fail "squid does not start, see journalctl -u squid"; return 1; }
    wait_for_port || return 1
    check_upstream || return 1

    if onegate_ready; then
        onegate_call vm update --data "CVMFS_PROXY_URL=${PROXY_URL}" >/dev/null 2>&1 \
            || msg warning "could not publish CVMFS_PROXY_URL to OneGate"
        # READY is published here as well as by the one-context hook, because that hook only
        # uses the endpoint injected in the context and fails where it does not answer.
        onegate_call vm update --data "READY=YES" >/dev/null 2>&1 \
            || msg warning "could not publish READY to OneGate"
        # A boot that succeeds after a failed one clears the ERROR that the failure left.
        onegate_call vm update --erase ERROR >/dev/null 2>&1 || true
    else
        msg warning "OneGate does not answer, CVMFS_PROXY_URL is only in ${ONE_SERVICE_REPORT}"
    fi

    msg info "CernVM-FS proxy ready at ${PROXY_URL}"
    return 0
}

service_cleanup()
{
    # Empty on purpose. The framework runs it on every exit of the service script, including
    # the successful end of configure on a deployed VM.
    :
}

###############################################################################
### Functions #################################################################
###############################################################################

# Logs the reason, publishes it as the ERROR attribute of the VM so the operator reads it in
# Sunstone, and returns 1. The onegate client cuts its data at a comma and a double quote
# ends the value, so both are replaced.
fail()
{
    local reason="$*"
    msg error "$reason"
    if onegate_ready; then
        reason="${reason//\"/\'}"
        onegate_call vm update --data "ERROR=\"cvmfs-proxy: ${reason//,/;}\"" >/dev/null 2>&1 || true
    fi
    return 1
}

# The context runs this script about a second after the NIC comes up, often before the
# default route exists, and then neither OneGate nor the internet answers. It waits up to a
# minute and goes on anyway, so a VM with no default route still reports the real problem.
wait_for_network()
{
    local _
    for _ in $(seq 1 30); do
        [[ -n "$(ip route show default)" ]] && return 0
        sleep 2
    done
    msg warning "the VM has no default route after 60 seconds"
}

# Address of the first NIC and the URL the clients use. The context normally exports the
# NIC variables to this script, and the environment file of one-context has them otherwise.
load_network_context()
{
    if [[ -z "${ETH0_IP:-}" && -r /var/run/one-context/one_env ]]; then
        # shellcheck disable=SC1091
        . /var/run/one-context/one_env
    fi
    PROXY_IP="${ETH0_IP:-$(get_local_ip)}"
    PROXY_URL="http://${PROXY_IP}:${SQUID_PORT}"
}

# Prints the client networks, normalised, one line. Empty input means the subnet of the
# first NIC. Each value is checked, because it is written into squid.conf and a stray line
# there could open the proxy.
client_networks()
{
    local nets out
    read -ra nets <<< "${ONEAPP_ACCESS_CLIENTS_NETWORKS}"
    if (( ${#nets[@]} == 0 )); then
        [[ -n "${ETH0_IP:-}" ]] \
            || { fail "the context has no first NIC, set ONEAPP_ACCESS_CLIENTS_NETWORKS"; return 1; }
        nets=("${ETH0_IP}/${ETH0_MASK:-255.255.255.0}")
    fi
    out="$(python3 - "${nets[@]}" <<'PY'
import ipaddress, sys
try:
    print(' '.join(str(ipaddress.ip_network(n, strict=False)) for n in sys.argv[1:]))
except ValueError as e:
    sys.exit(str(e))
PY
)" || { fail "ONEAPP_ACCESS_CLIENTS_NETWORKS has a value that is not a network in CIDR notation"; return 1; }
    printf '%s\n' "$out"
}

# Prints the destination domains. A leading dot allows the domain and every host under it,
# as in Squid. Only host name characters pass, for the same reason as the networks.
destination_domains()
{
    local d domains label='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
    read -ra domains <<< "${ONEAPP_ACCESS_DESTINATIONS_DOMAINS}"
    for d in "${domains[@]}"; do
        [[ "$d" =~ ^\.?${label}(\.${label})*$ ]] \
            || { fail "ONEAPP_ACCESS_DESTINATIONS_DOMAINS has a value that is not a domain, ${d}"; return 1; }
    done
    printf '%s\n' "${domains[*]}"
}

check_sizes()
{
    local mem_mb
    [[ "$ONEAPP_CACHE_SIZE_DISK" =~ ^[1-9][0-9]*$ ]] \
        || { fail "ONEAPP_CACHE_SIZE_DISK must be a number of MB, it is ${ONEAPP_CACHE_SIZE_DISK}"; return 1; }
    [[ "$ONEAPP_CACHE_SIZE_MEMORY" =~ ^[1-9][0-9]*$ ]] \
        || { fail "ONEAPP_CACHE_SIZE_MEMORY must be a number of MB, it is ${ONEAPP_CACHE_SIZE_MEMORY}"; return 1; }

    # Squid needs memory beyond cache_mem for the index of the disk cache and for itself, so
    # half a GB stays free for them and for the system.
    mem_mb="$(awk '/^MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
    (( ONEAPP_CACHE_SIZE_MEMORY + 512 <= mem_mb )) \
        || { fail "a memory cache of ${ONEAPP_CACHE_SIZE_MEMORY} MB does not fit in the ${mem_mb} MB of the VM, add memory or lower ONEAPP_CACHE_SIZE_MEMORY"; return 1; }
}

# Puts the cache on the second disk when the switch is on. A blank disk is formatted as ext4.
# A disk with an ext4 file system is used as it is, so a cache survives a new VM. Anything
# else stops the boot, so the appliance never destroys data.
setup_cache_disk()
{
    local dev fstype mounted_at root_disk

    if ! is_true ONEAPP_CACHE_DISK_ENABLED; then
        # A disk switched off later is released, and the cache goes back to the system disk.
        if grep -q "[[:space:]]${CACHE_DIR}[[:space:]]" /etc/fstab; then
            systemctl stop squid >/dev/null 2>&1
            umount "$CACHE_DIR" 2>/dev/null
            sed -i "\#[[:space:]]${CACHE_DIR}[[:space:]]#d" /etc/fstab
            systemctl daemon-reload
        fi
        return 0
    fi

    dev="$(find_cache_disk)" || return 1
    [[ -b "$dev" ]] \
        || { fail "the cache disk ${dev} does not exist, add a second disk to the VM"; return 1; }

    # Already in place, for example on a reboot.
    [[ "$(findmnt -rno SOURCE "$CACHE_DIR")" == "$dev" ]] && return 0

    root_disk="$(lsblk -ndo PKNAME "$(findmnt -rno SOURCE /)")"
    [[ "$(basename "$dev")" != "$root_disk" ]] \
        || { fail "${dev} is the system disk, choose the second disk"; return 1; }
    mounted_at="$(findmnt -rno TARGET -S "$dev" | head -1)"
    [[ -z "$mounted_at" ]] \
        || { fail "${dev} is already mounted at ${mounted_at}"; return 1; }

    # blkid returns 2 only when it finds no signature at all. Any other code, including the
    # one for two conflicting signatures, means the disk holds something.
    blkid -p "$dev" >/dev/null 2>&1
    if (( $? == 2 )) && (( $(lsblk -nro NAME "$dev" | wc -l) == 1 )); then
        msg info "formatting the blank disk ${dev} for the cache"
        mkfs.ext4 -q -L cvmfs-cache "$dev" || { fail "could not format ${dev}"; return 1; }
    fi
    fstype="$(blkid -o value -s TYPE "$dev")"
    [[ "$fstype" == "ext4" ]] \
        || { fail "${dev} holds ${fstype:-a partition table}, the appliance only formats a blank disk"; return 1; }

    # The old cache on the system disk would stay hidden under the mount point, so it goes.
    systemctl stop squid >/dev/null 2>&1
    rm -rf "${CACHE_DIR:?}"/*
    sed -i "\#[[:space:]]${CACHE_DIR}[[:space:]]#d" /etc/fstab
    # A disk that comes from another VM may carry programs or device files, so none of them run.
    printf 'UUID=%s %s ext4 defaults,nofail,nosuid,nodev,noexec 0 2\n' "$(blkid -o value -s UUID "$dev")" "$CACHE_DIR" >> /etc/fstab
    systemctl daemon-reload
    mount "$CACHE_DIR" || { fail "could not mount ${dev} at ${CACHE_DIR}"; return 1; }
    chown proxy:proxy "$CACHE_DIR"
    msg info "the cache lives on ${dev}"
}

# Prints the device of the second disk. It is the one the admin named, or else the only disk
# of the VM that is not the system disk. A disk added in Sunstone shows up as /dev/sda or
# /dev/vdb inside the VM depending on its device prefix, so the appliance does not assume a name.
find_cache_disk()
{
    local root_disk name type ro disks=()

    if [[ -n "$ONEAPP_CACHE_DISK_DEVICE" ]]; then
        [[ "$ONEAPP_CACHE_DISK_DEVICE" =~ ^/dev/[A-Za-z0-9/_-]+$ ]] \
            || { fail "ONEAPP_CACHE_DISK_DEVICE must be a device path, it is ${ONEAPP_CACHE_DISK_DEVICE}"; return 1; }
        readlink -f "$ONEAPP_CACHE_DISK_DEVICE"
        return 0
    fi

    root_disk="$(lsblk -ndo PKNAME "$(findmnt -rno SOURCE /)")"
    while read -r name type ro; do
        [[ "$type" == "disk" && "$ro" == "0" && "$(basename "$name")" != "$root_disk" ]] && disks+=("$name")
    done < <(lsblk -dnpo NAME,TYPE,RO)

    case ${#disks[@]} in
        1) printf '%s\n' "${disks[0]}" ;;
        0) fail "the VM has no second disk, add one in the Storage tab of the wizard or turn off ONEAPP_CACHE_DISK_ENABLED"
           return 1 ;;
        *) fail "the VM has several extra disks (${disks[*]}), name the cache disk in ONEAPP_CACHE_DISK_DEVICE"
           return 1 ;;
    esac
}

cache_disk_label()
{
    local src
    src="$(findmnt -rno SOURCE "$CACHE_DIR")"
    printf '%s\n' "${src:-system disk}"
}

# Squid stops when its disk fills, so the cache must fit with room to spare.
check_disk_space()
{
    local avail_mb used_mb total_mb
    avail_mb="$(df -Pm "$CACHE_DIR" | awk 'NR == 2 {print $4}')"
    used_mb="$(du -sm "$CACHE_DIR" | cut -f1)"
    total_mb=$(( avail_mb + used_mb ))
    (( ONEAPP_CACHE_SIZE_DISK <= total_mb * 9 / 10 )) \
        || { fail "a disk cache of ${ONEAPP_CACHE_SIZE_DISK} MB does not fit in the ${total_mb} MB free for ${CACHE_DIR}, grow the disk or lower ONEAPP_CACHE_SIZE_DISK"; return 1; }
}

# The complete squid.conf, written on every boot. The access rules are the ones of the EESSI
# template. The cache directives are the ones of the CernVM-FS documentation, except
# cache_mem, whose default follows EESSI.
write_squid_conf()
{
    local tmp net
    tmp="$(mktemp)"
    {
        printf '# Written by the CernVM-FS Proxy appliance on every boot, from the ONEAPP_ context\n'
        printf '# variables of the VM. Change those and reboot, edits to this file are lost.\n'
        for net in $CLIENTS; do
            printf 'acl local_nodes src %s\n' "$net"
        done
        # -n stops Squid from matching an address in the URL by its reverse DNS name, which the
        # owner of that address chooses. Without it a client could reach any server.
        printf 'acl stratum_ones dstdomain -n %s\n' "$DOMAINS"
        cat <<EOF
# CernVM-FS only sends plain GET requests, so tunnels are never needed.
http_access deny CONNECT
http_access deny !stratum_ones
http_access allow local_nodes
http_access allow localhost
http_access deny all
http_port ${SQUID_PORT}
max_filedescriptors 8192
collapsed_forwarding on
minimum_expiry_time 0
maximum_object_size 1024 MB
cache_mem ${ONEAPP_CACHE_SIZE_MEMORY} MB
maximum_object_size_in_memory 128 KB
cache_dir ufs ${CACHE_DIR} ${ONEAPP_CACHE_SIZE_DISK} 16 256
coredump_dir ${CACHE_DIR}
# logrotate rotates the logs of the Ubuntu package.
logfile_rotate 0
EOF
    } > "$tmp"

    if ! squid -k parse -f "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        fail "squid rejects the generated configuration"
        return 1
    fi
    install -m 644 "$tmp" "$SQUID_CONF"
    rm -f "$tmp"
}

wait_for_port()
{
    local _
    for _ in $(seq 1 30); do
        ss -ltnH "( sport = :${SQUID_PORT} )" | grep -q . && return 0
        sleep 2
    done
    fail "squid does not listen on port ${SQUID_PORT} after 60 seconds"
}

# True when the destination list allows the host of the check.
check_host_allowed()
{
    local d
    for d in $DOMAINS; do
        [[ "$d" == "$CHECK_HOST" ]] && return 0
        [[ "$d" == .* && ".${CHECK_HOST}" == *"$d" ]] && return 0
    done
    return 1
}

# Fetches the EESSI test file through the proxy, as the EESSI documentation does, so READY
# means the proxy really reaches the internet. The VM may start before its network is fully
# up, so the check retries for a minute.
check_upstream()
{
    local code
    if ! check_host_allowed; then
        msg info "${CHECK_HOST} is not in the destination list, the check through the internet is skipped"
        return 0
    fi
    for _ in $(seq 1 6); do
        code="$(curl -s -o /dev/null -w '%{http_code}' --head --max-time 20 \
                -x "http://127.0.0.1:${SQUID_PORT}" "$CHECK_URL")"
        [[ "$code" == "200" ]] && return 0
        sleep 10
    done
    fail "the proxy cannot download ${CHECK_URL} (HTTP ${code}), check that the VM reaches the internet on port 80"
}

# OneGate. The endpoint injected in the context is a link-local address that only answers
# where the OneGate proxy or a virtual router serves it. On a single node installation
# OneGate listens on the gateway of the VM instead, so that address is tried second. The Ruby
# client is called directly, because the /usr/bin/onegate wrapper always rereads the
# injected endpoint.
onegate_ready()
{
    local candidate code _
    [[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env
    # A VM without TOKEN=YES has no way to talk to OneGate, so it does not wait for it.
    [[ -n "${VMID:-}" && "${TOKEN:-}" == "YES" ]] || return 1
    for _ in 1 2 3; do
        for candidate in "${ONEGATE_ENDPOINT:-}" \
                         "http://$(ip route show default | awk '{print $3; exit}'):5030"; do
            [[ -z "$candidate" || "$candidate" == "http://:5030" ]] && continue
            code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${candidate}/vm")"
            if [[ "$code" == "401" || "$code" == "200" ]]; then
                export ONEGATE_ENDPOINT="$candidate"
                return 0
            fi
        done
        sleep 5
    done
    return 1
}

onegate_call()
{
    if [[ -x /usr/bin/onegate.rb ]]; then
        ruby /usr/bin/onegate.rb "$@"
    else
        onegate "$@"
    fi
}
