#!/usr/bin/env bash

# OpenNebula Front-end appliance for OpenNebula ("OpenNebula over OpenNebula").
# Turns a single Ubuntu 24.04 VM into a self-contained OpenNebula lab using the
# upstream miniONE installer, which pulls the latest OpenNebula release: an
# OpenNebula front-end (oned + FireEdge web UI + OneGate + OneFlow) plus a
# co-located local KVM/QEMU node and a default lab virtual network. Deploy it
# inside another OpenNebula cloud and you get a disposable OpenNebula lab to
# learn, demo, or test against.
#
# miniONE detects hardware virtualization (vmx/svm) and uses KVM when the
# underlying host exposes nested virtualization, transparently falling back to
# QEMU emulation otherwise, so the lab boots everywhere (just slower without
# nested virt). miniONE runs once on first boot so detection and networking
# happen against the real host, not the build environment.
#
# Upstream: https://github.com/OpenNebula/minione
#           https://opennebula.io

set -o errexit -o pipefail

### Configuration ############################################################

MINIONE_BIN='/usr/local/bin/minione'
APP_STATE_DIR='/var/lib/one-appliance'
APP_LOG_DIR='/var/log/one-appliance'
MINIONE_SENTINEL="${APP_STATE_DIR}/.minione_done"
MINIONE_LOG="${APP_LOG_DIR}/minione.log"
PW_FILE="${APP_STATE_DIR}/oneadmin.password"
FIREEDGE_PORT=2616
SUNSTONE_PROXY_PORT=80

### CONTEXT SECTION ##########################################################

ONE_SERVICE_PARAMS=(
    'ONEAPP_ONEADMIN_PASSWORD'  'configure'  'Password for the oneadmin user and the FireEdge web UI (leave empty to auto-generate a random one, shown in the VM report)'  'O|password'
    'ONEAPP_ONE_MODE'           'configure'  'What to deploy: "Front-end + KVM node" (a complete single-VM lab that can launch VMs) or "Front-end only" (just the control plane, attach external KVM hosts yourself)'  'O|list'
    'ONEAPP_ONE_VERSION'        'configure'  'OpenNebula release to install (leave empty to install the latest release; set e.g. 7.2 to pin a specific one)'  'O|text'
    'ONEAPP_ONE_FORM'           'configure'  'Install OneForm so the front-end can provision more KVM nodes and clusters (oneprovision, Terraform plus Ansible). YES or NO'  'O|boolean'
    'ONEAPP_ONE_VNET_ADDRESS'   'configure'  'Base network address for the lab virtual network (Front-end + KVM node mode)'  'O|text'
    'ONEAPP_ONE_SSHKEY'         'configure'  'Extra SSH public key authorized for root (one-context already injects $USER[SSH_PUBLIC_KEY])'  'O|text64'
)

ONEAPP_ONEADMIN_PASSWORD="${ONEAPP_ONEADMIN_PASSWORD:-}"
ONEAPP_ONE_MODE="${ONEAPP_ONE_MODE:-Front-end + KVM node}"
ONEAPP_ONE_VERSION="${ONEAPP_ONE_VERSION:-}"
ONEAPP_ONE_FORM="${ONEAPP_ONE_FORM:-YES}"
ONEAPP_ONE_VNET_ADDRESS="${ONEAPP_ONE_VNET_ADDRESS:-172.16.100.0}"
ONEAPP_ONE_SSHKEY="${ONEAPP_ONE_SSHKEY:-}"

### Appliance metadata #######################################################

ONE_SERVICE_NAME='Service OpenNebula Front-end - KVM'
ONE_SERVICE_VERSION='1.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='OpenNebula front-end plus a local KVM/QEMU node, built with miniONE (latest release)'
ONE_SERVICE_DESCRIPTION=$(cat <<'EOF'
A self-contained OpenNebula lab built with the upstream miniONE installer, which
pulls the latest OpenNebula release. On first boot it deploys an OpenNebula
front-end (oned, the FireEdge web UI, OneGate and OneFlow) plus a co-located
local KVM/QEMU node and a default lab virtual network, so you can log in to
FireEdge and launch VMs immediately.

Hardware virtualization is detected automatically: KVM is used when the host
exposes nested virtualization (recommended for usable guest performance), and
QEMU software emulation is used otherwise. The lab is for evaluation, training
and demos, not production.
EOF
)
ONE_SERVICE_RECONFIGURABLE=true

###############################################################################
# Lifecycle
###############################################################################

service_install()
{
    msg info "Installing OpenNebula Front-end (miniONE) appliance"

    export DEBIAN_FRONTEND=noninteractive

    # rules #3: needrestart hooks apt on Ubuntu 24.04 and restarts ssh.service
    # mid-provisioner, dropping Packer's SSH connection. Remove it first.
    apt-get remove -y needrestart || true

    # Deny apt-triggered service restarts during the build so installing or
    # upgrading openssh-server/systemd cannot drop Packer's SSH connection
    # ("Script disconnected unexpectedly"). Removed in postinstall_cleanup.
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
    chmod 0755 /usr/sbin/policy-rc.d

    apt_wait_lock
    apt-get update -y

    # ufw + iptables together (rules #1: never iptables-persistent, which ufw Breaks).
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        jq \
        lsb-release \
        openssh-server \
        ufw \
        iptables \
        netplan.io \
        network-manager

    install_minione
    install_helpers
    configure_console_autologin
    harden_firewall

    postinstall_cleanup
    msg info "INSTALLATION FINISHED"
}

service_configure()
{
    msg info "Configuring OpenNebula Front-end appliance"

    configure_dns
    resolve_oneadmin_password
    configure_extra_ssh_key
    harden_firewall

    msg info "CONFIGURATION FINISHED"
}

service_bootstrap()
{
    msg info "Bootstrapping OpenNebula Front-end appliance"

    # configure and bootstrap run as separate processes, so re-derive the
    # password here (idempotent: reloads the persisted value from PW_FILE).
    resolve_oneadmin_password
    ensure_ssh_service

    run_minione
    apply_oneadmin_password
    ensure_services
    install_oneform
    write_service_report

    msg info "BOOTSTRAP FINISHED"
}

service_cleanup() { :; }

###############################################################################
# Install helpers (build time)
###############################################################################

apt_wait_lock()
{
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
       || fuser /var/lib/apt/lists/lock     >/dev/null 2>&1 \
       || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        [ "${waited}" -ge 120 ] && break
        sleep 5
        waited=$((waited + 5))
    done
}

install_minione()
{
    msg info "Downloading the miniONE installer"
    install -d -m 0755 "${APP_STATE_DIR}" "${APP_LOG_DIR}"

    # Bake the installer into the image so first boot does not depend on
    # GitHub being reachable to fetch miniONE itself (the OS packages it pulls
    # still need the OpenNebula apt repo at first boot).
    local url='https://github.com/OpenNebula/minione/releases/latest/download/minione'
    curl -fsSL -o "${MINIONE_BIN}" "${url}"
    chmod 0755 "${MINIONE_BIN}"
    sha256sum "${MINIONE_BIN}" | awk '{print $1}' > "${APP_STATE_DIR}/minione.sha256"
    msg info "miniONE baked at ${MINIONE_BIN} (sha256 $(cat "${APP_STATE_DIR}/minione.sha256"))"
}

install_helpers()
{
    msg info "Installing CLI helpers and MOTD"

    cat > /usr/local/bin/one-status <<EOF
#!/usr/bin/env bash
# Quick status of the OpenNebula front-end lab.
set -eu
echo "OpenNebula services:"
for unit in opennebula opennebula-fireedge opennebula-gate opennebula-flow; do
    printf '  %-22s %s\n' "\${unit}" "\$(systemctl is-active "\${unit}" 2>/dev/null || echo inactive)"
done
IP=\$(hostname -I | awk '{print \$1}')
echo
echo "FireEdge web UI: http://\${IP}:${FIREEDGE_PORT}/fireedge  (also http://\${IP}/ if the proxy is up)"
echo "oneadmin password: \$( [ -f "${PW_FILE}" ] && cat "${PW_FILE}" || echo '<set via context or see /var/lib/one/.one/one_auth>')"
if command -v onehost >/dev/null 2>&1; then
    echo
    echo "Hosts:"; sudo -u oneadmin onehost list 2>/dev/null || true
fi
EOF
    chmod 0755 /usr/local/bin/one-status

    cat > /etc/profile.d/99-opennebula-motd.sh <<'EOF'
#!/usr/bin/env bash
case $- in *i*) ;; *) return;; esac
IP=$(hostname -I | awk '{print $1}')
cat <<BANNER
============================================================
  OpenNebula Front-end (miniONE lab)
------------------------------------------------------------
  FireEdge web UI:  http://${IP}:2616/fireedge
  Login user:       oneadmin
  Password:         see /var/lib/one-appliance/oneadmin.password
                    (or the VM report / /var/lib/one/.one/one_auth)
------------------------------------------------------------
  one-status        show services, hosts and the UI URL
  sudo -u oneadmin onevm list        list lab VMs
  Provisioning log: /var/log/one-appliance/minione.log
============================================================
BANNER
EOF
    chmod 0755 /etc/profile.d/99-opennebula-motd.sh
}

configure_console_autologin()
{
    msg info "Configuring console autologin for root"

    install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I $TERM
Type=idle
EOF

    install -d -m 0755 /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
EOF

    systemctl daemon-reload
}

harden_firewall()
{
    msg info "Applying firewall rules"
    # Reconfigurable: re-applied on every boot, nothing persisted (rules #1).
    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp     comment 'SSH'
    ufw allow 80/tcp     comment 'Sunstone proxy'
    ufw allow 2616/tcp   comment 'FireEdge web UI'
    ufw allow 2633/tcp   comment 'oned XML-RPC API'
    ufw allow 2474/tcp   comment 'OneFlow'
    ufw allow 5030/tcp   comment 'OneGate'
    ufw allow 29876/tcp  comment 'noVNC proxy'
    ufw logging low
    ufw --force enable
}

###############################################################################
# Configure helpers (boot time)
###############################################################################

configure_dns()
{
    getent hosts github.com >/dev/null 2>&1 && return 0
    if [ ! -s /etc/resolv.conf ] || ! grep -q '^nameserver' /etc/resolv.conf; then
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    fi
}

resolve_oneadmin_password()
{
    install -d -m 0750 "${APP_STATE_DIR}"
    local pw="${ONEAPP_ONEADMIN_PASSWORD}"
    # trim whitespace and ignore unsubstituted CONTEXT templates ($ONEAPP...)
    pw="${pw#"${pw%%[![:space:]]*}"}"; pw="${pw%"${pw##*[![:space:]]}"}"
    case "${pw}" in ''|'$ONEAPP'*) pw='' ;; esac

    if [ -z "${pw}" ]; then
        if [ -s "${PW_FILE}" ]; then
            pw="$(cat "${PW_FILE}")"                 # reuse across reboots (idempotent)
        else
            pw="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
            msg info "Generated a random oneadmin password"
        fi
    fi
    umask 077
    printf '%s\n' "${pw}" > "${PW_FILE}"
    chmod 0600 "${PW_FILE}"
    ONEADMIN_PW="${pw}"
}

configure_extra_ssh_key()
{
    [ -n "${ONEAPP_ONE_SSHKEY}" ] || return 0
    msg info "Authorizing extra SSH key for root"
    install -d -m 0700 /root/.ssh
    # text64 normally arrives base64-encoded, but a user may paste a raw key.
    # Decode only when it is not already an OpenSSH public key (GNU base64 -d
    # would otherwise turn a raw key into binary garbage).
    case "${ONEAPP_ONE_SSHKEY}" in
        ssh-*|ecdsa-*|sk-*)
            printf '%s\n' "${ONEAPP_ONE_SSHKEY}" >> /root/.ssh/authorized_keys ;;
        *)
            { echo "${ONEAPP_ONE_SSHKEY}" | base64 -d 2>/dev/null \
                || printf '%s\n' "${ONEAPP_ONE_SSHKEY}"; } >> /root/.ssh/authorized_keys ;;
    esac
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
}

###############################################################################
# Bootstrap helpers (boot time)
###############################################################################

ensure_ssh_service()
{
    # Ubuntu 24.04 ships openssh-server socket-activated (ssh.socket), so
    # ssh.service reads as inactive until a connection arrives. miniONE's
    # "ssh service is running" pre-flight check fails on that, so switch to the
    # always-on ssh.service before invoking miniONE.
    systemctl is-active --quiet ssh.service && return 0
    msg info "Switching SSH from socket activation to the always-on ssh.service"
    systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    systemctl enable --now ssh.service >/dev/null 2>&1 || true
}

run_minione()
{
    if [ -f "${MINIONE_SENTINEL}" ]; then
        msg info "miniONE already provisioned, skipping installation"
        return 0
    fi

    # --force skips miniONE's conservative non-fatal pre-flight checks (e.g. the
    # free-disk-space minimum); the front-end plus a small guest needs only a few
    # GiB. --sunstone-port 2616 keeps FireEdge on its default port (miniONE moves
    # it to 80 unless this equals 2616), matching the firewall, report and tests.
    local args=(--yes --force --password "${ONEADMIN_PW}" --sunstone-port 2616)

    # Install the latest OpenNebula release by default (miniONE's built-in
    # default tracks the newest supported release). Pin only when asked.
    [ -n "${ONEAPP_ONE_VERSION}" ] && args+=(--version "${ONEAPP_ONE_VERSION}")

    # Match the mode robustly: anything that looks like "front-end only" skips the
    # local node; everything else (the default "Front-end + KVM node") builds the
    # full single-VM lab.
    local mode mode_lc
    mode_lc=$(printf '%s' "${ONEAPP_ONE_MODE}" | tr '[:upper:]' '[:lower:]')
    case "${mode_lc}" in
        *only*|frontend)
            mode='Front-end only'
            args+=(--frontend)                       # front-end only, no local node
            ;;
        *)
            mode='Front-end + KVM node'              # full lab: front-end + local KVM/QEMU node
            [ -n "${ONEAPP_ONE_VNET_ADDRESS}" ] && args+=(--vnet-address "${ONEAPP_ONE_VNET_ADDRESS}")
            ;;
    esac

    msg info "Running miniONE (${mode}, OpenNebula ${ONEAPP_ONE_VERSION:-latest release}). This can take several minutes."
    install -d -m 0755 "${APP_LOG_DIR}"
    # one-context runs bootstrap under systemd with no HOME, but miniONE invokes
    # the ONE CLI (oneuser), which resolves ~/.one/one_auth via $HOME and crashes
    # on a nil HOME ("no implicit conversion of nil into String"). Set it.
    export HOME=/root
    # miniONE creates the OpenNebula apt keyring with `gpg --dearmor`, which
    # honors the umask. The service framework runs bootstrap with umask 077, so
    # the keyring lands 0600 and apt's sandboxed _apt user cannot read it
    # (NO_PUBKEY, apt update fails). Run miniONE under umask 022 so the keyring
    # is world-readable.
    umask 022
    if "${MINIONE_BIN}" "${args[@]}" >"${MINIONE_LOG}" 2>&1; then
        touch "${MINIONE_SENTINEL}"
        msg info "miniONE provisioning completed"
    else
        msg error "miniONE failed, see ${MINIONE_LOG}"
        tail -n 60 "${MINIONE_LOG}" >&2 || true
        return 1
    fi
}

apply_oneadmin_password()
{
    # On a later boot the operator may pass a new password via context. Keep
    # oneadmin and the stored file in sync. Guarded on a provisioned front-end.
    [ -f "${MINIONE_SENTINEL}" ] || return 0
    command -v oneuser >/dev/null 2>&1 || return 0
    [ -n "${ONEADMIN_PW}" ] || return 0

    install -d -m 0700 -o oneadmin -g oneadmin /var/lib/one/.one 2>/dev/null || true
    if sudo -u oneadmin oneuser passwd oneadmin "${ONEADMIN_PW}" >/dev/null 2>&1; then
        printf 'oneadmin:%s\n' "${ONEADMIN_PW}" > /var/lib/one/.one/one_auth
        chown oneadmin:oneadmin /var/lib/one/.one/one_auth
        chmod 0600 /var/lib/one/.one/one_auth
    fi
}

ensure_services()
{
    local units=(opennebula opennebula-fireedge opennebula-gate opennebula-flow)
    for unit in "${units[@]}"; do
        systemctl enable "${unit}" >/dev/null 2>&1 || true
        systemctl is-active --quiet "${unit}" || systemctl start "${unit}" >/dev/null 2>&1 || true
    done
}

install_oneform()
{
    # OneForm (opennebula-form) is the native provisioning engine: it adds more
    # KVM nodes and clusters to this front-end (oneform/oneprovider/oneprovision,
    # Terraform plus Ansible/one-deploy under the hood). miniONE configures the
    # OpenNebula apt repo, so the package and its deps resolve here on first boot.
    [ -f "${MINIONE_SENTINEL}" ] || return 0
    case "${ONEAPP_ONE_FORM^^}" in
        NO|FALSE|0|'') return 0 ;;
    esac

    export DEBIAN_FRONTEND=noninteractive HOME=/root
    install -d -m 0755 "${APP_LOG_DIR}"
    # Install only if missing (the front-end install may already pull it in).
    if ! command -v oneform >/dev/null 2>&1; then
        msg info "Installing OneForm (oneprovision: provision more nodes/clusters)"
        apt-get install -y opennebula-form >"${APP_LOG_DIR}/oneform.log" 2>&1 \
            || msg warning "OneForm install failed, see ${APP_LOG_DIR}/oneform.log (the lab is up regardless)"
    fi
    # Always enable and start the OneForm server. The package ships
    # opennebula-form.service disabled, and oneprovision talks to it on :13013,
    # so this must run whether we installed it or the front-end already had it.
    if command -v oneform >/dev/null 2>&1; then
        systemctl enable --now opennebula-form >>"${APP_LOG_DIR}/oneform.log" 2>&1 || true
        msg info "OneForm ready (opennebula-form service started)"
    fi
    return 0
}

write_service_report()
{
    local ip hyp one_ver
    ip=$(get_local_ip 2>/dev/null || hostname -I | awk '{print $1}')
    if [ -e /dev/kvm ]; then hyp='KVM (hardware accelerated)'; else hyp='QEMU (software emulation, host has no nested virtualization)'; fi
    one_ver=$(dpkg-query -W -f='${Version}' opennebula 2>/dev/null | cut -d- -f1)
    [ -n "${one_ver}" ] || one_ver='latest'

    cat > "${ONE_SERVICE_REPORT}" <<EOF
[OpenNebula Front-end]
FireEdge web UI:   http://${ip}:${FIREEDGE_PORT}/fireedge
Sunstone proxy:    http://${ip}/  (if enabled by miniONE)
oned XML-RPC API:  http://${ip}:2633/RPC2
Login user:        oneadmin
Login password:    ${ONEADMIN_PW}
SSH:               ssh root@${ip}

[Lab]
Deployment:        ${ONEAPP_ONE_MODE}
OpenNebula:        ${one_ver}
Hypervisor:        ${hyp}
Lab vnet:          ${ONEAPP_ONE_VNET_ADDRESS}/24 (Front-end + KVM node)
Add more nodes:    $(command -v oneprovision >/dev/null 2>&1 && echo 'OneForm installed, run: oneprovision' || echo 'OneForm not installed (set ONEAPP_ONE_FORM=YES)')
Provisioning log:  ${MINIONE_LOG}

[Notes]
This is an evaluation / training lab, not a production deployment.
For usable guest-VM performance, run it on a host that exposes nested
virtualization (host-passthrough CPU and kvm nested=1).
EOF
    chmod 0644 "${ONE_SERVICE_REPORT}"
}

###############################################################################
# Cleanup
###############################################################################

postinstall_cleanup()
{
    rm -f /usr/sbin/policy-rc.d
    apt-get autoremove -y
    apt-get autoclean
    rm -rf /var/lib/apt/lists/*
    find /var/log -type f -exec truncate -s 0 {} \;
    rm -f /etc/netplan/90-NM-*.yaml
}
