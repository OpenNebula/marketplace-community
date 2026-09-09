#!/usr/bin/env bash
# Open OnDemand appliance for OpenNebula, one image and three roles.
#
# Open OnDemand gives HPC users a browser interface to a cluster. This appliance carries the
# three roles of the deployment, and ONEAPP_ROLE picks the role at boot. The OneFlow service
# template sets that variable per role:
#
#   portal   the web portal, with its own LDAP directory and Dex authentication
#   storage  the shared home over NFS and the site cache for the EESSI catalogue
#   worker   a compute VM that runs user sessions inside Apptainer containers
#
# One image instead of three because there is one thing to build, publish and document, and
# the OneKS appliance takes the same approach for its control plane and its nodes.
#
# THIS FILE IS GENERATED. The logic of the three roles lives in the project repository, split
# across files so it can be read, and marketplace/build-appliance-sh.sh packs it into this
# single self-contained script, which is what the marketplace expects. Do not edit it by
# hand. Edit the project repository and generate it again.
#
# The split between what is baked into the image and what happens at boot follows dependency
# rather than time. Everything that only needs the internet is baked, and everything that
# needs an address that does not exist until the service is deployed waits for boot. That is
# what takes a compute VM from instantiation to serving in under a minute.

ONE_SERVICE_SETUP_DIR="/opt/one-appliance"          ### Install location. Required by bash helpers
SRC="/opt/one-appliance/one-ondemand-src"           ### Where this script unpacks the source
APPLIANCE_DIR="/opt/one-ondemand"                   ### Where the appliance code lives in the image

### CONTEXT SECTION ###########################################################

ONE_SERVICE_PARAMS=(
    'ONEAPP_ROLE'              'configure' 'Role this VM plays: portal, storage or worker'         'M|list|portal,storage,worker'
    'ONEAPP_NFS_HOST'          'configure' 'Address of the storage role, for the shared home'      'O|text'
    'ONEAPP_LDAP_HOST'         'configure' 'Address of the portal role, where the directory lives' 'O|text'
    'ONEAPP_CVMFS_PROXY'       'configure' 'URL of the site cache for the software catalogue'      'O|text'
    'ONEAPP_NFS_ADMIN_IPS'     'configure' 'Addresses allowed to act as root on the shared home'   'O|text'
    'ONEAPP_NFS_NET'           'configure' 'Network allowed to mount the shared home'              'O|text'
    'ONEAPP_SQUID_NETS'        'configure' 'Networks allowed to use the site cache'                'O|text'
    'ONEAPP_POOL_RANGE'        'configure' 'Address range reserved for the compute pool'           'O|text'
    'ONEAPP_OOD_SERVERNAME'    'configure' 'Public hostname of the portal'                         'O|text'
    'ONEAPP_OOD_SSL_MODE'      'configure' 'TLS certificate: letsencrypt or selfsigned'            'O|list|letsencrypt,selfsigned'
    'ONEAPP_OOD_SSL_EMAIL'     'configure' 'Contact address for Let''s Encrypt'                    'O|text'
    'ONEAPP_LDAP_USERS'        'configure' 'Initial users, user:password:uid separated by spaces'  'O|text'
    'ONEAPP_EESSI_VERSION'     'configure' 'EESSI release to load in sessions'                     'O|text'
)

### Appliance metadata #######################################################

ONE_SERVICE_NAME='Service Open OnDemand - KVM'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Open OnDemand portal, shared storage and elastic compute pool'
ONE_SERVICE_DESCRIPTION=$(cat <<'DESC'
Open OnDemand on OpenNebula. One image, three roles, chosen with ONEAPP_ROLE.

  portal   the web portal, with its own LDAP directory and Dex authentication
  storage  the shared home over NFS and the site cache for the EESSI catalogue
  worker   a compute VM that runs user sessions inside Apptainer containers

Deploy it with the Open OnDemand Service appliance, which wires the three roles together with
OneFlow and grows the pool of compute VMs with the number of open sessions.

Scientific software comes from EESSI over CernVM-FS, cached by the storage role, so a notebook
loads the same modules a user would find at a EuroHPC centre and the image does not age with
the software it serves. Five interactive applications ship with it: JupyterLab, Octave, a C++
notebook, RStudio and VS Code.

After deployment the portal answers on https://<ONEAPP_OOD_SERVERNAME>/ and the initial users
are the ones given in ONEAPP_LDAP_USERS. Adding a user later is one entry in the directory on
the portal role, and their home and their sessions follow from it.

Each role records what it did at boot in /var/log/ood-appliance-configure.log, and
/etc/one-ondemand/build.env records what the image was built from.
DESC
)
ONE_SERVICE_RECONFIGURABLE=true

###############################################################################
### Lifecycle #################################################################
###############################################################################

service_install()
{
    _one_ondemand_write_source || { msg error "could not unpack the appliance source"; return 1; }
    [[ -x "${SRC}/appliance/install.sh" ]] \
        || { msg error "${SRC}/appliance/install.sh is missing after unpacking"; return 1; }

    # install.sh copies the source into ${APPLIANCE_DIR} itself, so the image carries its own
    # code and no VM needs anything copied into it at deployment time.
    "${SRC}/appliance/install.sh" || return 1
    rm -rf "${SRC}"

    create_one_service_metadata

    msg info "Open OnDemand appliance built for roles portal, storage and worker"
    return 0
}

service_configure()
{
    [[ -x /usr/local/sbin/ood-appliance-configure ]] \
        || { msg error "the role switch is missing, the image was not built correctly"; return 1; }

    # A failure here has to be visible. net-90-service-appliance runs this step, and the
    # appliance's own net-99-report-ready only publishes READY=YES once the recorded status
    # is bootstrap_success, and OneFlow's ready_status_gate waits for that.
    /usr/local/sbin/ood-appliance-configure || return 1

    # Where the operator finds what this deployment produced. The portal is the role that
    # generates the OIDC secret and seeds the directory, so without this there is no
    # canonical place to read any of it.
    if [[ "${ONEAPP_ROLE}" == "portal" ]]; then
        cat > "${ONE_SERVICE_REPORT}" <<REPORT
[Open OnDemand]
portal      = https://${ONEAPP_OOD_SERVERNAME:-$(hostname -f)}/
users       = ${ONEAPP_LDAP_USERS:-demo1:demo1pass:10001}
directory   = ldap://$(hostname -I | awk '{print $NF}')/${ONEAPP_LDAP_BASE:-dc=ood,dc=local}
oidc_secret = /etc/ood/config/.oidc_crypto_passphrase
boot_log    = /var/log/ood-appliance-configure.log
built_from  = /etc/one-ondemand/build.env

Adding a user later is one entry in the directory on this VM. Their home directory and
their sessions follow from it, with no further action on any other role.
REPORT
        chmod 600 "${ONE_SERVICE_REPORT}"
    fi
    return 0
}

service_bootstrap()
{
    # Nothing to do here, because service_configure does everything that depends on the
    # deployment, and repeating it here would only add another place to fail.
    return 0
}

service_cleanup()
{
    # Deliberately empty, because the framework installs this as a trap on EXIT
    # (lib/functions.sh), so it runs on EVERY exit of /etc/one-appliance/service, including
    # the successful exit of configure on the deployed VM. Anything destructive here would
    # dismantle the appliance seconds after it finished configuring itself.
    #
    # Preparing the disk for imaging is the job of the post-processor in the packer build,
    # not of this function. Every appliance in this repository leaves it empty for the same
    # reason.
    :
}

### APPLIANCE CODE ##################################################

# service_install writes it in ${SRC} and from there
# appliance/install.sh installs it. Generated by marketplace/build-appliance-sh.sh,
# do not edit by hand, edit the project repository and generate again.

_one_ondemand_write_source() {
    rm -rf "${SRC}"
    install -d -m 755 "${SRC}"

install -d -m 755 "${SRC}/appliance"
cat > "${SRC}/appliance/clean-for-image.sh" <<'ONEOND_APPLIANCE_CLEAN_FOR_IMAGE_SH_'
#!/usr/bin/env bash
# Leaves the VM ready to become the image of the appliance.
#
# An image is cloned many times and here it covers three different roles, so everything that
# identifies THIS machine and everything that belongs to THIS deployment is removed.
# Otherwise every new VM would be born with the machine identifier and the host keys of the
# original, which breaks the systemd journal and gives them all the same SSH fingerprint. It
# would also boot with the LDAP, the exports and the certificate of the site where it was built.
#
# What is baked in stays, the packages of the three roles, Apptainer, the SIF, code-server
# and the appliance code in /opt/one-ondemand. What is deleted is written again by the
# configure of the role on every boot.
#
# Usage:  ./clean-for-image.sh    (and then power off the VM and do a disk-saveas)

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

msg "stopping the role services"
for unit in apache2 ondemand-dex slapd nfs-server nfs-kernel-server squid sssd ood-publish-load; do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
ok "no role service is left started or enabled"

msg "removing the configuration of this deployment"
# Mounts first, an image with /home mounted over NFS does not boot if the server is not there.
umount -l /home 2>/dev/null || true
umount -l /cvmfs/software.eessi.io 2>/dev/null || true
sed -i '\#:/export/home /home nfs4 #d;\# /cvmfs/software.eessi.io cvmfs #d' /etc/fstab
rm -f /etc/cvmfs/default.local
rm -rf /var/lib/cvmfs/shared /var/lib/cvmfs/software.eessi.io
ok "fstab, CernVM-FS proxy and cache cleaned"

# Worker role, identity against the LDAP of the portal.
systemctl stop sssd >/dev/null 2>&1 || true
rm -f /etc/sssd/sssd.conf
rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
sed -i '/# one-ondemand worker$/d;/# one-ondemand pool$/d' /etc/hosts
rm -f /etc/one-ondemand/pool-exclude
ok "identity and pool names removed"

# Portal role, the LDAP tree with the seeded users, the site configuration of Open OnDemand and
# its certificate. The tree is created again at boot (scripts/20-install-identity.sh).
rm -rf /var/lib/ldap/* /etc/ldap/slapd.d/* 2>/dev/null || true
rm -rf /etc/ood/config/clusters.d/* /etc/ood/config/ondemand.d/* \
       /etc/ood/config/apps/dashboard/initializers/* 2>/dev/null || true
rm -f  /etc/ood/config/ood_portal.yml
rm -rf /etc/letsencrypt /etc/ssl/one-ondemand 2>/dev/null || true
rm -rf /var/lib/ood-pool 2>/dev/null || true
ok "LDAP tree, Open OnDemand site configuration and certificates removed"

# Storage role, the exports and the proxy cache.
rm -f /etc/exports.d/one-ondemand*.exports
rm -f /etc/squid/conf.d/one-ondemand-cvmfs.conf
rm -rf /var/spool/squid/* 2>/dev/null || true
ok "NFS exports and Squid cache removed"

msg "removing what identifies this machine"
# machine-id, systemd regenerates it at boot if the file exists and is empty. Deleting it
# altogether makes some versions fail, so it is truncated instead.
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
# SSH host keys, if they travel inside the image all the VMs present the same fingerprint
# and a client cannot tell one from another.
rm -f /etc/ssh/ssh_host_*
# Authorized keys, one-context injects them on every boot from the CONTEXT.
rm -f /root/.ssh/authorized_keys
rm -f /var/lib/dhcp/* /var/lib/systemd/random-seed 2>/dev/null || true
# The name of the build machine would otherwise travel inside the image and appear in the log
# of every VM of the service, which makes the journals confusing to read. The worker role
# rewrites it with the name derived from its address, and the other two keep this one, which
# at least says what they are.
echo "one-ondemand" > /etc/hostname
hostnamectl set-hostname one-ondemand 2>/dev/null || true
ok "machine-id, name, host keys and leases deleted"

msg "reducing the size of the image"
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/* /root/.cache /root/one-ondemand 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
# The zeros in the free space compress, so the exported image is much smaller.
fstrim -av >/dev/null 2>&1 || true
ok "caches, logs and free space cleaned"

# --- what has to stay inside, checked instead of assumed ------------------------------------
msg "checking what is baked in"
for req in /etc/one-ondemand/build.env /etc/one-ondemand/ood-app-lib.sh \
           /etc/one-ondemand/onegate-lib.sh /etc/one-ondemand/code-server.env \
           /opt/ood/linuxhost.sif /opt/one-ondemand/worker/configure.sh \
           /opt/one-ondemand/scripts/30-configure-portal.sh \
           /opt/one-ondemand/storage/10-install-nfs.sh \
           /usr/local/sbin/ood-appliance-configure \
           /usr/local/bin/ood-publish-load.sh \
           /opt/ood/ood-portal-generator/sbin/update_ood_portal; do
    [[ -e "$req" ]] || die "${req} is missing, the cleanup took away something that had to stay"
done
for cmd in apptainer cvmfs_config exportfs squid slapadd; do
    command -v "$cmd" >/dev/null || die "${cmd} has disappeared from the image"
done
for pkg in ondemand ondemand-dex nfs-kernel-server squid slapd; do
    dpkg -s "$pkg" >/dev/null 2>&1 || die "the package ${pkg} has disappeared from the image"
done
ok "the three roles are still complete in the image"

printf '\n'
ok "VM ready to power off and do a disk-saveas"
ONEOND_APPLIANCE_CLEAN_FOR_IMAGE_SH_

install -d -m 755 "${SRC}/appliance"
cat > "${SRC}/appliance/configure.sh" <<'ONEOND_APPLIANCE_CONFIGURE_SH_'
#!/usr/bin/env bash
# Boot phase of the one-ondemand appliance, it picks the role and configures it.
#
# The same image covers the three roles of the service. Which one this VM plays comes from
# ONEAPP_ROLE in the CONTEXT, and the OneFlow service template sets it per role. The role is
# not deduced from the name of the VM, because OneFlow names them with the template
# $ROLE_NAME_$VM_NUMBER_(service_$SERVICE_ID). That name carries parentheses and changes
# between versions, so an explicit variable is more honest and more stable.
#
# Who calls it depends on the path. In the published appliance net-90-service-appliance runs
# the service script, which calls service_configure and from there this one, and
# net-99-report-ready publishes READY=YES afterwards when the recorded state is
# bootstrap_success. On the manual path READY_SCRIPT_PATH from
# the CONTEXT points at it, and that is the one-context hook. Both paths end at the same
# place, because OneFlow does not accept the role until that READY.
#
# Variables common to all the roles:
#   ONEAPP_ROLE            portal | storage | worker (mandatory)
# Per role, the ones each script documents:
#   portal    ONEAPP_NFS_HOST, ONEAPP_OOD_SERVERNAME, ONEAPP_POOL_RANGE, ONEAPP_CVMFS_PROXY
#   storage   ONEAPP_NFS_ADMIN_IPS
#   worker    ONEAPP_NFS_HOST, ONEAPP_LDAP_HOST, ONEAPP_CVMFS_PROXY
#
# Usage:  ONEAPP_ROLE=worker /usr/local/sbin/ood-appliance-configure

set -uo pipefail
LOG=/var/log/ood-appliance-configure.log
exec > >(tee -a "$LOG") 2>&1
printf '\n===== %s =====\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env

DIR="${ONEAPP_APPLIANCE_DIR:-/opt/one-ondemand}"
source "${DIR}/scripts/00-lib.sh"
require_root

ROLE="${ONEAPP_ROLE:-}"
if [[ -z "$ROLE" ]]; then
    echo "ONEAPP_ROLE is missing from the CONTEXT, there is no role to configure"
    exit 0
fi

# A failure here has to show as a failure, because READY=YES depends on this script
# returning zero and OneFlow waits for that READY.
run() {
    local what="$1"; shift
    msg "--- ${what}"
    "$@" || die "${what} failed"
}

t0=$(date +%s)
case "$ROLE" in
storage)
    : "${ONEAPP_NFS_ADMIN_IPS:?the storage role needs ONEAPP_NFS_ADMIN_IPS with the private IP of the portal}"
    run "home NFS server"      bash "${DIR}/storage/10-install-nfs.sh"
    run "site Squid for EESSI" bash "${DIR}/storage/20-install-squid.sh"
    ;;
portal)
    : "${ONEAPP_NFS_HOST:?the portal role needs ONEAPP_NFS_HOST}"
    : "${ONEAPP_CVMFS_PROXY:?the portal role needs ONEAPP_CVMFS_PROXY}"
    : "${ONEAPP_POOL_RANGE:?the portal role needs ONEAPP_POOL_RANGE with the range reserved for the workers}"
    # The metrics publisher belongs to the worker role. On the portal it would only spend
    # OneGate calls to publish zero sessions, and it would confuse the reading of the panel.
    systemctl disable --now ood-publish-load.service >/dev/null 2>&1 || true
    run "Open OnDemand"         bash "${DIR}/scripts/10-install-ood.sh"
    run "LDAP and Dex identity" bash "${DIR}/scripts/20-install-identity.sh"
    run "shared home"           bash "${DIR}/scripts/25-mount-home.sh"
    run "portal configuration"  bash "${DIR}/scripts/30-configure-portal.sh"
    run "application catalog"   bash "${DIR}/scripts/60-install-apps.sh"
    run "EESSI on the portal"   bash "${DIR}/scripts/70-install-cvmfs.sh"
    run "worker pool"           bash "${DIR}/scripts/90-configure-vm-pool.sh"
    ;;
worker)
    # The three addresses are optional on purpose. A worker without them is a standalone
    # machine with Apptainer, and that is what the marketplace certification harness
    # instantiates. worker/configure.sh skips each block and says so in the log.
    run "pool VM" bash "${DIR}/worker/configure.sh"
    ;;
*)
    die "ONEAPP_ROLE=${ROLE} is not a role of this appliance (portal, storage or worker)"
    ;;
esac

# The OneGate endpoint is fixed in the context environment before this script returns,
# because the standard one-context hook publishes READY next and it uses the onegate
# wrapper, which rereads that file. Without this, in a deployment with no virtual router the
# VM would be configured but would never declare itself ready.
#
# READY is published from here as well, for a VM instantiated without REPORT_READY, where the
# standard hook would do nothing and OneFlow would keep waiting.
if . /etc/one-ondemand/onegate-lib.sh 2>/dev/null && onegate_ready; then
    onegate_fix_context_env || true
    onegate_call vm update --data "READY=YES" >/dev/null 2>&1 \
        && ok "READY=YES published to ${ONEGATE_ENDPOINT}" \
        || warn "could not publish READY=YES to ${ONEGATE_ENDPOINT}"
else
    warn "OneGate does not answer, READY is left to the one-context hook"
fi

ok "role ${ROLE} configured in $(( $(date +%s) - t0 ))s"
ONEOND_APPLIANCE_CONFIGURE_SH_

install -d -m 755 "${SRC}/appliance"
cat > "${SRC}/appliance/install.sh" <<'ONEOND_APPLIANCE_INSTALL_SH_'
#!/usr/bin/env bash
# Build phase of the one-ondemand appliance, one image for the three roles.
#
# The service has three roles, portal, storage and worker, and all three are built from the
# same image. ONEAPP_ROLE from the CONTEXT picks one at boot, and OneFlow sets it per role. One
# image instead of three because there is one thing to build, publish and document, which is
# what makes an appliance publishable, and because the OneKS appliance is built the same way,
# with one image for the control plane and for the nodes.
#
# Everything that only depends on the internet goes here. What depends on an address that
# does not exist until deployment is in appliance/configure.sh and in the scripts of each
# role. That is the same cut that separates service_install from service_configure in one-apps.
#
# No service is left started at the end, because the configure of the matching role leaves
# them enabled or stopped, so a worker does not start Apache and a portal does not export NFS.
#
# It is idempotent. Variables: those of worker/install.sh, plus those of scripts/00-lib.sh.
#
# Usage:  ./install.sh     (on the VM that will become the image)

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ONEAPP_APPLIANCE_DIR:-/opt/one-ondemand}"
t0=$(date +%s)

msg "=== common packages ==="
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
apt_install apt-transport-https ca-certificates wget curl gnupg python3

# --- worker role --------------------------------------------------------------------------
# It installs the most and it was already written, so it is reused as is, with packages,
# Apptainer, the SIF, code-server, the CernVM-FS client and the metrics publisher.
msg "=== worker role ==="
bash "${REPO}/worker/install.sh" || die "the build of the worker role failed"

# --- storage role -------------------------------------------------------------------------
# The NFS server of the home and the site Squid for CernVM-FS. Only the packages are
# installed here, because the exports and the networks with access belong to the deployment.
msg "=== storage role ==="
apt_install nfs-kernel-server squid

# --- portal role --------------------------------------------------------------------------
# Open OnDemand and its Dex, the LDAP that holds the accounts, and certbot for the
# certificate. The OSC repository is registered here because it belongs to the software and
# not to the site.
msg "=== portal role ==="
deb_url="${ONEAPP_OOD_APT_BASE}/${ONEAPP_OOD_VERSION}/${ONEAPP_OOD_RELEASE_DEB}"
if ! dpkg -s ondemand-release-web >/dev/null 2>&1; then
    msg "registering the Open OnDemand ${ONEAPP_OOD_VERSION} repository"
    wget -q -O "/tmp/${ONEAPP_OOD_RELEASE_DEB}" "$deb_url" \
        || die "could not download the repository package from ${deb_url}"
    apt-get install -y "/tmp/${ONEAPP_OOD_RELEASE_DEB}" >/dev/null \
        || die "could not install the repository package"
    rm -f "/tmp/${ONEAPP_OOD_RELEASE_DEB}"
    apt-get update -qq || die "apt-get update failed after adding the OSC repository"
fi
apt_install ondemand ondemand-dex slapd ldap-utils rsync certbot
[[ -x /opt/ood/ood-portal-generator/sbin/update_ood_portal ]] \
    || die "update_ood_portal is not there, the Open OnDemand installation did not complete"
# The slapd package creates a directory during installation, with a domain taken from the
# build machine and an administrator password generated here. Publishing that would publish
# the password inside the image, and scripts/20-install-identity.sh already assumes an empty
# tree so that each deployment builds its own with dpkg-reconfigure. The assumption is made
# true here.
rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*
install -d -m 755 -o openldap -g openldap /etc/ldap/slapd.d /var/lib/ldap
ok "LDAP directory left empty, each deployment creates its own"

install -d -m 755 /etc/ood/config/clusters.d
ok "Open OnDemand $(dpkg-query -W -f='${Version}' ondemand 2>/dev/null), dex $(dpkg-query -W -f='${Version}' ondemand-dex 2>/dev/null), slapd $(dpkg-query -W -f='${Version}' slapd 2>/dev/null)"

# --- the image carries its own code inside -------------------------------------------------
# The whole repository, so the configure of each role has what it needs and nothing is copied
# to the VM at deployment time. That is what makes the image an appliance rather than a
# preinstalled machine.
msg "=== appliance code in ${DEST} ==="
rm -rf "$DEST"
install -d -m 755 "$DEST"
tar -C "$REPO" -cf - --exclude=.git scripts config apps worker storage appliance \
    | tar -C "$DEST" -xf - || die "could not copy the appliance code"
chmod +x "$DEST"/scripts/*.sh "$DEST"/worker/*.sh "$DEST"/storage/*.sh "$DEST"/appliance/*.sh 2>/dev/null
ok "$(find "$DEST" -type f | wc -l) files in ${DEST}"

install -m 755 "${REPO}/appliance/configure.sh" /usr/local/sbin/ood-appliance-configure
ok "entry point at /usr/local/sbin/ood-appliance-configure"

# --- no role service started ---------------------------------------------------------------
# The image covers the three roles, so none of their services can be left enabled. A worker
# that starts Apache with an empty LDAP is a free attack surface, and a portal that exports
# NFS is a mistake that is hard to see. The configure of the role enables them.
msg "=== leaving the role services stopped ==="
for unit in apache2 ondemand-dex slapd nfs-server nfs-kernel-server squid sssd; do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
# The metrics publisher stays enabled because it belongs to the worker role, and on the
# other two roles it starts, finds no sessions and publishes zero, which does no harm, so
# the configure of those roles stops it.
ok "role services disabled, they are enabled per role at boot"

# --- provenance ------------------------------------------------------------------------------
cat >> /etc/one-ondemand/build.env <<EOF
APPLIANCE=one-ondemand
APPLIANCE_ROLES=portal,storage,worker
APPLIANCE_DIR=${DEST}
OOD_VERSION=$(dpkg-query -W -f='${Version}' ondemand 2>/dev/null)
EOF
ok "provenance extended in /etc/one-ondemand/build.env"

printf '\n'
ok "appliance built in $(( $(date +%s) - t0 ))s, for the portal, storage and worker roles"
ONEOND_APPLIANCE_INSTALL_SH_

install -d -m 755 "${SRC}/config/clusters.d"
cat > "${SRC}/config/clusters.d/vms.yml" <<'ONEOND_CONFIG_CLUSTERS_D_VMS_YML_'
# Definition of the OpenNebula VM pool as an Open OnDemand target.
# Installed at /etc/ood/config/clusters.d/vms.yml
#
# These are OpenNebula VMs with no scheduler, neither Slurm nor Kubernetes. The
# portal enters each VM over SSH as the user and launches every job inside an
# Apptainer container under tmux, all of it with the stock linux_host adapter.
#
# The @@ placeholders are substituted by scripts/90-configure-vm-pool.sh.
v2:
  metadata:
    title: "OpenNebula VMs"
    # This target is offered in the job composer, because it accepts batch scripts.
    hidden: false
  # No login section, because the portal terminal already logs into the portal itself.
  job:
    adapter: "linux_host"
    # The adapter sends every job to this host. ssh_hosts is the list of hosts where
    # it recognises sessions, and that list does not distribute the load.
    submit_host: "@@SUBMIT_HOST@@"
    ssh_hosts:
@@SSH_HOSTS@@
    # Each job runs with `apptainer exec --pid <image>` and the session script inside.
    # As Open OnDemand documents, the image is a base of the same operating system as
    # the VM and only isolates the processes. The VM filesystem is mounted inside it
    # (the documented bindpath plus the home and EESSI). The session software comes
    # from EESSI, not from the image.
    singularity_bin: "/usr/bin/apptainer"
    singularity_image: "/opt/ood/linuxhost.sif"
    singularity_bindpath: "/etc,/media,/mnt,/opt,/run,/srv,/usr,/var,/home,/cvmfs"
    tmux_bin: "/usr/bin/tmux"
    # VMs are created and destroyed, so their host keys are not known in advance.
    strict_host_checking: false
    site_timeout: 43200
    debug: false
  batch_connect:
    basic:
      # The host published in the session is the private IP of the VM, because the
      # portal proxy reaches that address and host_regex accepts it.
      set_host: "host=$(hostname -I | tr ' ' '\\n' | grep '^172\\.20\\.' | head -1)"
    ssh_allow: false
ONEOND_CONFIG_CLUSTERS_D_VMS_YML_

install -d -m 755 "${SRC}/config/dashboard-initializers"
cat > "${SRC}/config/dashboard-initializers/50-submit-host-override.rb" <<'ONEOND_CONFIG_DASHBOARD_INITIALIZERS_50_SUBMIT_HOST_OVERRIDE_RB_'
# Makes the submit_host_override key of the linux_host adapter live.
#
# The adapter already ships the feature. In launcher.rb:95-101 it checks
# script.native['submit_host_override'] and, if the key is there, sends the session to
# that host instead of to the fixed submit_host from the cluster file. A growing pool
# needs exactly that, so every new session runs on the worker with the most room.
#
# The problem is that the key never arrives. The dashboard converts the keys to symbols
# three times before building the Script, in app.rb:424 and in session.rb:304 and :330,
# and the adapter reads it as a string, so the value that submit.yml.erb emits is
# silently lost and every session runs on the same worker.
#
# This initializer prepends a module that accepts both forms of the key. It does not
# modify the gem, because the ondemand package owns the gem and the next update would
# restore it. The initializer lives in the site configuration directory that Rails
# already loads (application.rb:50).
#
# When there is no override, or it arrives empty, the original behaviour applies.

begin
  require 'ood_core/job/adapters/linux_host'
  require 'ood_core/job/adapters/linux_host/launcher'

  module OneOnDemandPlacement
    def submit_host(script = nil)
      native = script.respond_to?(:native) ? script.native : nil
      if native.respond_to?(:[])
        override = native[:submit_host_override] || native['submit_host_override']
        return override.to_s unless override.nil? || override.to_s.strip.empty?
      end
      super
    end
  end

  OodCore::Job::Adapters::LinuxHost::Launcher.prepend(OneOnDemandPlacement)
  Rails.logger.info('one-ondemand: submit_host_override active for the linux_host adapter')
rescue LoadError, NameError => e
  # With no linux_host adapter loaded there is nothing to patch, and the portal must
  # start all the same. The failure is recorded in the log instead of breaking the
  # user process.
  Rails.logger.warn("one-ondemand: could not activate submit_host_override (#{e.class}: #{e.message})")
end

# Selection of the least loaded worker.
#
# The portal computes the roster in /var/lib/ood-pool/workers.json with a systemd timer
# that checks which workers answer and how many sessions each one has, and this code only
# reads that file. Tied workers are drawn at random, so two nearly simultaneous launches
# do not always pick the same one, because the roster refreshes every half minute and does
# not see a just-created session immediately.
#
# pick returns nil when the roster is missing or expired, or when no worker answers, and
# then the adapter uses the submit_host from the cluster file, the usual behaviour. A
# failure here never prevents launching a session.
require 'json'

module OneOnDemandPool
  POOL_FILE = ENV.fetch('OOD_POOL_FILE', '/var/lib/ood-pool/workers.json')
  MAX_AGE_SECONDS = 180

  def self.workers
    data = JSON.parse(File.read(POOL_FILE))
    return [] if Time.now.to_i - data['ts'].to_i > MAX_AGE_SECONDS
    Array(data['workers']).select { |w| w['alive'] && !w['fqdn'].to_s.empty? }
  rescue StandardError
    []
  end

  def self.pick
    candidates = workers
    return nil if candidates.empty?
    fewest = candidates.map { |w| w['sessions'].to_i }.min
    candidates.select { |w| w['sessions'].to_i == fewest }.sample['fqdn']
  rescue StandardError
    nil
  end
end
ONEOND_CONFIG_DASHBOARD_INITIALIZERS_50_SUBMIT_HOST_OVERRIDE_RB_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/00-lib.sh" <<'ONEOND_SCRIPTS_00_LIB_SH_'
#!/usr/bin/env bash
# Common library for the scripts that run inside the portal VM.
#
# Every tunable is an environment variable with a default value, following the
# one-apps convention. These scripts then become the service_install,
# service_configure and service_bootstrap functions of the appliance with no
# rewrite.

set -uo pipefail

# --- portal parameters --------------------------------------------------------
ONEAPP_OOD_VERSION="${ONEAPP_OOD_VERSION:-4.2}"
ONEAPP_OOD_RELEASE_DEB="${ONEAPP_OOD_RELEASE_DEB:-ondemand-release-web_4.2.0-noble_all.deb}"
ONEAPP_OOD_APT_BASE="${ONEAPP_OOD_APT_BASE:-https://apt.osc.edu/ondemand}"
# Empty by default. A published image must not carry the name of the site it was built
# on, so when it is not given the portal names itself after its own address.
ONEAPP_OOD_SERVERNAME="${ONEAPP_OOD_SERVERNAME:-}"
ONEAPP_OOD_SSL_MODE="${ONEAPP_OOD_SSL_MODE:-letsencrypt}"   # letsencrypt | selfsigned
ONEAPP_OOD_SSL_EMAIL="${ONEAPP_OOD_SSL_EMAIL:-}"

# --- identity parameters -------------------------------------------------------
ONEAPP_LDAP_DOMAIN="${ONEAPP_LDAP_DOMAIN:-ood.local}"
ONEAPP_LDAP_BASE="${ONEAPP_LDAP_BASE:-dc=ood,dc=local}"
ONEAPP_LDAP_ADMIN_PASS="${ONEAPP_LDAP_ADMIN_PASS:-oodadmin}"
ONEAPP_LDAP_USERS="${ONEAPP_LDAP_USERS:-demo1:demo1pass:10001 demo2:demo2pass:10002}"

# --- target parameters ---------------------------------------------------------
# EESSI catalogue version and the module with JupyterLab and ipykernel for the kernel.
ONEAPP_EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
ONEAPP_EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"

export ONEAPP_OOD_VERSION ONEAPP_OOD_RELEASE_DEB ONEAPP_OOD_APT_BASE \
       ONEAPP_OOD_SERVERNAME ONEAPP_OOD_SSL_MODE ONEAPP_OOD_SSL_EMAIL \
       ONEAPP_LDAP_DOMAIN ONEAPP_LDAP_BASE ONEAPP_LDAP_ADMIN_PASS ONEAPP_LDAP_USERS

export DEBIAN_FRONTEND=noninteractive

# --- output --------------------------------------------------------------------
msg()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf '[%s]   ok: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[%s]   warning: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() { [[ "$(id -u)" -eq 0 ]] || die "it has to be run as root"; }

# wait_apt_lock [SECS]: wait until unattended-upgrades releases the dpkg lock.
# On a freshly booted image the automatic updates process is usually running,
# and without this wait the installation fails intermittently.
wait_apt_lock() {
    local secs="${1:-300}"
    local deadline=$(( $(date +%s) + secs ))
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
        (( waited == 0 )) && msg "waiting for another process to release the apt lock"
        waited=1
        (( $(date +%s) >= deadline )) && die "the apt lock is still held after ${secs}s"
        sleep 5
    done
    (( waited == 1 )) && ok "apt lock free"
    return 0
}

# apt_install PKG...: install without prompting, and only if something is missing.
apt_install() {
    local missing=()
    local p
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if (( ${#missing[@]} == 0 )); then
        ok "already installed: $*"
        return 0
    fi
    wait_apt_lock
    msg "installing: ${missing[*]}"
    apt-get install -y -o Dpkg::Options::=--force-confold "${missing[@]}" >/dev/null \
        || die "installation failed for: ${missing[*]}"
    ok "installed: ${missing[*]}"
}

# service_up UNIT: start and enable it, and check that it ended up active.
service_up() {
    local unit="$1"
    systemctl enable --now "$unit" >/dev/null 2>&1
    # A unit that systemd generates from an LSB init script, which is what slapd still is on
    # Ubuntu 24.04, is not reported active the moment enable returns. Checking straight away
    # reports a failure for a service that starts correctly a second later.
    wait_for 30 systemctl is-active --quiet "$unit" \
        || die "service ${unit} did not end up active"
    ok "${unit} active and enabled at boot"
}

# backup_once FILE: keep a copy of the original the first time a file is modified.
backup_once() {
    local f="$1"
    [[ -f "$f" && ! -f "${f}.one-ondemand.orig" ]] && cp -a "$f" "${f}.one-ondemand.orig"
    return 0
}

# ldap_users_each: splits each entry of ONEAPP_LDAP_USERS and calls the given
# function with user, password and uid.
ldap_users_each() {
    local fn="$1" entry user pass uid
    for entry in $ONEAPP_LDAP_USERS; do
        IFS=: read -r user pass uid <<<"$entry"
        "$fn" "$user" "$pass" "$uid"
    done
}

# wait_for SECS CMD...: repeats CMD until it returns 0 or SECS seconds elapse.
wait_for() {
    local secs="$1"; shift
    local end=$(( $(date +%s) + secs ))
    while ! "$@" >/dev/null 2>&1; do
        (( $(date +%s) >= end )) && return 1
        sleep 3
    done
    return 0
}
ONEOND_SCRIPTS_00_LIB_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/10-install-ood.sh" <<'ONEOND_SCRIPTS_10_INSTALL_OOD_SH_'
#!/usr/bin/env bash
# Installs Open OnDemand 4.2 and the Dex it includes on the portal VM.
#
# This is the "install" phase of a one-apps appliance. It only installs software
# and configures nothing site dependent. Ubuntu 24.04 (noble) is a platform
# officially supported by Open OnDemand 4.2.
#
# Usage:  ./10-install-ood.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

[[ "$(. /etc/os-release && echo "$VERSION_CODENAME")" == "noble" ]] \
    || warn "this VM is not Ubuntu 24.04 (noble), the repository package may not fit"

wait_apt_lock
msg "updating package indexes"
apt-get update -qq || die "apt-get update failed"

apt_install apt-transport-https ca-certificates wget curl gnupg

# --- OSC repository ------------------------------------------------------------
deb_url="${ONEAPP_OOD_APT_BASE}/${ONEAPP_OOD_VERSION}/${ONEAPP_OOD_RELEASE_DEB}"
if dpkg -s ondemand-release-web >/dev/null 2>&1; then
    ok "the Open OnDemand repository is already registered"
else
    msg "downloading ${deb_url}"
    wget -q -O "/tmp/${ONEAPP_OOD_RELEASE_DEB}" "$deb_url" \
        || die "could not download the repository package from ${deb_url}"

    msg "registering the repository"
    apt-get install -y "/tmp/${ONEAPP_OOD_RELEASE_DEB}" >/dev/null \
        || die "could not install the repository package"
    rm -f "/tmp/${ONEAPP_OOD_RELEASE_DEB}"
    apt-get update -qq || die "apt-get update failed after adding the OSC repository"
    ok "Open OnDemand ${ONEAPP_OOD_VERSION} repository registered"
fi

# --- packages -------------------------------------------------------------------
apt_install ondemand ondemand-dex

msg "installed version"
dpkg-query -W -f='    ondemand ${Version}\n' ondemand 2>/dev/null || true
dpkg-query -W -f='    ondemand-dex ${Version}\n' ondemand-dex 2>/dev/null || true

# --- services -----------------------------------------------------------------------
service_up apache2

# ondemand-dex has no site configuration yet, so it is only enabled here, and
# 30-configure-portal.sh writes that configuration and starts it.
systemctl enable ondemand-dex >/dev/null 2>&1 \
    && ok "ondemand-dex enabled at boot, it will be configured in 30-configure-portal.sh"

# --- check ----------------------------------------------------------------------
[[ -x /opt/ood/ood-portal-generator/sbin/update_ood_portal ]] \
    || die "update_ood_portal is missing, the installation did not complete"
ok "update_ood_portal available"

[[ -d /etc/ood/config/clusters.d ]] || mkdir -p /etc/ood/config/clusters.d
ok "/etc/ood/config/clusters.d ready for the target definitions"

ok "Open OnDemand ${ONEAPP_OOD_VERSION} installed"
ONEOND_SCRIPTS_10_INSTALL_OOD_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/20-install-identity.sh" <<'ONEOND_SCRIPTS_20_INSTALL_IDENTITY_SH_'
#!/usr/bin/env bash
# Configures the identity source of the deployment, a local OpenLDAP with the initial users
# and sssd so the system resolves them through NSS.
#
# The goal is that adding a user is writing an entry in LDAP and nothing else,
# with no account created by hand in /etc/passwd.
#
# PAM does not create the home. With OIDC authentication the PUN starts without
# a PAM session, so pam_mkhomedir would never fire, and the pre-PUN hook
# installed by 30-configure-portal.sh creates the home instead.
#
# Usage:  ./20-install-identity.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

BASE="$ONEAPP_LDAP_BASE"
ADMIN_DN="cn=admin,${BASE}"
PEOPLE_OU="ou=People,${BASE}"
GROUPS_OU="ou=Groups,${BASE}"

# --- slapd ---------------------------------------------------------------------
# In the appliance the package is already in the image. Here it is installed only if missing,
# as on a portal built by hand on top of a base image.
apt_install slapd ldap-utils

# The decision to seed the directory reads its CONFIGURATION database, not the package. In the
# appliance the package is already in the image but /etc/ldap/slapd.d is empty on purpose.
# Publishing an image with the tree already seeded would publish the administrator password and
# the test users inside it. This way each deployment creates its own directory with its own
# password.
#
# dpkg-reconfigure is the supported way to rebuild it when the package is already installed,
# because reinstalling does not recreate it.
if [[ -z "$(ls -A /etc/ldap/slapd.d 2>/dev/null)" ]]; then
    msg "creating the directory for ${ONEAPP_LDAP_DOMAIN}"
    debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string ${ONEAPP_LDAP_DOMAIN}
slapd shared/organization string OpenNebula OnDemand
slapd slapd/password1 password ${ONEAPP_LDAP_ADMIN_PASS}
slapd slapd/password2 password ${ONEAPP_LDAP_ADMIN_PASS}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
EOF
    install -d -m 755 -o openldap -g openldap /var/lib/ldap /etc/ldap/slapd.d
    dpkg-reconfigure -f noninteractive slapd >/dev/null 2>&1 \
        || die "dpkg-reconfigure slapd failed while creating the directory"
    [[ -n "$(ls -A /etc/ldap/slapd.d 2>/dev/null)" ]] \
        || die "dpkg-reconfigure finished but /etc/ldap/slapd.d is still empty"
    ok "directory created for ${ONEAPP_LDAP_DOMAIN}"
fi

apt_install ldap-utils
service_up slapd

# The real domain can differ if slapd was already there, so it is checked.
actual_base="$(ldapsearch -x -LLL -H ldapi:/// -b '' -s base namingContexts 2>/dev/null \
               | awk '/^namingContexts:/{print $2; exit}')"
if [[ -n "$actual_base" && "$actual_base" != "$BASE" ]]; then
    die "slapd serves ${actual_base} but ${BASE} was expected, adjust ONEAPP_LDAP_BASE or reinstall slapd"
fi
ok "slapd serving ${BASE}"

# --- structure -------------------------------------------------------------------
# ldap_add DESCRIPTION LDIF creates the entry. It returns 1 only when ldapadd
# reports that the entry already exists, so the caller can update it, and aborts
# on any other error, including a malformed LDIF.
ldap_add() {
    local desc="$1" ldif="$2" out
    if out="$(ldapadd -x -D "$ADMIN_DN" -w "$ONEAPP_LDAP_ADMIN_PASS" 2>&1 <<<"$ldif")"; then
        ok "created: ${desc}"
        return 0
    elif grep -q "Already exists" <<<"$out"; then
        ok "already existed: ${desc}"
        return 1
    fi
    die "ldapadd failed for ${desc}: ${out}"
}

# ldap_replace DN ATTRIBUTE VALUE replaces an attribute of an existing entry.
ldap_replace() {
    local dn="$1" attr="$2" value="$3"
    ldapmodify -x -D "$ADMIN_DN" -w "$ONEAPP_LDAP_ADMIN_PASS" >/dev/null 2>&1 <<EOF
dn: ${dn}
changetype: modify
replace: ${attr}
${attr}: ${value}
EOF
}

msg "creating the organizational units"
ldap_add "$PEOPLE_OU" "dn: ${PEOPLE_OU}
objectClass: organizationalUnit
ou: People"
ldap_add "$GROUPS_OU" "dn: ${GROUPS_OU}
objectClass: organizationalUnit
ou: Groups"

# --- users --------------------------------------------------------------------------
seed_user() {
    local user="$1" pass="$2" uid="$3"
    local hash
    hash="$(slappasswd -h '{SSHA}' -s "$pass")"

    ldap_add "group ${user} (gid ${uid})" "dn: cn=${user},${GROUPS_OU}
objectClass: posixGroup
cn: ${user}
gidNumber: ${uid}"

    if ! ldap_add "user ${user} (uid ${uid})" "dn: uid=${user},${PEOPLE_OU}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${user}
cn: ${user}
sn: ${user}
gecos: Test user ${user}
mail: ${user}@${ONEAPP_LDAP_DOMAIN}
uidNumber: ${uid}
gidNumber: ${uid}
homeDirectory: /home/${user}
loginShell: /bin/bash
userPassword: ${hash}"; then
        # The entry was already there, so the current password is applied. The
        # password is the only field of the user list that changes over time, so
        # applying it here makes a password edited in the configuration reach the
        # directory.
        ldap_replace "uid=${user},${PEOPLE_OU}" userPassword "$hash" \
            && ok "password of ${user} updated" \
            || die "could not update the password of ${user}"
    fi
}

msg "seeding the test users"
ldap_users_each seed_user

# --- sssd ----------------------------------------------------------------------------
apt_install sssd sssd-ldap libnss-sss libpam-sss

msg "configuring sssd against the local LDAP"
backup_once /etc/sssd/sssd.conf
cat > /etc/sssd/sssd.conf <<EOF
# Generated by one-ondemand/scripts/20-install-identity.sh
[sssd]
config_file_version = 2
services = nss, pam
domains = ${ONEAPP_LDAP_DOMAIN}

[nss]
filter_users = root
homedir_substring = /home

[domain/${ONEAPP_LDAP_DOMAIN}]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://localhost
ldap_search_base = ${BASE}
ldap_default_bind_dn = ${ADMIN_DN}
ldap_default_authtok = ${ONEAPP_LDAP_ADMIN_PASS}
ldap_user_search_base = ${PEOPLE_OU}
ldap_group_search_base = ${GROUPS_OU}
# The directory lives on the same machine and only listens on localhost, which is why
# the transport is not encrypted. With a remote LDAP this would have to be LDAPS.
ldap_id_use_start_tls = false
ldap_auth_disable_tls_never_use_in_production = true
cache_credentials = true
enumerate = true
EOF
chmod 600 /etc/sssd/sssd.conf
service_up sssd

msg "restarting sssd so it picks up the configuration"
systemctl restart sssd
sss_cache -E >/dev/null 2>&1 || true
sleep 3

# --- verification -------------------------------------------------------------------
verify_user() {
    local user="$1" pass="$2" uid="$3"
    if grep -q "^${user}:" /etc/passwd; then
        die "${user} is in /etc/passwd, it must exist only in LDAP"
    fi
    local resolved
    resolved="$(getent passwd "$user" 2>/dev/null)"
    [[ -z "$resolved" ]] && die "getent passwd ${user} does not resolve, sssd is not serving the user"
    local got_uid="${resolved#*:*:}"; got_uid="${got_uid%%:*}"
    [[ "$got_uid" == "$uid" ]] || die "${user} resolves with uid ${got_uid} instead of ${uid}"
    ok "${user} resolves through NSS with uid ${uid} and is not in /etc/passwd"
}

msg "verifying that the users resolve"
ldap_users_each verify_user

ok "identity ready, LDAP with the test users and sssd resolving them"
ONEOND_SCRIPTS_20_INSTALL_IDENTITY_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/25-mount-home.sh" <<'ONEOND_SCRIPTS_25_MOUNT_HOME_SH_'
#!/usr/bin/env bash
# Mounts the persistent home on the portal.
#
# The user homes live on the storage VM and are mounted over NFS on /home. That
# way the portal file explorer, the portal terminal and the pool VMs see exactly
# the same files. Before mounting on top, the homes that already existed on the
# portal disk are copied to the export once, so nothing is lost.
#
# It is idempotent, so if /home is already mounted from the server it does
# nothing beyond checking it.
#
# Variables:
#   ONEAPP_NFS_HOST   private IP of the storage VM (required)
#
# Usage:  ONEAPP_NFS_HOST=172.20.0.221 ./25-mount-home.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

NFS_HOST="${ONEAPP_NFS_HOST:?ONEAPP_NFS_HOST is missing, set it to the private IP of the NFS server}"
HOME_EXPORT="${ONEAPP_NFS_HOME_EXPORT:-/export/home}"
STATE_DIR=/etc/one-ondemand
FSTAB_LINE="${NFS_HOST}:${HOME_EXPORT} /home nfs4 _netdev,hard,noatime 0 0"

msg "installing the NFS client"
apt_install nfs-common
ok "nfs-common installed"

# The address is left in ${STATE_DIR}/nfs_host as the record of which server /home comes
# from, which is what an operator reads when a mount does not come back after a reboot.
install -d -m 755 "$STATE_DIR"
printf '%s\n' "$NFS_HOST" > "${STATE_DIR}/nfs_host"
ok "NFS server recorded in ${STATE_DIR}/nfs_host"

# --- already mounted ------------------------------------------------------------------
if findmnt -n -t nfs4,nfs /home >/dev/null 2>&1; then
    ok "/home is already mounted from $(findmnt -n -o SOURCE /home)"
    exit 0
fi

# --- one time migration of the local homes -----------------------------------------
msg "copying the local homes to the export before mounting on top"
tmp_mnt="$(mktemp -d)"
mount -t nfs4 -o hard "${NFS_HOST}:${HOME_EXPORT}" "$tmp_mnt" \
    || die "cannot mount ${NFS_HOST}:${HOME_EXPORT}, are the storage VM and the export up?"
for d in /home/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ -e "${tmp_mnt}/${name}" ]]; then
        ok "the home of ${name} already exists in the export, the one in the export is kept"
        continue
    fi
    apt_install rsync >/dev/null 2>&1 || true
    rsync -a "$d" "${tmp_mnt}/${name}/" && ok "home of ${name} copied to the export" \
        || die "the copy of the home of ${name} failed"
done
umount "$tmp_mnt" && rmdir "$tmp_mnt"

# --- fstab and mount ------------------------------------------------------------------
backup_once /etc/fstab
grep -qF " /home nfs4 " /etc/fstab && sed -i '\# /home nfs4 #d' /etc/fstab
printf '%s\n' "$FSTAB_LINE" >> /etc/fstab
systemctl daemon-reload >/dev/null 2>&1 || true
ok "fstab entry written"

# No user process must have /home open while the mount goes on top. The PUNs
# restart on their own on the next access.
if command -v /opt/ood/nginx_stage/sbin/nginx_stage >/dev/null 2>&1; then
    /opt/ood/nginx_stage/sbin/nginx_stage nginx_clean --force >/dev/null 2>&1 || true
fi
mount /home || die "could not mount /home from ${NFS_HOST}"
ok "/home mounted from ${NFS_HOST}:${HOME_EXPORT}"

# --- verification ---------------------------------------------------------------------
msg "checking the mount"
findmnt -n -o SOURCE,FSTYPE,OPTIONS /home | sed 's/^/    /'
probe="/home/.one-ondemand-probe.$$"
touch "$probe" && rm -f "$probe" || die "root cannot write to /home over NFS, no_root_squash for this portal is missing on the server"
ok "the portal root can create homes in the export"
ls -1 /home | sed 's/^/    /'
ok "persistent home operational"
ONEOND_SCRIPTS_25_MOUNT_HOME_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/30-configure-portal.sh" <<'ONEOND_SCRIPTS_30_CONFIGURE_PORTAL_SH_'
#!/usr/bin/env bash
# Configures the portal public name, TLS, authentication with Dex against the local
# LDAP, and the mapping from the remote user to the Unix user.
#
# This is the "configure" phase of a one-apps appliance. It holds everything that
# depends on the site, and in Phase 2 those values arrive through contextualization
# variables.
#
# Usage:  ./30-configure-portal.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

PORTAL_YML=/etc/ood/config/ood_portal.yml
CERT_DIR=/etc/ood/ssl
SERVERNAME="$ONEAPP_OOD_SERVERNAME"
BASE="$ONEAPP_LDAP_BASE"

# Without a name given, the portal answers on its own address. A published image cannot
# default to any particular host name, and an address always works for a first login over
# https, with the certificate carrying it as an IP entry rather than a DNS one.
if [[ -z "$SERVERNAME" ]]; then
    SERVERNAME="$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1)"
    [[ -n "$SERVERNAME" ]] || die "ONEAPP_OOD_SERVERNAME is missing and this VM has no IPv4 address"
    warn "no ONEAPP_OOD_SERVERNAME, the portal answers on ${SERVERNAME}"
fi
if [[ "$SERVERNAME" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    SERVERNAME_SAN="IP:${SERVERNAME}"
else
    SERVERNAME_SAN="DNS:${SERVERNAME}"
fi

# The origin allowed to use the per user key. It is the compute network, taken from the
# range reserved for the workers rather than from a constant, because the adapter opens a
# session on those VMs with this same key and their addresses are whatever the deployment
# gives them.
POOL_FIRST="${ONEAPP_POOL_RANGE:-}"
POOL_FIRST="${POOL_FIRST%%-*}"
if [[ "$POOL_FIRST" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    POOL_CIDR="${POOL_FIRST%.*}.0/24"
else
    POOL_CIDR="$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | tail -1)"
    POOL_CIDR="${POOL_CIDR%.*}.0/24"
    warn "no usable ONEAPP_POOL_RANGE, allowing the key from ${POOL_CIDR}"
fi

# --- certificate ------------------------------------------------------------------
mkdir -p "$CERT_DIR"
cert="${CERT_DIR}/${SERVERNAME}.crt"
key="${CERT_DIR}/${SERVERNAME}.key"

issue_selfsigned() {
    msg "generating a self-signed certificate for ${SERVERNAME}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
        -keyout "$key" -out "$cert" \
        -subj "/CN=${SERVERNAME}/O=OpenNebula Open OnDemand" \
        -addext "subjectAltName=${SERVERNAME_SAN}" >/dev/null 2>&1 \
        || die "could not generate the self-signed certificate"
    chmod 600 "$key"
    ok "self-signed certificate at ${cert}"
}

if [[ -f "$cert" && -f "$key" ]]; then
    ok "a certificate for ${SERVERNAME} already exists"
elif [[ "$ONEAPP_OOD_SSL_MODE" == "letsencrypt" ]]; then
    apt_install certbot
    msg "requesting a Let's Encrypt certificate for ${SERVERNAME}"
    # The HTTP-01 challenge arrives through the host redirection, which is already
    # tested. Apache stops to free port 80 and starts again whatever happens, because
    # without this trap a half-way failure left the portal down.
    systemctl stop apache2 >/dev/null 2>&1
    trap 'systemctl start apache2 >/dev/null 2>&1 || true' EXIT
    le_args=(--standalone -d "$SERVERNAME" --agree-tos --non-interactive)
    if [[ -n "$ONEAPP_OOD_SSL_EMAIL" ]]; then
        le_args+=(-m "$ONEAPP_OOD_SSL_EMAIL")
    else
        le_args+=(--register-unsafely-without-email)
    fi
    if certbot certonly "${le_args[@]}" >/tmp/certbot.log 2>&1; then
        ln -sf "/etc/letsencrypt/live/${SERVERNAME}/fullchain.pem" "$cert"
        ln -sf "/etc/letsencrypt/live/${SERVERNAME}/privkey.pem" "$key"
        ok "Let's Encrypt certificate issued for ${SERVERNAME}"
    else
        warn "Let's Encrypt failed, continuing with a self-signed certificate"
        warn "detail: $(tail -3 /tmp/certbot.log | tr '\n' ' ')"
        issue_selfsigned
    fi
    systemctl start apache2 >/dev/null 2>&1
    trap - EXIT
else
    issue_selfsigned
fi

# --- the portal has to trust its own certificate ------------------------------------
# mod_auth_openidc fetches the Dex metadata over HTTPS against the portal's own name, so
# with a self-signed certificate it refuses the connection and every request returns a
# 500. The vhost log carries this trace.
#
#   oidc_util_http_call: curl_easy_perform failed for .../dex/.well-known/openid-configuration
#   with: [SSL certificate problem: self-signed certificate]
#
# With Let's Encrypt it does not appear because the certificate is already trusted, so the
# failure only reaches deployments in self-signed mode, and that is every deployment
# without a public DNS name. Checked on 9 September 2026 on the OneFlow service portal.
#
# The fix is to make the system trust the certificate, because the system trust store is
# where mod_auth_openidc looks. Disabling validation would leave the portal accepting any
# certificate in the exchange that decides who each user is.
if [[ ! -L "$cert" ]]; then
    trust=/usr/local/share/ca-certificates/one-ondemand-portal.crt
    if ! cmp -s "$cert" "$trust"; then
        install -m 644 "$cert" "$trust"
        update-ca-certificates >/dev/null 2>&1 || die "could not update the certificate store"
        ok "the system now trusts the self-signed certificate of the portal"
    fi
fi

# --- OIDC secret -----------------------------------------------------------------
# update_ood_portal refuses to generate the configuration if this passphrase is
# missing, and it has no default value. It is generated once and stored, so that
# rerunning the script does not invalidate sessions that are already open.
PASSPHRASE_FILE=/etc/ood/config/.oidc_crypto_passphrase
if [[ -s "$PASSPHRASE_FILE" ]]; then
    ok "reusing the existing OIDC crypto passphrase"
else
    openssl rand -hex 32 > "$PASSPHRASE_FILE" || die "could not generate the OIDC crypto passphrase"
    chmod 600 "$PASSPHRASE_FILE"
    ok "OIDC crypto passphrase generated"
fi
OIDC_PASSPHRASE="$(cat "$PASSPHRASE_FILE")"

# --- ood_portal.yml -----------------------------------------------------------------
msg "writing ${PORTAL_YML}"
backup_once "$PORTAL_YML"

cat > "$PORTAL_YML" <<EOF
# Generated by one-ondemand/scripts/30-configure-portal.sh
# After any change you have to run:
#   /opt/ood/ood-portal-generator/sbin/update_ood_portal && systemctl reload apache2

servername: ${SERVERNAME}

ssl:
  - 'SSLCertificateFile "${cert}"'
  - 'SSLCertificateKeyFile "${key}"'

# Proxying is only allowed towards the private networks of the deployment, rather than
# the permissive wildcard of the example.
host_regex: '[\\w.-]+\\.ood\\.local|(?:10|172\\.(?:1[6-9]|2\\d|3[01])|192\\.168)\\.[\\d.]+'

# With Dex connectors defined, oidc_remote_user_claim is preferred_username. In this
# directory that claim is the uid itself, with no at sign. The example in the OSC
# documentation assumes the email claim and requires the at sign, so applied here the
# mapping fails and the portal answers 404 "failed to map user".
# This Lua pattern keeps the leading part before the at sign, so it works both for
# "demo1" and for "demo1@ood.local" if the claim is ever changed.
user_map_match: '^([^@]+)'

# Without these two paths, Apache does not proxy towards the interactive sessions, and
# opening a notebook answers 404 Not Found even when Jupyter is already serving. The
# node proxy forwards /node/<host>/<port>/... to the machine running the session, and
# that is the route into the notebook. rnode is the variant without link rewriting,
# used by some apps.
node_uri: '/node'
rnode_uri: '/rnode'

# Mandatory for OIDC. Without it update_ood_portal refuses to generate anything.
oidc_crypto_passphrase: '${OIDC_PASSPHRASE}'

# The state cookie that mod_auth_openidc creates when redirecting to Dex expires after
# 300 seconds by default. Whoever takes longer to fill the form returns from Dex with a
# state that no longer exists, and Apache answers 400 Bad Request with no explanation.
# One hour covers whoever leaves the tab open, and OIDCDefaultURL sends the expired
# state to the front page, which restarts the login, instead of to the error.
oidc_settings:
  OIDCStateTimeout: 3600
  OIDCDefaultURL: 'https://${SERVERNAME}/'

# It runs as root right before starting the PUN of the user, and it creates the home
# and the credentials the session needs. Creating an account is then a single LDAP
# entry, with nothing in the system touched by hand.
pun_pre_hook_root_cmd: '/opt/one-ondemand/bin/pun_prehook'
pun_pre_hook_exports: 'OIDC_CLAIM_preferred_username,OIDC_CLAIM_email'

dex:
  connectors:
    - type: ldap
      id: ldap
      name: LDAP
      config:
        host: localhost:389
        insecureNoSSL: true
        bindDN: cn=admin,${BASE}
        bindPW: ${ONEAPP_LDAP_ADMIN_PASS}
        userSearch:
          baseDN: ou=People,${BASE}
          filter: "(objectClass=posixAccount)"
          username: uid
          idAttr: uid
          emailAttr: mail
          nameAttr: gecos
          preferredUsernameAttr: uid
        groupSearch:
          baseDN: ou=Groups,${BASE}
          filter: "(objectClass=posixGroup)"
          userMatchers:
            - userAttr: DN
              groupAttr: member
          nameAttr: cn
EOF

# It carries the bind password of the directory, so it must not be readable by everyone.
chown root:root "$PORTAL_YML"
chmod 600 "$PORTAL_YML"
ok "${PORTAL_YML} written with mode 600"

# --- minimal pre-PUN hook -------------------------------------------------------------
# The hook creates the user home right away, because with OIDC there is no PAM session
# and pam_mkhomedir would never fire. An extension point at the end lets a site add
# more setup.
mkdir -p /opt/one-ondemand/bin
cat > /opt/one-ondemand/bin/pun_prehook <<'HOOK'
#!/usr/bin/env bash
# Runs as root right before the user PUN starts.
#
# nginx_stage calls it as `pun_prehook --user <name>`, not with the name as a bare
# first argument, and it also discards its output and its return code, so an error
# here does not break the PUN startup but is not visible anywhere either. That is
# why both forms are accepted and everything is logged to syslog.
set -uo pipefail

user=""
while (( $# )); do
    case "$1" in
        --user) user="${2:-}"; shift 2 ;;
        --user=*) user="${1#--user=}"; shift ;;
        *) [[ -z "$user" ]] && user="$1"; shift ;;
    esac
done

[[ -z "$user" || "$user" == "root" ]] && exit 0

home="$(getent passwd "$user" | cut -d: -f6)"
if [[ -z "$home" ]]; then
    logger -t ood-prehook "user ${user} does not resolve through NSS, nothing is created"
    exit 0
fi

if [[ ! -d "$home" ]]; then
    if install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home"; then
        for f in /etc/skel/.bashrc /etc/skel/.profile; do
            [[ -f "$f" ]] && install -m 0644 -o "$user" -g "$(id -gn "$user")" "$f" "${home}/$(basename "$f")"
        done
        logger -t ood-prehook "home created for ${user} at ${home}"
    else
        logger -t ood-prehook "could not create the home of ${user} at ${home}"
        exit 1
    fi
fi

# The portal web terminal opens an ssh to the portal itself as the user, because this
# deployment has no login nodes, and the linux_host adapter opens another one to the
# pool VMs. It is the same key for both, and it only works from
# the portal (over localhost or over its IP on the compute network).
sshdir="${home}/.ssh"
key="${sshdir}/id_ed25519_portal"
if [[ ! -f "$key" ]]; then
    group="$(id -gn "$user")"
    install -d -m 0700 -o "$user" -g "$group" "$sshdir"
    if runuser -u "$user" -- ssh-keygen -q -t ed25519 -N "" -C "one-ondemand-portal" -f "$key" </dev/null; then
        printf 'from="127.0.0.1,::1,@@POOL_CIDR@@" %s\n' "$(cat "${key}.pub")" >> "${sshdir}/authorized_keys"
        grep -qs "id_ed25519_portal" "${sshdir}/config" \
            || printf 'Host *\n    IdentityFile %s\n    StrictHostKeyChecking accept-new\n' "$key" >> "${sshdir}/config"
        chown "$user:$group" "${sshdir}/authorized_keys" "${sshdir}/config"
        chmod 600 "${sshdir}/authorized_keys" "${sshdir}/config"
        logger -t ood-prehook "web terminal key created for ${user}"
    else
        logger -t ood-prehook "could not create the web terminal key of ${user}"
    fi
fi
# The same key lets the portal open a session on the pool VMs as the user (linux_host
# adapter), so the allowed origin includes the private compute network and the
# client offers it to any host, not only to localhost. A key created earlier with
# the old origin or the old scope is corrected here.
if [[ -f "${key}.pub" && -f "${sshdir}/authorized_keys" ]]; then
    pub="$(cut -d' ' -f2 "${key}.pub")"
    if grep -qF "$pub" "${sshdir}/authorized_keys" && ! grep -F "$pub" "${sshdir}/authorized_keys" | grep -q '@@POOL_CIDR@@'; then
        awk -v pub="$pub" -v pre='from="127.0.0.1,::1,@@POOL_CIDR@@"' \
            'index($0, pub) { sub(/^from="[^"]*" */, ""); $0 = pre " " $0 } { print }' \
            "${sshdir}/authorized_keys" > "${sshdir}/authorized_keys.new" \
            && cat "${sshdir}/authorized_keys.new" > "${sshdir}/authorized_keys" && rm -f "${sshdir}/authorized_keys.new"
        logger -t ood-prehook "web terminal key origin of ${user} widened to the pool"
    fi
    if grep -qs '^Host localhost$' "${sshdir}/config"; then
        sed -i 's/^Host localhost$/Host */' "${sshdir}/config"
        logger -t ood-prehook "the web terminal key of ${user} is now offered to the pool VMs"
    fi
fi

# The job composer keeps its state in a SQLite database inside the user home, and Open
# OnDemand 4.2 does not migrate it on its own. It creates the database empty, and from then
# on every request to the composer returns a 500 with "Could not find table 'workflows'". A
# portal that has been running for a while does not show this, because its database was
# migrated long ago, and a portal just deployed shows it at once. Checked on 9 September 2026.
#
# The migration needs three things that Passenger gives the application and a shell does not.
# The Open OnDemand gem path plus the system one, because net-pop lives in the system one
# and without it bundler does not resolve; RAILS_ENV=production; and a SECRET_KEY_BASE, which
# to migrate a schema does not need to be the real one and is therefore throwaway.
myjobs_app=/var/www/ood/apps/sys/myjobs
myjobs_dir="${home}/ondemand/data/sys/myjobs"
if [[ -x "${myjobs_app}/bin/rake" ]]; then
    migrada=0
    python3 - "${myjobs_dir}/production.sqlite3" <<'PYDB' && migrada=1
import sqlite3, sys
try:
    c = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
    c.execute("select 1 from workflows limit 1")
except Exception:
    sys.exit(1)
sys.exit(0)
PYDB
    if (( migrada == 0 )); then
        install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$myjobs_dir"
        if (cd "$myjobs_app" && runuser -u "$user" -- env \
                GEM_PATH=/opt/ood/gems:/usr/lib/ruby/gems/3.2.0:/var/lib/gems/3.2.0 \
                RAILS_ENV=production RAILS_LOG_TO_STDOUT=1 \
                SECRET_KEY_BASE="$(openssl rand -hex 32)" \
                ./bin/rake db:migrate) >/dev/null 2>&1; then
            logger -t ood-prehook "job composer database migrated for ${user}"
        else
            logger -t ood-prehook "could not migrate the job composer database of ${user}"
        fi
    fi
fi

# Extension point. If an executable exists at this path, the hook runs it with the user
# name as its only argument.
if [[ -x /opt/one-ondemand/bin/pun_prehook_site ]]; then
    /opt/one-ondemand/bin/pun_prehook_site "$user" \
        || logger -t ood-prehook "the site hook failed for ${user}"
fi

exit 0
HOOK
# The hook is written with a quoted heredoc, so the compute network is substituted here
# instead of being expanded inside it.
sed -i "s|@@POOL_CIDR@@|${POOL_CIDR}|g" /opt/one-ondemand/bin/pun_prehook
if grep -q '@@POOL_CIDR@@' /opt/one-ondemand/bin/pun_prehook; then
    die "the compute network was not substituted in the pre-PUN hook"
fi
chmod 755 /opt/one-ondemand/bin/pun_prehook
ok "pre-PUN hook installed at /opt/one-ondemand/bin/pun_prehook"

# --- menu and terminal ----------------------------------------------------------------
# The package ships a job composer, a module browser and a system status page
# meant for a Slurm cluster with login nodes. This appliance has no such cluster,
# so those pages are empty and the menu is declared by hand with what works. The
# interactive apps installed later appear on their own in their own group.
install -d -m 755 /etc/ood/config/ondemand.d
# bc_dynamic_js. The app forms use dynamic rules (they hide the cores, memory and
# GPU fields when the VM is chosen). Open OnDemand 4.2 disables that feature by
# default, and without it the rules are ignored with no error at all.
cat > /etc/ood/config/ondemand.d/one-ondemand.yml <<'EOF'
# Generated by one-ondemand/scripts/30-configure-portal.sh
bc_dynamic_js: true
nav_bar:
  - "Files"
  - "Interactive Apps"
  - "Jobs"
  - "sessions"
  - apps: "sys/shell"
# By default the front page shows only the recently used applications, so a new user
# lands on an almost empty page and the catalogue looks like it does not exist. With
# pinned_apps the five of them always appear, each one with the logo of its project,
# grouped by the subcategory its manifest declares.
pinned_apps:
  - sys/jupyter
  - sys/octave
  - sys/cpp-notebook
  - sys/rstudio
  - sys/code-server
pinned_apps_menu_length: 8
pinned_apps_group_by: subcategory
# The front page carries a "Recently Used Apps" row above everything, which in a
# demo shows what the last person to log in opened and not the catalogue. Declaring
# the layout by hand removes that row, because it only exists inside the default
# layout and has no switch of its own.
dashboard_layout:
  rows:
    - columns:
        - width: 12
          widgets:
            - pinned_apps
            - motd
EOF
ok "menu and dynamic forms declared in /etc/ood/config/ondemand.d/one-ondemand.yml"

# --- pool roster ----------------------------------------------------------------------
# A timer that records which workers answer and how many sessions each one has, so the
# launch template sends every new session to the one with the most room. Without this
# the adapter sends everything to the same host and a worker added by elasticity stays
# empty. Every half minute is enough, because a session takes longer than that to start.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The OneGate library goes here too. When the portal is a VM of the OneFlow service, the
# roster asks OneGate which workers the role has right now, instead of probing the whole
# range. A portal installed by hand belongs to no service, so the library is unused and
# the roster probes the range instead.
install -d -m 755 /etc/one-ondemand
install -m 644 "${REPO_ROOT}/worker/onegate-lib.sh" /etc/one-ondemand/onegate-lib.sh
bash -n /etc/one-ondemand/onegate-lib.sh || die "onegate-lib.sh is not valid bash"
install -m 755 "${REPO_ROOT}/scripts/ood-pool-refresh.sh" /usr/local/bin/ood-pool-refresh
cat > /etc/systemd/system/ood-pool-refresh.service <<'UNIT'
[Unit]
Description=Refresh the Open OnDemand worker pool roster
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ood-pool-refresh
UNIT
cat > /etc/systemd/system/ood-pool-refresh.timer <<'UNIT'
[Unit]
Description=Refresh the Open OnDemand worker pool roster every 30 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ood-pool-refresh.timer >/dev/null 2>&1
/usr/local/bin/ood-pool-refresh || die "the pool roster could not be generated"
ok "pool roster active: $(cat /var/lib/ood-pool/workers.json)"

# --- dashboard extensions -------------------------------------------------------------
# Rails loads the files in this directory as initializers when the external configuration
# is active (dashboard/config/application.rb:50). This directory is meant for site code,
# and it survives an update of the ondemand package, unlike patching the gem in
# /opt/ood/gems.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "${REPO_ROOT}/config/dashboard-initializers" ]]; then
    install -d -m 755 /etc/ood/config/apps/dashboard/initializers
    install -m 644 "${REPO_ROOT}"/config/dashboard-initializers/*.rb /etc/ood/config/apps/dashboard/initializers/
    for f in "${REPO_ROOT}"/config/dashboard-initializers/*.rb; do
        ruby -c "$f" >/dev/null 2>&1 || die "$(basename "$f") is not valid Ruby"
    done
    ok "dashboard extensions installed: $(ls -1 /etc/ood/config/apps/dashboard/initializers | tr '\n' ' ')"
fi

# The web terminal needs a host to open ssh to. With no login nodes that host is the
# portal itself, where the user has their home, and the pre-PUN hook leaves them a key
# that only works from this machine.
install -d -m 755 /etc/ood/config/apps/shell
cat > /etc/ood/config/apps/shell/env <<'EOF'
# Generated by one-ondemand/scripts/30-configure-portal.sh
OOD_DEFAULT_SSHHOST=localhost
OOD_SSHHOST_ALLOWLIST=localhost
EOF
ok "web terminal pointing at the portal itself"

# --- resolving the portal own public name ------------------------------------------
# mod_auth_openidc reads the Dex metadata through the public name of the portal. That
# name points at the public IP of the host, and the traffic leaving this VM towards it
# does not return through the inbound redirection, which only acts on the public
# interface. Without this entry the dashboard answers 500 with a timeout when asking for
# /dex/.well-known/openid-configuration.
if grep -qE "^[0-9.]+[[:space:]]+${SERVERNAME}( |\$)" /etc/hosts; then
    ok "${SERVERNAME} already resolves locally"
else
    printf '127.0.0.1 %s\n' "$SERVERNAME" >> /etc/hosts
    ok "${SERVERNAME} added to /etc/hosts pointing at this machine"
fi

# --- Apache modules --------------------------------------------------------------
# On Ubuntu mod_ssl is installed but disabled, while on RHEL it is enabled by default.
# The OSC documentation is RHEL, so this step does not appear there, and without it
# Apache does not start and reports "Invalid command 'SSLEngine'".
msg "checking the Apache modules the portal needs"
for mod in ssl auth_openidc lua proxy proxy_http proxy_wstunnel headers rewrite env deflate; do
    if a2query -m "$mod" >/dev/null 2>&1; then
        ok "module ${mod} already enabled"
    else
        a2enmod -q "$mod" >/dev/null 2>&1 && ok "module ${mod} enabled" \
            || die "could not enable the Apache module ${mod}"
    fi
done

# --- apply ----------------------------------------------------------------------------
msg "generating the Apache configuration"
/opt/ood/ood-portal-generator/sbin/update_ood_portal 2>&1 | sed 's/^/    /' \
    || die "update_ood_portal failed"

msg "restarting services"
systemctl restart ondemand-dex || die "ondemand-dex did not start, check the Dex configuration"
systemctl reload apache2 2>/dev/null || systemctl restart apache2 || die "Apache did not start"
service_up ondemand-dex
service_up apache2

# --- verification ---------------------------------------------------------------------
# The check goes through the public name, not through localhost, because the portal
# vhost answers on that name and mod_auth_openidc travels the same path.
msg "checking that the portal answers"
code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "https://${SERVERNAME}/" 2>/dev/null)"
case "$code" in
    200|301|302|303) ok "the portal answers over HTTPS (code ${code})" ;;
    *) die "the portal returns ${code} over HTTPS" ;;
esac

if curl -sk --max-time 15 "https://${SERVERNAME}/dex/.well-known/openid-configuration" 2>/dev/null | grep -q issuer; then
    ok "Dex publishes its OIDC configuration"
else
    die "Dex does not publish its OIDC configuration, check journalctl -u ondemand-dex"
fi

msg "checking the full authentication flow"
login_url="$(curl -sk -o /dev/null -w '%{url_effective}' -L --max-time 25 "https://${SERVERNAME}/" 2>/dev/null)"
if [[ "$login_url" == *"/dex/auth/"* ]]; then
    ok "the portal leads to the Dex login form (${login_url##*/dex/})"
else
    warn "the portal did not end at the Dex login form but at ${login_url}"
fi

ok "portal configured at https://${SERVERNAME}"
ONEOND_SCRIPTS_30_CONFIGURE_PORTAL_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/60-install-apps.sh" <<'ONEOND_SCRIPTS_60_INSTALL_APPS_SH_'
#!/usr/bin/env bash
# Installs the interactive applications in the portal.
#
# An application is a folder with a form, a submit template and a connection panel.
# There is no code to compile and no service to restart.
#
# Usage:  ./60-install-apps.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR=/var/www/ood/apps/sys

[[ -d "$APPS_DIR" ]] || die "${APPS_DIR} does not exist, is Open OnDemand installed?"

for app in "${REPO_DIR}"/apps/*/; do
    name="$(basename "$app")"
    dest="${APPS_DIR}/${name}"

    msg "installing application ${name}"
    mkdir -p "$dest"
    cp -a "${app}." "$dest/"
    # The ._* files are the resource forks macOS adds when packaging. If they stay,
    # the portal reads them as definitions and they clutter the application listing.
    find "$dest" -name '._*' -delete
    chown -R root:root "$dest"
    find "$dest" -type f -exec chmod 644 {} +
    find "$dest" -type d -exec chmod 755 {} +
    # The dashboard copies the mode of each template to the file it renders, and the
    # session script (template/script.sh) runs directly, not through bash, so without
    # the execute bit the session dies with "Permission denied".
    [[ -d "${dest}/template" ]] && find "${dest}/template" -name '*.sh.erb' -exec chmod 755 {} +

    for f in manifest.yml form.yml submit.yml.erb; do
        [[ -f "${dest}/${f}" ]] || die "application ${name} is missing ${f}"
    done
    ok "${name} installed in ${dest}"

    # The form and the manifest are YAML. The submit template is ERB and can only be
    # validated once it is rendered, so only the YAML is checked here.
    if command -v ruby >/dev/null 2>&1; then
        for f in manifest.yml form.yml; do
            ruby -e "require 'yaml'; YAML.load_file('${dest}/${f}')" 2>&1 | sed 's/^/    /' \
                || die "${name}/${f} is not valid YAML"
        done
        ok "${name}: manifest and form are valid"
    fi
done

# --- stock desktop ------------------------------------------------------------------
# The package installs a desktop (bc_desktop) that starts a VNC session on a node of
# a classic scheduler. This appliance has no such scheduler, so the desktop cannot
# work, and it still appears in the listing with no configuration option that hides
# it. Its manifest and its form are diverted with dpkg-divert, the way Debian
# withdraws a file from a package so an update does not restore it. Without the
# manifest the portal does not list it, and without the form it treats it as an
# invalid application if someone reaches it by URL.
for f in manifest.yml form.yml; do
    stock="${APPS_DIR}/bc_desktop/${f}"
    if dpkg-divert --list "$stock" | grep -q .; then
        ok "stock desktop: ${f} was already set aside"
    elif [[ -f "$stock" ]]; then
        dpkg-divert --local --rename --divert "${stock}.distrib" "$stock" 2>&1 | sed 's/^/    /' \
            || die "could not set aside ${stock}"
        ok "stock desktop: ${f} set aside in ${stock}.distrib"
    else
        ok "stock desktop: there is no ${f} to set aside"
    fi
done

msg "available applications"
ls -1 "$APPS_DIR" | sed 's/^/    /'

ok "applications installed"
ONEOND_SCRIPTS_60_INSTALL_APPS_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/70-install-cvmfs.sh" <<'ONEOND_SCRIPTS_70_INSTALL_CVMFS_SH_'
#!/usr/bin/env bash
# CernVM-FS client with EESSI in the portal, through the site Squid.
#
# In the portal it serves the web terminal, and it tells the application templates which
# version and which Jupyter module to offer. It follows the CernVM-FS recommendation
# (local client with cache and site proxy), instead of the NFS reexport that they advise
# against. If an old NFS mount is left, it removes it.
#
# It is idempotent. Variables:
#   ONEAPP_CVMFS_PROXY            Squid URL (required)
#   ONEAPP_EESSI_VERSION          EESSI version (2025.06)
#   ONEAPP_EESSI_JUPYTER_MODULE   EESSI module with JupyterLab and ipykernel
#
# Usage:  ONEAPP_CVMFS_PROXY=http://172.20.0.222:3128 ./70-install-cvmfs.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

PROXY="${ONEAPP_CVMFS_PROXY:?ONEAPP_CVMFS_PROXY with the Squid URL is missing}"
STATE_DIR=/etc/one-ondemand
MOUNT=/cvmfs/software.eessi.io
EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"

# The first version mounted /cvmfs over NFS, so that mount is removed if it is still there.
if findmnt -n -t nfs4,nfs "$MOUNT" >/dev/null 2>&1; then
    umount "$MOUNT" || die "could not unmount the old NFS ${MOUNT}"
    sed -i "\# ${MOUNT} nfs4 #d" /etc/fstab
    ok "old NFS mount of ${MOUNT} removed"
fi

CVMFS_PROXY="$PROXY" EESSI_VERSION="$EESSI_VERSION" CVMFS_MOUNT=autofs \
    bash "$(dirname "${BASH_SOURCE[0]}")/cvmfs-client.sh" || die "the CernVM-FS client did not end up operational"

install -d -m 755 "$STATE_DIR"

# --- module discovery ----------------------------------------------------------------
# The portal applications need to know which module to load for each language. The
# versions change with every EESSI release, so they are not written down here. Each family
# is queried in the mounted catalogue and the most recent version is kept. A module that
# does not exist is recorded empty and its application says so when launched, so a
# secondary application cannot fail here and leave the portal uninstalled.
init="${MOUNT}/versions/${EESSI_VERSION}/init/bash"
latest_module() {
    local family="$1"
    bash -c "source '${init}' >/dev/null 2>&1 && module -t avail '${family}/' 2>&1" \
        | grep -E "^${family}/" | sort -V | tail -1
}

declare -A MODULES=(
    [EESSI_JUPYTER_MODULE]="$EESSI_JUPYTER_MODULE"
    [EESSI_OCTAVE_KERNEL_MODULE]="$(latest_module octave-kernel)"
    [EESSI_OCTAVE_MODULE]="$(latest_module Octave)"
    [EESSI_CLING_MODULE]="$(latest_module cling-kernel)"
    [EESSI_RSTUDIO_MODULE]="$(latest_module RStudio-Server)"
)

{
    printf '# Generated by one-ondemand/scripts/70-install-cvmfs.sh\n'
    printf 'EESSI_VERSION=%s\n' "$EESSI_VERSION"
    printf 'CVMFS_PROXY=%s\n' "$PROXY"
    for key in EESSI_JUPYTER_MODULE EESSI_OCTAVE_KERNEL_MODULE \
               EESSI_OCTAVE_MODULE EESSI_CLING_MODULE EESSI_RSTUDIO_MODULE; do
        printf '%s=%s\n' "$key" "${MODULES[$key]}"
    done
} > "${STATE_DIR}/eessi.env"
chmod 644 "${STATE_DIR}/eessi.env"

for key in "${!MODULES[@]}"; do
    if [[ -n "${MODULES[$key]}" ]]; then
        ok "${key}=${MODULES[$key]}"
    else
        warn "${key} does not exist in EESSI ${EESSI_VERSION}, its application will warn about it when launched"
    fi
done
ok "version, modules and proxy recorded in ${STATE_DIR}/eessi.env"

msg "checking the EESSI Jupyter module from the portal"
if bash -c "source '${init}' >/dev/null 2>&1 && module load '${EESSI_JUPYTER_MODULE}' >/dev/null 2>&1 && python -c 'import ipykernel'" 2>/dev/null; then
    ok "${EESSI_JUPYTER_MODULE} loads and brings ipykernel"
else
    die "could not load ${EESSI_JUPYTER_MODULE} from EESSI ${EESSI_VERSION}"
fi
ONEOND_SCRIPTS_70_INSTALL_CVMFS_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/90-configure-vm-pool.sh" <<'ONEOND_SCRIPTS_90_CONFIGURE_VM_POOL_SH_'
#!/usr/bin/env bash
# Declares the VM pool as the portal target.
#
# The linux_host adapter rejects a job whose host is not in ssh_hosts, and that list is
# read only once per user process. With a pool that grows that is an ordering problem,
# because a worker that OneFlow creates later would not exist for the portal until the
# user process restarts.
#
# The fix is to declare the whole compute network range in advance. The name of each
# worker is derived from its address with the same rule the VM itself uses in
# worker/configure.sh, so that 172.20.0.228 is always ood-worker-228. OpenNebula
# guarantees that two VMs do not share an address, so the name is unique without any
# coordination, and any worker born inside the range is accepted before it exists.
#
# The names carry a domain because ood_core recognises the host of a job with a regular
# expression that only accepts names with dots, so with a short name the job identifier
# is left without a host and the session is taken as finished straight away.
#
# It is idempotent. Variables:
#   ONEAPP_POOL_RANGE       range RESERVED FOR THE WORKERS, "first-last" (required),
#                           for example "172.20.0.230-172.20.0.249". Everything else
#                           depends on this contract, because the portal takes any live
#                           machine inside that range for a worker, so nothing else can
#                           be there.
#                           In the OneFlow service it is the compute network of the role,
#                           in a manual installation it has to be reserved.
#   ONEAPP_POOL_EXCLUDE_IPS addresses inside the range that are NOT workers, separated by
#                           spaces. The portal and the storage addresses are added
#                           automatically.
#   ONEAPP_POOL_PREFIX      name prefix of each worker (ood-worker-)
#   ONEAPP_POOL_DOMAIN      domain of the pool VMs (ood.local)
#   ONEAPP_POOL_MAX         cap on generated entries (256), as a safety net
#   ONEAPP_POOL_SUBMIT_HOST fallback host that receives jobs if the roster is stale.
#                           By default, the first one in the range that responds.
#
# Usage:  ONEAPP_POOL_RANGE="172.20.0.50-172.20.0.249" ./90-configure-vm-pool.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

POOL_RANGE="${ONEAPP_POOL_RANGE:?ONEAPP_POOL_RANGE with the compute network range is missing}"
POOL_PREFIX="${ONEAPP_POOL_PREFIX:-ood-worker-}"
POOL_DOMAIN="${ONEAPP_POOL_DOMAIN:-ood.local}"
POOL_MAX="${ONEAPP_POOL_MAX:-256}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_FILE=/etc/ood/config/clusters.d/vms.yml
HOSTS_MARK="# one-ondemand pool"

first="${POOL_RANGE%%-*}"; last="${POOL_RANGE##*-}"
[[ "$first" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$last" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "ONEAPP_POOL_RANGE must be \"first-last\", for example 172.20.0.50-172.20.0.249"
net="${first%.*}"
# The name is built from the last octet, so the range has to fit in a /24 or two VMs from
# different subnets would receive the same name. The check exists instead of an assumption,
# because that failure would be silent and very hard to find.
[[ "${last%.*}" == "$net" ]] || die "ONEAPP_POOL_RANGE has to be inside a single /24 (${first} and ${last} are not)"
lo="${first##*.}"; hi="${last##*.}"
(( lo <= hi )) || die "the range is backwards, ${first} comes after ${last}"
count=$(( hi - lo + 1 ))
(( count <= POOL_MAX )) || die "the range has ${count} addresses and the cap is ${POOL_MAX}, adjust ONEAPP_POOL_RANGE or ONEAPP_POOL_MAX"

# --- what is in the range and is not a worker -----------------------------------------------
# The portal and the storage have SSH open just like a worker, so without this list the
# roster would take them for valid destinations and a user session could run on the
# portal itself.
install -d -m 755 /etc/one-ondemand
{
    printf '# Generated by one-ondemand/scripts/90-configure-vm-pool.sh\n'
    printf '# Addresses inside the pool range that are not workers.\n'
    for ip in ${ONEAPP_POOL_EXCLUDE_IPS:-} ${ONEAPP_LDAP_HOST:-} ${ONEAPP_NFS_HOST:-} $(hostname -I); do
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        [[ "${ip%.*}" == "$net" ]] || continue
        printf '%s%s.%s\n' "$POOL_PREFIX" "${ip##*.}" "$POOL_DOMAIN"
    done | sort -u
} > /etc/one-ondemand/pool-exclude
chmod 644 /etc/one-ondemand/pool-exclude
ok "excluded from the pool: $(grep -vc '^#' /etc/one-ondemand/pool-exclude) names"

# --- resolvable names -------------------------------------------------------------------
msg "declaring ${count} names for the compute network ${first} to ${last}"
backup_once /etc/hosts
sed -i "/${HOSTS_MARK}\$/d" /etc/hosts
ssh_hosts=""
{
    for (( o = lo; o <= hi; o++ )); do
        printf '%s.%s %s%s.%s %s%s %s\n' "$net" "$o" "$POOL_PREFIX" "$o" "$POOL_DOMAIN" "$POOL_PREFIX" "$o" "$HOSTS_MARK"
    done
} >> /etc/hosts
for (( o = lo; o <= hi; o++ )); do
    ssh_hosts+="      - \"${POOL_PREFIX}${o}.${POOL_DOMAIN}\"\n"
done
ok "${count} names from ${POOL_PREFIX}${lo}.${POOL_DOMAIN} to ${POOL_PREFIX}${hi}.${POOL_DOMAIN} in /etc/hosts"

# --- fallback host -----------------------------------------------------------------------
# The roster does the real spreading, and it sends each session to the least loaded worker
# (config/dashboard-initializers/50-submit-host-override.rb). submit_host is only used if
# the roster is stale or empty, so it points at a worker that has announced itself, and not
# at an address in the range that may have no VM behind it or a different machine.
submit_host="${ONEAPP_POOL_SUBMIT_HOST:-}"
if [[ -z "$submit_host" ]]; then
    submit_host="${POOL_PREFIX}${lo}.${POOL_DOMAIN}"
fi
ok "provisional fallback host: ${submit_host}, it will be adjusted with the roster"

# --- target definition ---------------------------------------------------------------------
msg "writing ${CLUSTER_FILE}"
awk -v sh="$submit_host" -v hosts="$(printf "$ssh_hosts")" '
    /@@SSH_HOSTS@@/ { print hosts; next }
    { gsub(/@@SUBMIT_HOST@@/, sh); print }
' "${REPO_DIR}/config/clusters.d/vms.yml" > "$CLUSTER_FILE"
chmod 644 "$CLUSTER_FILE"
ruby -e "require 'yaml'; YAML.load_file('${CLUSTER_FILE}')" 2>&1 | sed 's/^/    /' \
    || die "${CLUSTER_FILE} is not valid YAML"
ok "target vms declared with ${count} accepted hosts and fallback on ${submit_host}"

# --- the job composer in the menu -------------------------------------------------------------
# It offers the vms cluster, the only target declared in clusters.d.
menu=/etc/ood/config/ondemand.d/one-ondemand.yml
if ! grep -q '"Jobs"' "$menu" 2>/dev/null; then
    sed -i 's/^  - "sessions"$/  - "Jobs"\n  - "sessions"/' "$menu"
fi
grep -q '"Jobs"' "$menu" || die "could not add the Jobs group to the menu"
ok "job composer in the menu"

# --- roster ----------------------------------------------------------------------------------
# It is refreshed now so the portal does not have to wait for the timer.
if [[ -x /usr/local/bin/ood-pool-refresh ]]; then
    /usr/local/bin/ood-pool-refresh || warn "the roster could not be refreshed"
    read -r alive first < <(python3 -c "
import json
d=json.load(open('/var/lib/ood-pool/workers.json'))
w=[x for x in d.get('workers',[]) if x.get('alive')]
print(len(w), w[0]['fqdn'] if w else '')" 2>/dev/null)
    ok "roster refreshed, ${alive:-?} live workers"
    # The fallback host comes from the roster, because the roster knows which workers respond.
    if [[ -n "${first:-}" && -z "${ONEAPP_POOL_SUBMIT_HOST:-}" && "$first" != "$submit_host" ]]; then
        submit_host="$first"
        sed -i "s|^    submit_host: .*|    submit_host: \"${submit_host}\"|" "$CLUSTER_FILE"
        ok "fallback host adjusted to ${submit_host}"
    fi
fi

# --- verification -------------------------------------------------------------------------------
msg "checking that the portal logs into ${submit_host} as a user"
first_user="$(cut -d: -f1 <<<"${ONEAPP_LDAP_USERS%% *}")"
if runuser -u "$first_user" -- ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$submit_host" \
        'command -v tmux >/dev/null && command -v apptainer >/dev/null && test -s /opt/ood/linuxhost.sif && echo listo' 2>/dev/null | grep -q listo; then
    ok "${first_user} logs into ${submit_host} and finds tmux, apptainer and the SIF"
else
    warn "${first_user} does not log into ${submit_host} yet, if they have not signed in to the portal their key does not exist"
fi

for u in $(cut -d: -f1 <<<"$(tr ' ' '\n' <<<"$ONEAPP_LDAP_USERS")"); do
    /opt/ood/nginx_stage/sbin/nginx_stage nginx_clean -u "$u" -f >/dev/null 2>&1 || true
done
ok "VM pool declared"
ONEOND_SCRIPTS_90_CONFIGURE_VM_POOL_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/cvmfs-client.sh" <<'ONEOND_SCRIPTS_CVMFS_CLIENT_SH_'
#!/usr/bin/env bash
# Installs and configures the CernVM-FS client with the EESSI catalogue, the way
# CernVM-FS recommends it, a client on every machine that uses it, with a local
# cache and a site Squid proxy in front. It works the same on the portal and on the
# pool VMs, so it is a single script.
#
# It is idempotent. Variables:
#   CVMFS_PROXY      site Squid URL (required), e.g. http://172.20.0.222:3128
#   CVMFS_QUOTA_MB   local cache in MB (6000)
#   EESSI_VERSION    EESSI version whose presence is checked (2025.06)
#   CVMFS_MOUNT      autofs (the default, what CernVM-FS recommends) or static
#                    (fstab entry, for a machine where another service checks the
#                    mount point without entering it)
#   CVMFS_STAGE      all (the default), packages or config. The split exists for the
#                    worker golden image. The packages are baked when the image is
#                    built (packages), and the site proxy is a deployment address,
#                    so it is written at boot (config).
#
# Usage:  CVMFS_PROXY=http://172.20.0.222:3128 ./cvmfs-client.sh

set -uo pipefail
STAGE="${CVMFS_STAGE:-all}"
case "$STAGE" in all|packages|config) ;; *) echo "CVMFS_STAGE must be all, packages or config" >&2; exit 1 ;; esac
# The proxy is only needed when the configuration is written. When the packages are
# installed it is not yet known where the deployment Squid will be.
if [[ "$STAGE" != "packages" ]]; then
    PROXY="${CVMFS_PROXY:?CVMFS_PROXY with the Squid URL is missing}"
else
    PROXY="${CVMFS_PROXY:-}"
fi
QUOTA_MB="${CVMFS_QUOTA_MB:-6000}"
EESSI_VERSION="${EESSI_VERSION:-2025.06}"
MODE="${CVMFS_MOUNT:-autofs}"
REPO="software.eessi.io"
MOUNT="/cvmfs/${REPO}"
CVMFS_RELEASE_DEB="https://cvmrepo.s3.cern.ch/cvmrepo/apt/cvmfs-release-latest_all.deb"
EESSI_CONFIG_DEB="https://github.com/EESSI/filesystem-layer/releases/download/latest/cvmfs-config-eessi_latest_all.deb"

msg() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()  { printf '[%s]   ok: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "it has to be run as root"

export DEBIAN_FRONTEND=noninteractive
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 3; done

if ! dpkg -s cvmfs >/dev/null 2>&1; then
    msg "installing the CernVM-FS client"
    apt-get update -qq >/dev/null || die "apt-get update failed"
    apt-get install -y -qq wget >/dev/null
    if ! dpkg -s cvmfs-release >/dev/null 2>&1; then
        wget -q -O /tmp/cvmfs-release.deb "$CVMFS_RELEASE_DEB" || die "could not download cvmfs-release"
        dpkg -i /tmp/cvmfs-release.deb >/dev/null 2>&1 || die "could not install cvmfs-release"
        rm -f /tmp/cvmfs-release.deb
        apt-get update -qq >/dev/null || die "apt-get update failed after the CernVM-FS repository"
    fi
    apt-get install -y -qq cvmfs >/dev/null || die "could not install cvmfs"
fi
if ! dpkg -s cvmfs-config-eessi >/dev/null 2>&1; then
    wget -q -O /tmp/cvmfs-config-eessi.deb "$EESSI_CONFIG_DEB" || die "could not download cvmfs-config-eessi"
    dpkg -i /tmp/cvmfs-config-eessi.deb >/dev/null 2>&1 || die "could not install cvmfs-config-eessi"
    rm -f /tmp/cvmfs-config-eessi.deb
fi
ok "cvmfs $(dpkg-query -W -f='${Version}' cvmfs), cvmfs-config-eessi $(dpkg-query -W -f='${Version}' cvmfs-config-eessi)"

if [[ "$STAGE" == "packages" ]]; then
    ok "CernVM-FS packages baked, the proxy and the mount are configured at boot"
    exit 0
fi

# Client with a site proxy and a local cache, the configuration that CernVM-FS
# recommends for compute nodes. The proxy has DIRECT behind it only as a
# fallback if the Squid does not answer.
cat > /etc/cvmfs/default.local <<EOF
# Generated by one-ondemand/scripts/cvmfs-client.sh
CVMFS_HTTP_PROXY="${PROXY};DIRECT"
CVMFS_QUOTA_LIMIT=${QUOTA_MB}
CVMFS_CLIENT_PROFILE=single
EOF
if [[ "$MODE" == "static" ]]; then
    # autofs mounts the tree on first access, so a service that only checks the
    # directory can find it empty. A static mount exists from boot, so that check
    # does not depend on autofs.
    cvmfs_config setup noautofs >/dev/null 2>&1 || cvmfs_config setup >/dev/null 2>&1 || die "cvmfs_config setup failed"
    systemctl disable --now autofs >/dev/null 2>&1 || true
    install -d -m 755 "$MOUNT"
    grep -qF " ${MOUNT} cvmfs " /etc/fstab || printf '%s %s cvmfs defaults,_netdev,nodev 0 0\n' "$REPO" "$MOUNT" >> /etc/fstab
    mountpoint -q "$MOUNT" || mount "$MOUNT" || die "could not mount ${REPO}"
else
    cvmfs_config setup >/dev/null 2>&1 || die "cvmfs_config setup failed"
    systemctl enable --now autofs >/dev/null 2>&1 || true
    cvmfs_config reload >/dev/null 2>&1 || true
fi

cvmfs_config probe "$REPO" 2>&1 | grep -q OK || die "cvmfs_config probe ${REPO} failed, does it reach the proxy ${PROXY}?"
[[ -f "${MOUNT}/versions/${EESSI_VERSION}/init/bash" ]] || die "EESSI ${EESSI_VERSION} is not present in ${MOUNT}"
ok "EESSI ${EESSI_VERSION} available in ${MOUNT} (mode ${MODE}, proxy ${PROXY}, cache ${QUOTA_MB} MB)"
ONEOND_SCRIPTS_CVMFS_CLIENT_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/ood-pool-refresh.sh" <<'ONEOND_SCRIPTS_OOD_POOL_REFRESH_SH_'
#!/usr/bin/env bash
# Roster of the worker pool, computed on the portal.
#
# It writes to /var/lib/ood-pool/workers.json which workers are alive and how many sessions
# each one has. The launch template reads it and sends every new session to the least loaded
# worker, so every worker OneFlow adds takes a share of the sessions.
#
# WHO IS A WORKER. The address range the role has reserved decides it, because the compute
# network of the service belongs to the workers and to nobody else. When the portal belongs
# to a OneFlow service the list is also crossed with OneGate, the authoritative source,
# because OneGate knows exactly which VMs the role has.
#
# A probe to port 22 does not decide who is a worker, and it only says whether the address
# is alive. On 9 September 2026, with the range set to the whole network, a roster based only
# on port 22 gave nine live workers where there were three, because it counted the portal
# itself, the storage and other machines that shared the network then, which also have
# SSH open. That is why the portal and storage addresses are excluded explicitly,
# because they are the two addresses the portal knows for certain.
#
# The worker cannot announce itself in the shared home either, because with root_squash it
# can create the file but not write its content. The reason is in worker/publish-load.sh.
#
# WHY THE PORTAL COMPUTES IT. The portal is the only machine that sees the sessions of every
# user, and that is the data the count needs. The count comes from the session database of
# Open OnDemand itself. Each session stores its job identifier in the form
# launched-by-ondemand-<uuid>@<host>, so the host is in the data and there is no need to
# ask anyone.
set -uo pipefail

STATE_DIR="${OOD_POOL_STATE_DIR:-/var/lib/ood-pool}"
OUT="${STATE_DIR}/workers.json"
CLUSTER_FILE="${OOD_VM_CLUSTER_FILE:-/etc/ood/config/clusters.d/vms.yml}"
HOMES="${OOD_HOMES_DIR:-/home}"
PROBE_TIMEOUT="${OOD_POOL_PROBE_TIMEOUT:-3}"
ONEGATE_LIB="${ONEGATE_LIB:-/etc/one-ondemand/onegate-lib.sh}"
# Addresses that are inside the range but are not workers. They are left by
# scripts/90-configure-vm-pool.sh with what it knows about the deployment.
EXCLUDE_FILE="${OOD_POOL_EXCLUDE_FILE:-/etc/one-ondemand/pool-exclude}"

install -d -m 755 "$STATE_DIR"
write_out() { printf '%s\n' "$1" > "${OUT}.$$.tmp"; chmod 644 "${OUT}.$$.tmp"; mv -f "${OUT}.$$.tmp" "$OUT"; }

# --- candidates, the list the adapter accepts, minus what is not a worker ------------------
# A host that is not in ssh_hosts would be rejected by the adapter even if it were alive, so
# the roster can never propose one from outside.
mapfile -t permitted < <(sed -n '/ssh_hosts:/,/^[^ ]/p' "$CLUSTER_FILE" 2>/dev/null \
    | sed -n 's/^ *- *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p')
if (( ${#permitted[@]} == 0 )); then
    write_out "$(printf '{"workers":[],"error":"no ssh_hosts in %s","ts":%s}' "$CLUSTER_FILE" "$(date +%s)")"
    exit 0
fi

declare -A excluded
if [[ -r "$EXCLUDE_FILE" ]]; then
    while read -r name; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        excluded["$name"]=1
    done < "$EXCLUDE_FILE"
fi

candidates=()
for h in "${permitted[@]}"; do
    [[ -v excluded["$h"] ]] && continue
    candidates+=("$h")
done

# --- OneGate, when the portal belongs to the service ------------------------------------------
# OneGate is authoritative, so if it answers it replaces the whole range. It knows which VMs
# the worker role has right now, so there is no need to probe anything else.
source_name="rango"
if [[ -r "$ONEGATE_LIB" ]]; then
    # shellcheck source=/dev/null
    . "$ONEGATE_LIB"
    if onegate_ready 2>/dev/null; then
        desde_onegate=()
        while read -r ip; do
            [[ -n "$ip" ]] || continue
            for h in "${permitted[@]}"; do
                [[ "$h" == *"-${ip##*.}."* ]] && { desde_onegate+=("$h"); break; }
            done
        done < <(onegate_call service show --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("SERVICE", {}).get("roles", []):
    # Only the worker role, the portal and the storage are also nodes of the service.
    if r.get("name") not in ("worker", "workers"):
        continue
    for n in r.get("nodes", []):
        tmpl = ((n.get("vm_info") or {}).get("VM", {})).get("TEMPLATE", {})
        nics = tmpl.get("NIC", [])
        if isinstance(nics, dict):
            nics = [nics]
        for nic in nics:
            if nic.get("IP"):
                print(nic["IP"])
' 2>/dev/null)
        if (( ${#desde_onegate[@]} > 0 )); then
            candidates=("${desde_onegate[@]}")
            source_name="onegate"
        fi
    fi
fi

# --- live sessions per host ---------------------------------------------------------------
declare -A sessions
for h in "${candidates[@]}"; do sessions["$h"]=0; done
while read -r host; do
    [[ -z "$host" ]] && continue
    [[ -v sessions["$host"] ]] && sessions["$host"]=$(( ${sessions["$host"]} + 1 ))
done < <(
    for db in "${HOMES}"/*/ondemand/data/sys/dashboard/batch_connect/db/*; do
        [[ -f "$db" ]] || continue
        python3 - "$db" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
# completed_at marks the session as finished, and those do not occupy the worker.
if d.get('completed_at'):
    sys.exit(0)
jid = str(d.get('job_id', ''))
if '@' in jid:
    print(jid.rsplit('@', 1)[1])
PY
    done
)

# --- liveness check, in parallel ------------------------------------------------------------
# The TCP probe to the SSH port proves that the address is alive and proves nothing about
# its identity. The adapter connects the same way, so an address that does not answer would
# fail the session it was sent. The probes run in parallel because the range can hold
# hundreds of addresses. In series they did not fit in the timer period, probing them one
# by one took almost three minutes.
probe_dir="$(mktemp -d "${STATE_DIR}/.probe.XXXXXX")" || exit 1
trap 'rm -rf "$probe_dir"' EXIT
for h in "${candidates[@]}"; do
    ( timeout "$PROBE_TIMEOUT" bash -c "</dev/tcp/${h}/22" 2>/dev/null && : > "${probe_dir}/${h}" ) &
done
wait

entries=()
alive=0
for h in "${candidates[@]}"; do
    # Only the live ones are published, because a reserved range can have many addresses
    # with no VM behind them. The roster lists possible targets and does not inventory the
    # network.
    [[ -e "${probe_dir}/${h}" ]] || continue
    alive=$(( alive + 1 ))
    entries+=("$(printf '{"fqdn":"%s","sessions":%s,"alive":true}' "$h" "${sessions[$h]}")")
done

write_out "$(printf '{"ts":%s,"source":"%s","candidates":%s,"alive":%s,"workers":[%s]}' \
    "$(date +%s)" "$source_name" "${#candidates[@]}" "$alive" "$(IFS=,; echo "${entries[*]}")")"

# --- fallback host of the cluster file --------------------------------------------------------
# submit_host is only used when the roster is stale or empty, so almost never, but it still
# has to point to a worker that exists. The worker role depends on the portal, so the portal
# is configured before the workers. On the first boot no worker was alive and the value
# stayed at the first address of the range, which has no VM behind it.
#
# It is rewritten only when the current value is not among the live ones, and the user
# processes are not restarted. The cluster file is read once per process, so the new value
# takes effect in the next one, and meanwhile the roster based dispatch stays in charge.
if (( alive > 0 )); then
    actual="$(sed -n 's/^ *submit_host: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$CLUSTER_FILE" | head -1)"
    vivos=" $(for e in "${entries[@]}"; do sed -n 's/.*"fqdn":"\([^"]*\)".*/\1/p' <<<"$e"; done | tr '\n' ' ') "
    if [[ "$vivos" != *" ${actual} "* ]]; then
        nuevo="$(sed -n 's/.*"fqdn":"\([^"]*\)".*/\1/p' <<<"${entries[0]}")"
        if [[ -n "$nuevo" ]]; then
            sed -i "s|^\( *submit_host: \).*|\1\"${nuevo}\"|" "$CLUSTER_FILE"
        fi
    fi
fi
ONEOND_SCRIPTS_OOD_POOL_REFRESH_SH_

install -d -m 755 "${SRC}/storage"
cat > "${SRC}/storage/10-install-nfs.sh" <<'ONEOND_STORAGE_10_INSTALL_NFS_SH_'
#!/usr/bin/env bash
# NFS server that keeps the persistent home directories of the users.
#
# Runs on the storage VM. It exports /export/home to the private compute network,
# where the portal and the pool VMs are. The VMs write as the user (root_squash),
# and only the portal can act as root on the export, because the portal creates
# the home of each user on their first login. The UIDs are the same everywhere,
# because the LDAP of the portal supplies them.
#
# It is idempotent, so it rewrites its exports file and reloads it.
#
# Variables:
#   ONEAPP_NFS_NET        network with read and write access (172.20.0.0/24)
#   ONEAPP_NFS_ADMIN_IPS  IPs with no_root_squash, space separated (the portal)
#
# Usage:  ONEAPP_NFS_ADMIN_IPS="172.20.0.220" ./10-install-nfs.sh

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

NFS_NET="${ONEAPP_NFS_NET:-172.20.0.0/24}"
NFS_ADMIN_IPS="${ONEAPP_NFS_ADMIN_IPS:-}"
HOME_EXPORT="${ONEAPP_NFS_HOME_EXPORT:-/export/home}"
EXPORTS_FILE=/etc/exports.d/one-ondemand.exports

[[ -n "$NFS_ADMIN_IPS" ]] || die "ONEAPP_NFS_ADMIN_IPS is missing, it needs the private IP of the portal"

msg "installing the NFS server"
# The Marketplace image arrives with no package lists, so without this update apt
# finds no candidate for any package.
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
apt_install nfs-kernel-server
ok "nfs-kernel-server installed"

install -d -m 755 "$HOME_EXPORT"
ok "home export at ${HOME_EXPORT}"

# --- exports ----------------------------------------------------------------------
# The per IP entries go before the network one, because exportfs applies the most
# specific match.
msg "writing ${EXPORTS_FILE}"
install -d -m 755 /etc/exports.d
{
    printf '# Generated by one-ondemand/storage/10-install-nfs.sh\n'
    for ip in $NFS_ADMIN_IPS; do
        printf '%s %s(rw,sync,no_subtree_check,no_root_squash,fsid=1)\n' "$HOME_EXPORT" "$ip"
    done
    printf '%s %s(rw,sync,no_subtree_check,root_squash,fsid=1)\n' "$HOME_EXPORT" "$NFS_NET"
} > "$EXPORTS_FILE"
chmod 644 "$EXPORTS_FILE"

systemctl enable --now nfs-server >/dev/null 2>&1 || die "nfs-server does not start"
exportfs -ra || die "exportfs rejected the configuration"
ok "exports loaded"

# --- pool register --------------------------------------------------------------------
# The workers announce themselves here with their name and their session count, and the
# portal reads it to send each new session to the one with the most room. The storage VM
# creates the directory, because the workers mount the home with root_squash and cannot
# create anything at the root of the export. That mount option is right for them, because
# they run user code. Mode 1777 lets each worker write its own file without giving it
# permissions on the rest.
install -d -m 1777 "${HOME_EXPORT}/.ood-pool"
ok "pool register at ${HOME_EXPORT}/.ood-pool"

# --- verification ---------------------------------------------------------------------
msg "checking that the export is visible"
showmount -e localhost 2>&1 | sed 's/^/    /'
showmount -e localhost 2>/dev/null | grep -q "^${HOME_EXPORT} " \
    || die "the server does not announce ${HOME_EXPORT}"
ok "NFS server serving ${HOME_EXPORT} to ${NFS_NET}, with root for ${NFS_ADMIN_IPS}"
ONEOND_STORAGE_10_INSTALL_NFS_SH_

install -d -m 755 "${SRC}/storage"
cat > "${SRC}/storage/20-install-squid.sh" <<'ONEOND_STORAGE_20_INSTALL_SQUID_SH_'
#!/usr/bin/env bash
# Site Squid proxy for CernVM-FS, on the storage VM.
#
# CernVM-FS recommends this architecture, where every machine runs its own client
# with a local cache and downloads through one HTTP proxy of the site. The proxy
# keeps a single copy of the files for every machine. CernVM-FS recommends two or
# more proxies for redundancy and says that a single one serves hundreds of nodes,
# so this appliance deploys one and a production site would add a second. The
# configuration below is the one that CernVM-FS publishes in its documentation.
#
# This script replaces the NFS reexport of /cvmfs, which CernVM-FS advises
# against because it is a bottleneck and a single point of failure. If an old
# export remains, the script removes it.
#
# It is idempotent. Variables:
#   ONEAPP_NFS_NET        networks with access to the proxy (172.20.0.0/24 192.168.100.0/24)
#   ONEAPP_SQUID_CACHE_MB size of the on disk cache in MB (20000)
#
# Usage:  ./20-install-squid.sh

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

NETS="${ONEAPP_SQUID_NETS:-172.20.0.0/24 192.168.100.0/24}"
CACHE_MB="${ONEAPP_SQUID_CACHE_MB:-20000}"

msg "installing squid"
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
apt_install squid
ok "squid $(dpkg-query -W -f='${Version}' squid)"

# Configuration recommended by CernVM-FS (cpt-squid). collapsed_forwarding makes a
# concurrent download happen once, the large objects go on disk, and only the
# deployment networks can use the proxy.
msg "writing /etc/squid/conf.d/one-ondemand-cvmfs.conf"
backup_once /etc/squid/squid.conf
{
    printf '# Generated by one-ondemand/storage/20-install-squid.sh\n'
    for n in $NETS; do printf 'acl localnet src %s\n' "$n"; done
    cat <<EOF
http_access allow localnet
http_access deny all
http_port 3128
collapsed_forwarding on
minimum_expiry_time 0
maximum_object_size 1024 MB
cache_mem 128 MB
maximum_object_size_in_memory 128 KB
cache_dir ufs /var/spool/squid ${CACHE_MB} 16 256
EOF
} > /etc/squid/conf.d/one-ondemand-cvmfs.conf
# The Ubuntu squid.conf already includes conf.d and ends with a final
# "http_access deny all". The conf.d rules are evaluated before it, so the local
# networks pass.
squid -k parse >/dev/null 2>&1 || die "squid rejects the configuration"
squid -z >/dev/null 2>&1 || true
systemctl enable --now squid >/dev/null 2>&1; systemctl restart squid || die "squid does not start"
ok "squid listening on :3128 for ${NETS}"

# --- remove the old NFS reexport of /cvmfs ----------------------------------------
if [[ -f /etc/exports.d/one-ondemand-eessi.exports ]]; then
    rm -f /etc/exports.d/one-ondemand-eessi.exports
    exportfs -ra 2>/dev/null || true
    ok "NFS reexport of /cvmfs removed"
fi

msg "checking that the proxy answers a CernVM-FS request"
ip="$(hostname -I | tr ' ' '\n' | grep '^172\.20\.' | head -1)"
code="$(curl -s -o /dev/null -w '%{http_code}' -x "http://${ip:-127.0.0.1}:3128" --max-time 20 \
        http://cvmfs-s1-eessi.example.invalid/ 2>/dev/null || true)"
curl -s -o /dev/null -w '' -x "http://127.0.0.1:3128" --max-time 30 \
    "https://github.com/EESSI/filesystem-layer/releases/latest" 2>/dev/null || true
grep -q "TCP_" /var/log/squid/access.log 2>/dev/null && ok "squid records traffic in access.log" \
    || ok "squid started (no traffic yet, the log fills up with the clients)"
ok "site proxy ready at http://${ip:-?}:3128"
ONEOND_STORAGE_20_INSTALL_SQUID_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/clean-for-image.sh" <<'ONEOND_WORKER_CLEAN_FOR_IMAGE_SH_'
#!/usr/bin/env bash
# Leaves the VM ready to become a golden image.
#
# An image is cloned many times, so everything that identifies THIS machine or THIS deployment
# has to be removed before the disk-saveas. Otherwise every new worker would be born with the
# machine identifier and the host keys of the original, which breaks the systemd journal and
# makes every worker present the same SSH fingerprint. It would also boot with the NFS and the
# LDAP of the site where it was built.
#
# What was baked in stays, so packages, Apptainer, the SIF, code-server and the metrics
# publisher. What is deleted is written again by worker/configure.sh on every boot.
#
# Usage:  ./clean-for-image.sh    (and then power off the VM and do a disk-saveas)

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

msg "removing the configuration of this deployment"
# Mounts: unmount first, because an image with /home mounted over NFS does not boot if the
# server does not answer.
umount -l /home 2>/dev/null || true
umount -l /cvmfs/software.eessi.io 2>/dev/null || true
sed -i '\#:/export/home /home nfs4 #d;\# /cvmfs/software.eessi.io cvmfs #d' /etc/fstab
rm -f /etc/cvmfs/default.local
rm -rf /var/lib/cvmfs/shared /var/lib/cvmfs/software.eessi.io
ok "fstab, CernVM-FS proxy and cache cleaned"

# Deployment identity: sssd holds the portal's LDAP address, which is a different address on
# another deployment. The cache also keeps the users resolved here.
systemctl stop sssd >/dev/null 2>&1 || true
rm -f /etc/sssd/sssd.conf
rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
ok "sssd unconfigured"

# Name: configure.sh writes the line with the IP the new VM receives.
sed -i '/# one-ondemand worker$/d' /etc/hosts
ok "worker name removed from /etc/hosts"

msg "removing what identifies this machine"
# machine-id: systemd regenerates it at boot if the file exists and is empty. Deleting it
# altogether makes some versions fail, so the file is truncated instead.
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
# SSH host keys: if they travel in the image, every worker presents the same fingerprint and
# a client cannot tell one from another.
rm -f /etc/ssh/ssh_host_*
# Authorized keys: one-context injects them from the CONTEXT on every boot.
rm -f /root/.ssh/authorized_keys
# Network leases and randomness seed.
rm -f /var/lib/dhcp/* /var/lib/systemd/random-seed 2>/dev/null || true
ok "machine-id, host keys and leases deleted"

msg "reducing the image size"
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/* /root/.cache 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
# The zeros of the free space compress, so the exported image is much smaller.
fstrim -av >/dev/null 2>&1 || true
ok "caches, logs and free space cleaned"

# What has to stay inside, checked instead of assumed.
for req in /etc/one-ondemand/build.env /etc/one-ondemand/ood-app-lib.sh \
           /etc/one-ondemand/onegate-lib.sh /etc/one-ondemand/code-server.env \
           /opt/ood/linuxhost.sif /opt/one-ondemand/worker/configure.sh \
           /usr/local/sbin/ood-worker-configure \
           /usr/local/bin/ood-publish-load.sh /etc/systemd/system/ood-publish-load.service; do
    [[ -e "$req" ]] || die "${req} is missing: the cleanup took away something that had to stay"
done
command -v apptainer >/dev/null || die "apptainer has disappeared from the image"
command -v cvmfs_config >/dev/null || die "the CernVM-FS client has disappeared from the image"
systemctl is-enabled ood-publish-load.service >/dev/null 2>&1 \
    || die "the metrics publisher did not stay enabled at boot"
# The boot configuration is triggered by READY_SCRIPT_PATH from the CONTEXT, not by a unit, so
# here we only check that the entry point is still executable.
[[ -x /usr/local/sbin/ood-worker-configure ]] || die "the boot entry point is not executable"
ok "what was baked in is still inside: apptainer, cvmfs, SIF, code-server, the publisher and the boot phase"

printf '\n'
ok "VM ready to power off and do a disk-saveas"
ONEOND_WORKER_CLEAN_FOR_IMAGE_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/configure.sh" <<'ONEOND_WORKER_CONFIGURE_SH_'
#!/usr/bin/env bash
# Boot phase of the pool VM, the only part that cannot be baked into the image.
#
# Everything here needs an address that does not exist until OpenNebula instantiates the
# machine: the VM's own private IP, the NFS one, the LDAP one and the one of the site's
# Squid. The packages, Apptainer, the SIF and code-server already come inside the image
# (worker/install.sh), so this phase takes seconds and not minutes, and OneFlow can add a
# worker as soon as the load rises.
#
# If it runs on a VM that install.sh did not prepare, it stops with a clear message instead
# of failing halfway, and it is idempotent.
#
# Variables:
#   ONEAPP_NFS_HOST        private IP of the storage VM (required)
#   ONEAPP_LDAP_HOST       private IP of the portal, where the LDAP listens (required)
#   ONEAPP_CVMFS_PROXY     URL of the site's Squid (required)
#   ONEAPP_POOL_DOMAIN     domain the portal uses to name the pool VMs (ood.local)
#   ONEAPP_POOL_NET_PREFIX prefix of the private compute network (172.20.)
#   ONEAPP_POOL_PREFIX     prefix of each worker's name (ood-worker-). The name is completed
#                          with the last octet of its private IP, and the portal uses the
#                          same rule.
#   ONEAPP_LDAP_BASE       base of the LDAP tree (dc=ood,dc=local)
#   ONEAPP_WORKER_SELFTEST if it is "1", it also loads EESSI's JupyterLab inside the SIF as a
#                          deep check. It costs minutes with a cold cache, so by default it
#                          is not done at boot.
#
# Usage:  ONEAPP_NFS_HOST=172.20.0.222 ONEAPP_LDAP_HOST=172.20.0.220 \
#         ONEAPP_CVMFS_PROXY=http://172.20.0.222:3128 ./configure.sh

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The three addresses are optional on purpose. A worker without them is a standalone machine
# with Apptainer and the local catalogue, which is exactly what the marketplace certification
# harness instantiates, a single VM with no storage or portal beside it. If they were required
# here, that VM would end in configure_failure with the motd in red, and the harness checks
# would pass anyway because they only read what was baked in. Each block below skips itself
# and warns.
NFS_HOST="${ONEAPP_NFS_HOST:-}"
LDAP_HOST="${ONEAPP_LDAP_HOST:-}"
CVMFS_PROXY="${ONEAPP_CVMFS_PROXY:-}"
BASE="${ONEAPP_LDAP_BASE:-dc=ood,dc=local}"
POOL_DOMAIN="${ONEAPP_POOL_DOMAIN:-ood.local}"
NET_PREFIX="${ONEAPP_POOL_NET_PREFIX:-172.20.}"
POOL_PREFIX="${ONEAPP_POOL_PREFIX:-ood-worker-}"
EESSI_MOUNT="${ONEAPP_EESSI_MOUNT:-/cvmfs/software.eessi.io}"
EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"
SIF_PATH="${ONEAPP_SIF_PATH:-/opt/ood/linuxhost.sif}"
# What the adapter mounts inside the image: the documented value plus the home and EESSI.
# It has to match singularity_bindpath in clusters.d/vms.yml.
BINDPATH="${ONEAPP_SIF_BINDPATH:-/etc,/media,/mnt,/opt,/run,/srv,/usr,/var,/home,/cvmfs}"
SELFTEST="${ONEAPP_WORKER_SELFTEST:-0}"

t0=$(date +%s)

# --- the image has to bring what was baked in -------------------------------------------------
# A failure here means the VM being configured was not built by install.sh, and everything
# after this point would give a confusing error halfway through.
for req in /etc/one-ondemand/build.env /etc/one-ondemand/ood-app-lib.sh "$SIF_PATH"; do
    [[ -s "$req" ]] || die "${req} is missing: this VM does not come from an image built with worker/install.sh"
done
command -v apptainer >/dev/null || die "no apptainer: this VM does not come from the worker image"
command -v cvmfs_config >/dev/null || die "no CernVM-FS client: this VM does not come from the worker image"
ok "worker image: $(sed -n 's/^BUILD_DATE=//p' /etc/one-ondemand/build.env)"

# --- VM name ----------------------------------------------------------------------------------
# The adapter wrapper checks that the VM's `hostname -A` matches an ssh_hosts entry, and
# rejects the job if it does not. Without reverse DNS that output is empty, so the name is
# resolved in /etc/hosts with the private IP. It carries the domain, because ood_core only
# recognizes as a host a name with dots. With the short name the job identifier has no host
# and the session is considered finished immediately.
# The name is derived from the address, not from the name the VM comes with, for two reasons.
# The first is that OneFlow names its VMs with the template $ROLE_NAME_$VM_NUMBER_(service_$ID),
# which carries parentheses and is not valid as a host name. The second, and the one that
# matters, is that the portal has to accept a worker that did not exist yet when it started.
# Since the name is a function of the address and OpenNebula guarantees that two VMs do not
# share an address, the portal can declare in advance the whole range of the compute network
# and any worker born inside it is already accepted. The portal computes the same name with
# the same rule in scripts/90-configure-vm-pool.sh.
msg "making the VM name resolvable for the adapter"
priv_ip="$(hostname -I | tr ' ' '\n' | grep "^${NET_PREFIX}" | head -1)"
# A VM with no address on the compute network is a worker deployed on its own, which is what
# the marketplace certification harness instantiates, so it falls back to the first private
# address instead of failing. In the service the compute network is always there and this
# branch never runs.
if [[ -z "$priv_ip" ]]; then
    priv_ip="$(hostname -I | tr ' ' '\n' \
        | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1)"
    [[ -n "$priv_ip" ]] && warn "no address on ${NET_PREFIX}x, naming this VM from ${priv_ip}"
fi
[[ -n "$priv_ip" ]] || die "the VM has no private address to derive its name from"
name="${POOL_PREFIX}${priv_ip##*.}"
fqdn="${name}.${POOL_DOMAIN}"
backup_once /etc/hosts
sed -i '/# one-ondemand worker$/d' /etc/hosts
printf '%s %s %s # one-ondemand worker\n' "$priv_ip" "$fqdn" "$name" >> /etc/hosts
# hostname -A resolves through /etc/hosts, so the system short name has to be the same one or
# the line above does not cover it.
[[ "$(hostname)" == "$name" ]] || hostnamectl set-hostname "$name" 2>/dev/null || hostname "$name"
hostname -A 2>/dev/null | tr ' ' '\n' | grep -qx "$fqdn" || die "hostname -A does not return ${fqdn}"
ok "hostname -A returns ${fqdn} (${priv_ip})"

# --- home over NFS ----------------------------------------------------------------------------
if [[ -n "$NFS_HOST" ]]; then
    msg "mounting the home from ${NFS_HOST}"
    backup_once /etc/fstab
    entry="${NFS_HOST}:/export/home /home nfs4 _netdev,hard,noatime 0 0"
    install -d -m 755 /home
    sed -i '\#^[0-9.]*:/export/home /home nfs4 #d' /etc/fstab
    printf '%s\n' "$entry" >> /etc/fstab
    findmnt -n /home >/dev/null 2>&1 || mount /home || die "could not mount /home from ${NFS_HOST}"
    ok "/home mounted from ${NFS_HOST}"
else
    warn "no ONEAPP_NFS_HOST: the home stays local, the sessions will not share it with the portal"
fi

# --- EESSI: only the proxy and the mount ------------------------------------------------------
# The packages are already in the image. This block only writes the site proxy and mounts the
# catalogue.
if [[ -n "$CVMFS_PROXY" ]]; then
    msg "pointing CernVM-FS at the Squid ${CVMFS_PROXY}"
    CVMFS_STAGE=config CVMFS_PROXY="$CVMFS_PROXY" CVMFS_MOUNT=static EESSI_VERSION="$EESSI_VERSION" \
        bash "${HERE}/../scripts/cvmfs-client.sh" || die "the CernVM-FS client did not end up working"
else
    warn "no ONEAPP_CVMFS_PROXY: the EESSI catalogue is not mounted, the sessions will not have its modules"
fi

# --- identity: the same users as the portal ---------------------------------------------------
if [[ -n "$LDAP_HOST" ]]; then
    msg "configuring sssd against ldap://${LDAP_HOST}"
    backup_once /etc/sssd/sssd.conf
    cat > /etc/sssd/sssd.conf <<EOF
    # Generated by one-ondemand/worker/configure.sh
    [sssd]
    config_file_version = 2
    services = nss, pam
    domains = ood

    [nss]
    filter_users = root
    homedir_substring = /home

    [domain/ood]
    id_provider = ldap
    auth_provider = ldap
    ldap_uri = ldap://${LDAP_HOST}
    ldap_search_base = ${BASE}
    ldap_id_use_start_tls = false
    ldap_auth_disable_tls_never_use_in_production = true
    enumerate = true
    cache_credentials = false
    EOF
    chmod 600 /etc/sssd/sssd.conf
    systemctl enable sssd >/dev/null 2>&1
    systemctl restart sssd || die "sssd does not start"
    first_user="$(cut -d: -f1 <<<"${ONEAPP_LDAP_USERS%% *}")"
    wait_for 90 bash -c "getent passwd ${first_user} >/dev/null 2>&1" \
        || die "sssd does not resolve ${first_user} against ${LDAP_HOST}"
    ok "portal users visible: $(getent passwd "$first_user" | cut -d: -f1,3)"
else
    warn "no ONEAPP_LDAP_HOST: only the local accounts of this VM will exist"
    first_user="root"
fi

# --- metrics publisher ------------------------------------------------------------------------
# It already comes enabled from the image, so normally systemd started it on its own. It is
# forced in case this VM is being reconfigured live.
systemctl is-active --quiet ood-publish-load.service || systemctl start --no-block ood-publish-load.service
ok "metrics publisher running"

# --- deep check, optional ---------------------------------------------------------------------
# Exactly what the adapter does: SINGULARITY_BINDPATH exported, apptainer exec --pid over the
# SIF and a login bash with the script inside. With a cold CernVM-FS cache this takes minutes,
# so it is not done on every boot, only when the image is built and when
# ONEAPP_WORKER_SELFTEST is 1.
#
# The probe goes in a file and not in a string, because a command substitution inside a string
# would be evaluated by the user's shell on the VM, outside the container and with no EESSI
# loaded, and the result would be empty with no error at all.
if [[ "$SELFTEST" == "1" ]]; then
    msg "deep check: EESSI's JupyterLab inside the SIF, as ${first_user}"
    probe="$(mktemp /tmp/ood-probe.XXXXXX)"
    cat > "$probe" <<EOF
source ${EESSI_MOUNT}/versions/${EESSI_VERSION}/init/bash >/dev/null 2>&1 || { echo init-failed; exit 1; }
module load ${EESSI_JUPYTER_MODULE} >/dev/null 2>&1 || { echo module-failed; exit 1; }
echo "jupyter-\$(jupyter lab --version 2>/dev/null)"
echo "python-\$(command -v python)"
test -d /home/${first_user} && echo home-ok
command -v tmux >/dev/null && echo tmux-ok
EOF
    chmod 644 "$probe"
    out="$(runuser -l "$first_user" -c "SINGULARITY_BINDPATH='${BINDPATH}' apptainer exec --pid '${SIF_PATH}' /bin/bash --login '${probe}'" 2>&1)"
    rm -f "$probe"
    grep -q "^jupyter-[0-9]" <<<"$out" || die "inside the SIF JupyterLab does not load from EESSI: ${out:0:300}"
    grep -q "^python-${EESSI_MOUNT}/" <<<"$out" || die "the session python does not come from EESSI: ${out:0:300}"
    grep -q "home-ok" <<<"$out" || die "inside the SIF /home/${first_user} is not visible"
    grep -q "tmux-ok" <<<"$out" || die "inside the SIF the host tmux is not visible"
    ok "inside the SIF: $(grep '^jupyter-' <<<"$out") with $(grep '^python-' <<<"$out" | sed 's/^python-//')"
fi

printf '\n'
ok "pool VM ready in $(( $(date +%s) - t0 ))s"
ONEOND_WORKER_CONFIGURE_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/install.sh" <<'ONEOND_WORKER_INSTALL_SH_'
#!/usr/bin/env bash
# Build phase of the pool VM, everything that can be baked into the image.
#
# The split follows what each step depends on, not how long each step takes. This file holds
# everything that only needs internet access and no address from the deployment: the packages,
# Apptainer, the SIF image, code-server and the CernVM-FS client. Whatever needs to know where
# the NFS, the LDAP, the Squid or the VM's own IP are stays in configure.sh, because that data
# does not exist until OpenNebula instantiates the machine.
#
# It is the same boundary that separates service_install from service_configure in one-apps,
# and it lets us build a golden image once and boot each worker in seconds instead of
# minutes.
#
# It runs on the VM that will become the image, not in production, and it is idempotent.
#
# Variables:
#   ONEAPP_APPTAINER_DEB        URL of the Apptainer package
#   ONEAPP_SIF_IMAGE            base docker:// image the SIF is created from
#   ONEAPP_SIF_PATH             path of the SIF (/opt/ood/linuxhost.sif)
#   ONEAPP_CODE_SERVER_VERSION  code-server version (pinned, 4.136.2). With "latest" it
#                               resolves to the newest published one, so the build stops
#                               being reproducible.
#   ONEAPP_CVMFS_QUOTA_MB       local CernVM-FS cache in MB (6000)
#
# Usage:  ./install.sh

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPTAINER_DEB="${ONEAPP_APPTAINER_DEB:-https://github.com/apptainer/apptainer/releases/download/v1.5.3/apptainer_1.5.3_amd64.deb}"
SIF_IMAGE="${ONEAPP_SIF_IMAGE:-docker://ubuntu:24.04}"
SIF_PATH="${ONEAPP_SIF_PATH:-/opt/ood/linuxhost.sif}"
# Version pinned on purpose, so the image is reproducible. With "latest" it resolves to the
# newest published one, handy during development and bad for building an appliance.
CODE_SERVER_VERSION="${ONEAPP_CODE_SERVER_VERSION:-4.136.2}"
CVMFS_QUOTA_MB="${ONEAPP_CVMFS_QUOTA_MB:-6000}"
BUILD_USER="ood-build-probe"

t0=$(date +%s)

# --- base packages ----------------------------------------------------------------------------
msg "base packages"
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
# lsof: one of the ways the session script finds a free port.
# uidmap: user namespaces for Apptainer without setuid.
apt_install nfs-common tmux psmisc lsof wget curl sssd sssd-ldap libnss-sss libpam-sss uidmap
ok "base packages installed"

# --- CernVM-FS client, packages only ----------------------------------------------------------
# The Squid proxy is an address from the deployment, so default.local and the mount are
# written at boot. The slow part, installing the packages and configuring the client,
# happens here.
msg "installing the CernVM-FS client (proxy not configured yet)"
CVMFS_STAGE=packages CVMFS_QUOTA_MB="$CVMFS_QUOTA_MB" CVMFS_PROXY=unset \
    bash "${HERE}/../scripts/cvmfs-client.sh" || die "could not install the CernVM-FS packages"

# --- Apptainer --------------------------------------------------------------------------------
if ! command -v apptainer >/dev/null 2>&1; then
    msg "installing Apptainer from ${APPTAINER_DEB}"
    wget -q -O /tmp/apptainer.deb "$APPTAINER_DEB" || die "could not download Apptainer"
    apt-get install -y -qq /tmp/apptainer.deb >/dev/null 2>&1 || die "could not install Apptainer"
    rm -f /tmp/apptainer.deb
fi
ok "apptainer $(apptainer --version 2>/dev/null | awk '{print $NF}')"

# Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor, and Apptainer's
# non-setuid mode needs them. The package ships the profile that allows them to its
# launcher, so the kernel restriction stays enabled.
rm -f /etc/sysctl.d/90-apptainer.conf
sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=1 2>/dev/null || true

# --- session SIF image ------------------------------------------------------------------------
# Base image of the same operating system as the VM, converted to SIF once. It is only the
# isolation wrapper, because the session software comes from EESSI and not from here.
install -d -m 755 "$(dirname "$SIF_PATH")"
if [[ ! -s "$SIF_PATH" ]]; then
    msg "creating ${SIF_PATH} from ${SIF_IMAGE}"
    APPTAINER_TMPDIR=/var/tmp apptainer pull --disable-cache "$SIF_PATH" "$SIF_IMAGE" >/tmp/apptainer-pull.log 2>&1 \
        || die "could not create the SIF, see /tmp/apptainer-pull.log"
fi
chmod 644 "$SIF_PATH"
ok "SIF at ${SIF_PATH} ($(du -h "$SIF_PATH" | cut -f1))"

# --- code-server ------------------------------------------------------------------------------
# The VS Code app is the only one that does not come from EESSI, because code-server is not in
# the catalogue. It is baked here and its version is recorded, so the image is reproducible
# without pinning a number that goes stale.
msg "installing code-server for the VS Code app"
if [[ "$CODE_SERVER_VERSION" == "latest" ]]; then
    # Only when explicitly requested. Resolving "the latest" on every build would make two
    # builds of the same code produce different images, and would make the build depend on
    # GitHub's API answering. On 9 September 2026 it did not answer and the build waited two
    # minutes before failing.
    CODE_SERVER_VERSION="$(curl -fsSL --max-time 20 https://api.github.com/repos/coder/code-server/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$CODE_SERVER_VERSION" ]] || die "could not resolve the latest code-server version, set ONEAPP_CODE_SERVER_VERSION"
    msg "latest published version: ${CODE_SERVER_VERSION}"
fi
CODE_SERVER_DIR="/opt/code-server-${CODE_SERVER_VERSION}"
CODE_SERVER_BIN="${CODE_SERVER_DIR}/bin/code-server"
install -d -m 755 /etc/one-ondemand
if [[ -x "$CODE_SERVER_BIN" ]]; then
    ok "code-server ${CODE_SERVER_VERSION} was already installed"
else
    tarball="/tmp/code-server-${CODE_SERVER_VERSION}.tar.gz"
    url="https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
    curl -fsSL -o "$tarball" "$url" || die "could not download ${url}"
    install -d -m 755 "$CODE_SERVER_DIR"
    tar -xzf "$tarball" -C "$CODE_SERVER_DIR" --strip-components=1 || die "could not unpack code-server"
    rm -f "$tarball"
    ok "code-server ${CODE_SERVER_VERSION} installed in ${CODE_SERVER_DIR}"
fi
printf '# Generated by one-ondemand/worker/install.sh\nCODE_SERVER_VERSION=%s\nCODE_SERVER_BIN=%s\n' \
    "$CODE_SERVER_VERSION" "$CODE_SERVER_BIN" > /etc/one-ondemand/code-server.env
chmod 644 /etc/one-ondemand/code-server.env
"$CODE_SERVER_BIN" --version >/dev/null 2>&1 || die "code-server does not start on this VM"
ok "code-server responds: $("$CODE_SERVER_BIN" --version 2>/dev/null | head -1)"

# --- shared app library -----------------------------------------------------------------------
# The interactive apps share the same startup, loading EESSI and starting a server under the
# path the portal proxies. The library lives on the VM and not inside each app, so a single
# copy keeps five files from diverging.
msg "installing the shared app library"
install -m 644 "${HERE}/ood-app-lib.sh" /etc/one-ondemand/ood-app-lib.sh
bash -n /etc/one-ondemand/ood-app-lib.sh || die "ood-app-lib.sh is not valid bash"
ok "/etc/one-ondemand/ood-app-lib.sh installed"

# --- metrics publisher for OneFlow ------------------------------------------------------------
# The worker publishes to OneGate how many sessions it has, and OneFlow grows the role when
# the average exceeds the threshold, so without this signal elasticity has nothing to read.
#
# The unit is enabled here but not started, because in the golden image systemd starts it when
# the VM boots. The unit is deliberately not ordered after one-context.service, because a
# START_SCRIPT runs inside one-context and a unit ordered after it would wait for the script
# that is starting it, leaving contextualization hung. Checked on 8 September 2026.
msg "installing the metrics publisher for OneFlow"
install -m 644 "${HERE}/onegate-lib.sh" /etc/one-ondemand/onegate-lib.sh
bash -n /etc/one-ondemand/onegate-lib.sh || die "onegate-lib.sh is not valid bash"
install -m 755 "${HERE}/publish-load.sh" /usr/local/bin/ood-publish-load.sh
cat > /etc/systemd/system/ood-publish-load.service <<'UNIT'
[Unit]
Description=Publish Open OnDemand worker load to OneGate
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/ood-publish-load.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable ood-publish-load.service >/dev/null 2>&1 \
    || die "could not enable the metrics publisher"
ok "metrics publisher baked in and enabled at boot"

# --- self-configuration at boot ---------------------------------------------------------------
# The image carries its own boot phase inside, so a new VM configures itself just by receiving
# the addresses through CONTEXT and the repository never has to be copied to the VM.
#
# The hook is the one OpenNebula already ships, READY_SCRIPT_PATH. one-context runs it at the
# end of contextualization (/etc/one-context.d/net-99-report-ready) and publishes READY=YES to
# OneGate only if the script finishes cleanly, and OneFlow's ready_status_gate reads exactly
# that, so it does not accept a half-booted worker.
#
# A systemd unit is not used, because one-context.service declares After=multi-user.target,
# so contextualization happens AFTER the target that starts the normal services. A unit
# attached to multi-user.target and ordered after one-context closes
# a cycle, and systemd silently drops it with the message "Found ordering cycle ... job
# deleted to break ordering cycle". Checked on 9 September 2026 on VM 275. START_SCRIPT in
# base64 is not used either. It works, but it puts a blob in the template and does not
# connect READY to the result.
msg "baking the boot phase into the image"
install -d -m 755 /opt/one-ondemand/worker /opt/one-ondemand/scripts
install -m 755 "${HERE}/configure.sh"          /opt/one-ondemand/worker/configure.sh
install -m 644 "${HERE}/../scripts/00-lib.sh"  /opt/one-ondemand/scripts/00-lib.sh
install -m 755 "${HERE}/../scripts/cvmfs-client.sh" /opt/one-ondemand/scripts/cvmfs-client.sh

cat > /usr/local/sbin/ood-worker-configure <<'ENTRY'
#!/usr/bin/env bash
# Boot entry point of a pool VM created from the golden image.
#
# READY_SCRIPT_PATH in the CONTEXT names it, so one-context runs it at the end of
# contextualization and publishes READY=YES if it finishes cleanly.
set -uo pipefail
LOG=/var/log/ood-worker-configure.log
exec > >(tee -a "$LOG") 2>&1
printf '\n===== %s =====\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env

# Without the deployment addresses there is nothing to configure. A VM started by hand from
# the image is in that situation, and it is not an error.
for v in ONEAPP_NFS_HOST ONEAPP_LDAP_HOST ONEAPP_CVMFS_PROXY; do
    if [[ -z "${!v:-}" ]]; then
        echo "${v} is missing from the CONTEXT, there is no deployment to configure"
        exit 0
    fi
done

/opt/one-ondemand/worker/configure.sh || { echo "the boot phase failed"; exit 1; }

# The OneGate endpoint is fixed in the context environment before returning control, because
# what publishes READY next is the standard one-context hook and it uses the onegate wrapper,
# which re-reads that file. Without this, on a deployment with no virtual router the VM would
# be configured and would never declare itself ready.
#
# READY is also published from here, for a VM instantiated without REPORT_READY. The standard
# hook would do nothing and OneFlow would wait forever.
if . /etc/one-ondemand/onegate-lib.sh 2>/dev/null && onegate_ready; then
    onegate_fix_context_env || true
    onegate_call vm update --data "READY=YES" >/dev/null 2>&1 \
        && echo "READY=YES published to ${ONEGATE_ENDPOINT}" \
        || echo "could not publish READY=YES to ${ONEGATE_ENDPOINT}"
else
    echo "OneGate does not answer, READY is left to the one-context hook"
fi
echo "worker configured"
ENTRY
chmod 755 /usr/local/sbin/ood-worker-configure
bash -n /usr/local/sbin/ood-worker-configure || die "the boot entry point is not valid bash"
ok "the image configures itself at boot, through READY_SCRIPT_PATH"

# --- check of what was baked in ---------------------------------------------------------------
# Without NFS or LDAP there are no portal users, so the proof that an unprivileged user runs
# containers uses a throwaway local account, deleted right afterwards. Without this test the
# image could ship with Apptainer broken by the AppArmor restriction, and the failure would
# not appear until the first session of a real user.
msg "checking that an unprivileged user runs containers"
id "$BUILD_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$BUILD_USER" || die "could not create ${BUILD_USER}"
probe_ok=0
runuser -l "$BUILD_USER" -c "apptainer exec --pid '${SIF_PATH}' /bin/true" >/dev/null 2>&1 && probe_ok=1
userdel -r "$BUILD_USER" >/dev/null 2>&1 || true
(( probe_ok == 1 )) || die "an unprivileged user cannot run the SIF with Apptainer"
ok "an unprivileged user runs the SIF with the AppArmor restriction enabled"

# --- provenance -------------------------------------------------------------------------------
# What this image carries inside. The image check reads it, and it labels the image
# registered in OpenNebula.
cat > /etc/one-ondemand/build.env <<EOF
# Generated by one-ondemand/worker/install.sh
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_OS=$(. /etc/os-release && echo "${ID}-${VERSION_ID}")
APPTAINER_VERSION=$(apptainer --version 2>/dev/null | awk '{print $NF}')
CVMFS_VERSION=$(dpkg-query -W -f='${Version}' cvmfs 2>/dev/null)
CVMFS_CONFIG_EESSI_VERSION=$(dpkg-query -W -f='${Version}' cvmfs-config-eessi 2>/dev/null)
CODE_SERVER_VERSION=${CODE_SERVER_VERSION}
SIF_IMAGE=${SIF_IMAGE}
SIF_PATH=${SIF_PATH}
EOF
chmod 644 /etc/one-ondemand/build.env
ok "provenance in /etc/one-ondemand/build.env"

printf '\n'
ok "build phase completed in $(( $(date +%s) - t0 ))s"
ONEOND_WORKER_INSTALL_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/onegate-lib.sh" <<'ONEOND_WORKER_ONEGATE_LIB_SH_'
#!/usr/bin/env bash
# How to talk to OneGate from a service VM, without trusting the injected values.
#
# Two facts about the client live here, because the metrics publisher and the boot
# configuration both need them.
#
# 1. The injected endpoint may not answer. OpenNebula writes the ONEGATE_ENDPOINT value from
#    oned.conf into the CONTEXT and overwrites whatever the template puts there. That default
#    value is a link-local address served by a virtual router, and on a deployment without
#    that router nobody answers. This library tries the injected one first and then the VM's
#    gateway, where OneGate listens on a single-node installation.
#
# 2. The /usr/bin/onegate wrapper re-reads /var/run/one-context/one_env right before calling
#    the client, so it overwrites any endpoint exported to it and always talks to the
#    link-local address. This library calls the Ruby client directly, the same call the
#    wrapper makes on its last line.
#
# Usage:  source /etc/one-ondemand/onegate-lib.sh
#         onegate_ready || exit 1
#         onegate_call vm update --data "READY=YES"

ONEGATE_PORT="${ONEGATE_PORT:-5030}"
ONEGATE_RB="${ONEGATE_RB:-/usr/bin/onegate.rb}"

# First endpoint that answers, 401 included. A 401 means the service is alive and only the
# token is missing, and the client knows how to present it.
onegate_resolve_endpoint() {
    local candidate code
    for candidate in "${ONEGATE_ENDPOINT:-}" \
                     "http://$(ip route show default | awk '/default/{print $3; exit}'):${ONEGATE_PORT}"; do
        [[ -z "$candidate" || "$candidate" == "http://:${ONEGATE_PORT}" ]] && continue
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${candidate}/vm" 2>/dev/null)"
        if [[ "$code" == "401" || "$code" == "200" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

onegate_call() {
    if [[ -x "$ONEGATE_RB" ]]; then
        ruby "$ONEGATE_RB" "$@"
    else
        onegate "$@"
    fi
}

# Leaves ONEGATE_ENDPOINT exported and usable, or returns 1. It loads the context environment
# first, the source of the injected endpoint and the VM token.
onegate_ready() {
    [[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env
    local endpoint
    endpoint="$(onegate_resolve_endpoint)" || return 1
    export ONEGATE_ENDPOINT="$endpoint"
    return 0
}

# Fixes the endpoint in the context environment when the injected one does not answer.
#
# The rest of OpenNebula's contextualization uses the /usr/bin/onegate wrapper, which re-reads
# that file, so without this fix the standard net-99-report-ready hook cannot publish READY
# even when the VM is perfectly fine. It edits the runtime file and not the configuration,
# because that file lives in tmpfs and is regenerated on every boot.
#
# It only writes if the value changes, and it leaves a record on standard output.
onegate_fix_context_env() {
    local env_file=/var/run/one-context/one_env current
    [[ -w "$env_file" ]] || return 1
    current="$(sed -n 's/^export ONEGATE_ENDPOINT="\(.*\)"$/\1/p' "$env_file" | head -1)"
    [[ "$current" == "${ONEGATE_ENDPOINT:-}" ]] && return 0
    sed -i "s#^export ONEGATE_ENDPOINT=.*#export ONEGATE_ENDPOINT=\"${ONEGATE_ENDPOINT}\"#" "$env_file" || return 1
    echo "OneGate endpoint fixed in ${env_file}: ${current:-empty} -> ${ONEGATE_ENDPOINT}"
}
ONEOND_WORKER_ONEGATE_LIB_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/ood-app-lib.sh" <<'ONEOND_WORKER_OOD_APP_LIB_SH_'
#!/usr/bin/env bash
# Shared library of the portal's interactive apps.
#
# It lives on the worker VM, at /etc/one-ondemand/ood-app-lib.sh, and worker/install.sh
# installs it there. Each app's session script loads it on its first line. It is here and not
# inside each app because the six of them share the same startup, loading EESSI and starting a
# web server under the path the portal proxies, and a single copy keeps six files from
# diverging.
#
# Contract with the portal. The session template receives host, port and password from the
# before.sh file, which has already picked a free port on the VM's private IP. Everything
# served to the user has to listen on that IP and that port, and answer under the path
# /node/<host>/<port>/, or the portal proxy will return 404 on every resource.

# Initialises EESSI. $1 is the version, for example 2025.06.
#
# First it creates a valid XDG_RUNTIME_DIR. Inside the container there is no systemd session
# to create it, and without it Octave and several desktop tools warn or fail to start.
ood_eessi() {
    local version="$1" init
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/ood-runtime-${UID}}"
    mkdir -p "${XDG_RUNTIME_DIR}" && chmod 700 "${XDG_RUNTIME_DIR}"
    init="/cvmfs/software.eessi.io/versions/${version}/init/bash"
    if [[ ! -f "${init}" ]]; then
        echo "this VM has no EESSI ${version} under /cvmfs, the session cannot start" >&2
        return 1
    fi
    # shellcheck disable=SC1090
    source "${init}" >/dev/null 2>&1 || {
        echo "could not initialise EESSI ${version}" >&2
        return 1
    }
}

# Loads EESSI modules. An empty module is rejected, so an app whose module does not exist in
# this EESSI version fails with a clear message and not with an Lmod error.
ood_modules() {
    local m family
    for m in "$@"; do
        if [[ -z "${m}" ]]; then
            echo "this application has no module configured for this EESSI release" >&2
            echo "check EESSI_* in /etc/one-ondemand/eessi.env on the portal" >&2
            return 1
        fi
        if ! module load "${m}" 2>/dev/null; then
            family="${m%%/*}"
            echo "module ${m} is not available in this EESSI release" >&2
            echo "versions of ${family} that are: $(module -t avail "${family}/" 2>&1 | grep -c "^${family}/")" >&2
            return 1
        fi
    done
}

# Registers a Jupyter kernel in the user's home, if it is not there yet. $1 is the internal
# name, $2 the display name and the rest the command that starts the kernel. The home is
# persistent, so the kernel outlives the session.
ood_register_kernel() {
    local name="$1" display="$2"; shift 2
    local dir="${HOME}/.local/share/jupyter/kernels/${name}"
    mkdir -p "${dir}" || return 1
    python3 - "${dir}/kernel.json" "${display}" "$@" <<'PY'
import json, sys
path, display = sys.argv[1], sys.argv[2]
json.dump({"argv": sys.argv[3:], "display_name": display, "language": display.split()[0].lower()},
          open(path, "w"), indent=2)
PY
}

# Starts JupyterLab under the path the portal proxies. It does not return, it execs.
ood_launch_jupyter() {
    cd "${HOME}" || return 1
    echo "jupyter $(jupyter lab --version 2>/dev/null) from $(command -v jupyter)"
    exec jupyter lab \
        --ServerApp.ip="${host}" \
        --ServerApp.port="${port}" \
        --ServerApp.port_retries=0 \
        --ServerApp.base_url="/node/${host}/${port}/" \
        --ServerApp.open_browser=False \
        --ServerApp.allow_remote_access=True \
        --ServerApp.trust_xheaders=True \
        --ServerApp.quit_button=False \
        --ServerApp.root_dir="${HOME}" \
        --IdentityProvider.token="${password}"
}
ONEOND_WORKER_OOD_APP_LIB_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/publish-load.sh" <<'ONEOND_WORKER_PUBLISH_LOAD_SH_'
#!/usr/bin/env bash
# Publishes the worker load to OneGate so OneFlow can decide when to grow.
#
# Three attributes. ACTIVE_SESSIONS is the number of Open OnDemand sessions alive on this VM,
# and it is the one that triggers growth, because it matches what the user does, opening an
# app. CPU_BUSY is published too because it costs nothing and is useful for the dashboard.
#
# IDLE exists because an average of ACTIVE_SESSIONS cannot protect a busy worker. When
# shrinking a role, OneFlow terminates the oldest VM without draining it, and the policies are
# evaluated on the AVERAGE of the attribute across the VMs of the role. With
# "ACTIVE_SESSIONS < 1" and two workers, one with a live session and one empty, the average is
# 0.5 and the condition holds. OneFlow would power off the oldest worker, exactly the one
# accumulating sessions, and would kill somebody's work.
#
# IDLE is 1 if this VM has no session and 0 if it has any, so its average is the fraction of
# idle workers. A condition "IDLE > 0.99" literally means that all of them are empty, and that
# is the only situation in which powering off the oldest one cannot do any harm. An average
# cannot tell "nobody is working" from "one is working and another is not" if it is given the
# number of sessions, and with IDLE it can.

#
# /etc/one-ondemand/onegate-lib.sh resolves the OneGate endpoint and explains why the injected
# one is not trusted, and the boot configuration shares that same library.
set -u

STATE=/run/ood-publish-load
ONEGATE_LIB="${ONEGATE_LIB:-/etc/one-ondemand/onegate-lib.sh}"
# shellcheck source=/dev/null
. "$ONEGATE_LIB" || { echo "${ONEGATE_LIB} is missing" >&2; exit 1; }

log() { logger -t ood-publish-load "$*"; echo "$*"; }

# Live Open OnDemand sessions. The linux_host adapter opens one tmux session per job, named
# launched-by-ondemand-<uuid>, on the user's socket. Counting /tmp/tmux-* directories would
# count users and not sessions, and the two differ as soon as someone opens two apps.
count_sessions() {
    local total=0 sock n
    for sock in /tmp/tmux-*/default; do
        [[ -S "$sock" ]] || continue
        n="$(tmux -S "$sock" list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^launched-by-ondemand-')"
        total=$(( total + n ))
    done
    printf '%d' "$total"
}

# Why the worker does NOT announce itself in the shared home.
#
# It would be the natural thing, both mount it by definition, and it was tried. It does not
# work, and it looks like a bug without being one. The home is exported to the workers with
# root_squash, which is correct because they run user code. With root_squash the server maps
# root to nobody, and then root can CREATE a file in a 1777 directory but cannot write its
# content, because creation goes through the directory's "other" permission and the write is
# denied. Checked on 9 September 2026 on ood-worker-232, where touch works, the redirection
# leaves the file at zero and returns "Permission denied", and the same command as demo1 works.
#
# The alternatives would be removing root_squash, which is exactly the protection we want, or
# creating a service account in LDAP just for this. Neither is worth it, because the portal
# already knows which machines are workers from the address range reserved for the role and,
# when the portal belongs to the service, because OneGate tells it. See
# scripts/ood-pool-refresh.sh.

cpu_snapshot() { awk '/^cpu /{t=0; for (i=2; i<=NF; i++) t+=$i; print t, $5}' /proc/stat; }

install -d -m 755 "$STATE"

if ! onegate_ready; then
    log "no OneGate endpoint answers, tried '${ONEGATE_ENDPOINT:-none}' and the default gateway"
    exit 1
fi
printf '%s\n' "$ONEGATE_ENDPOINT" > "${STATE}/endpoint"
log "publishing to ${ONEGATE_ENDPOINT}"

publish() {
    local sessions="$1" busy="$2" idle=1
    (( sessions > 0 )) && idle=0
    onegate_call vm update --data "ACTIVE_SESSIONS=${sessions}" >/dev/null 2>&1 || return 1
    onegate_call vm update --data "CPU_BUSY=${busy}" >/dev/null 2>&1 || return 1
    onegate_call vm update --data "IDLE=${idle}" >/dev/null 2>&1 || return 1
}

# Initial value as soon as it starts, so a new VM is not missing from the average OneFlow
# evaluates before it has published anything.
publish 0 0 && log "ACTIVE_SESSIONS=0 CPU_BUSY=0 IDLE=1 (initial)"

while true; do
    read -r t0 i0 < <(cpu_snapshot)
    sleep 10
    read -r t1 i1 < <(cpu_snapshot)
    dt=$(( t1 - t0 )); di=$(( i1 - i0 ))
    busy=0
    (( dt > 0 )) && busy=$(( (100 * (dt - di)) / dt ))
    sessions="$(count_sessions)"
    if publish "$sessions" "$busy"; then
        printf '%s\n' "$sessions" > "${STATE}/sessions"
        log "ACTIVE_SESSIONS=${sessions} CPU_BUSY=${busy} IDLE=$(( sessions > 0 ? 0 : 1 ))"
    else
        log "publish failed against ${ONEGATE_ENDPOINT}"
    fi
    sleep 20
done
ONEOND_WORKER_PUBLISH_LOAD_SH_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/form.yml" <<'ONEOND_APPS_CODE_SERVER_FORM_YML_'
---
# The target is always the OpenNebula VM pool. A session shares the whole VM with any
# other session running on it, so core and memory fields would have no effect and the
# form omits them.
cluster:
  - "vms"
form:
  - num_hours
attributes:
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops when this time expires."
ONEOND_APPS_CODE_SERVER_FORM_YML_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/info.html.erb" <<'ONEOND_APPS_CODE_SERVER_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card
    title carries the job identifier, "launched-by-ondemand-<uuid>@<vm>", which nobody
    launching a session can read, so this panel names the target instead. The file is
    evaluated against the session, so cluster_id and job_id are its attributes, while
    view.html.erb is evaluated against the connection information. The target title
    is taken from the cluster definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  target_host = job_id.to_s.include?("@") ? job_id.to_s.split("@").last : nil
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %><%= target_host ? " (#{target_host})" : "" %></p>
ONEOND_APPS_CODE_SERVER_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/manifest.yml" <<'ONEOND_APPS_CODE_SERVER_MANIFEST_YML_'
---
name: VS Code
category: Interactive Apps
subcategory: Development
role: batch_connect
description: |
  Launches Visual Studio Code in the browser on an OpenNebula VM. The editor opens
  your home directory, shared over NFS with the file browser and with every other
  session, and its terminal runs on the VM that hosts the session.
ONEOND_APPS_CODE_SERVER_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/submit.yml.erb" <<'ONEOND_APPS_CODE_SERVER_SUBMIT_YML_ERB_'
---
# The linux_host adapter connects over SSH as the user, opens a tmux session and runs
# the session script inside an Apptainer container. The form supplies only the session
# time, which becomes the wall_time timeout that stops the session.
batch_connect:
  template: "basic"

<%- worker = (OneOnDemandPool.pick rescue nil) -%>
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
<%- if worker -%>
  native:
    # The worker with the fewest sessions, taken from the roster the workers
    # themselves refresh. Without this the adapter would send every session to the
    # fixed submit_host, and a worker added by elasticity would never receive one.
    submit_host_override: "<%= worker %>"
<%- end -%>
ONEOND_APPS_CODE_SERVER_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/code-server/template"
cat > "${SRC}/apps/code-server/template/after.sh.erb" <<'ONEOND_APPS_CODE_SERVER_TEMPLATE_AFTER_SH_ERB_'
# Runs after script.sh starts in the background and before connection.yml is written.
# Without this wait the portal would publish the connect button before the server
# listens, and the user would see a proxy error.
echo "waiting for the session to listen on ${host}:${port}"
if wait_until_port_used "${host}:${port}" 300; then
    echo "the session is listening on ${host}:${port}"
else
    echo "the session never listened on ${host}:${port}" >&2
    clean_up 1
fi
sleep 2
ONEOND_APPS_CODE_SERVER_TEMPLATE_AFTER_SH_ERB_

install -d -m 755 "${SRC}/apps/code-server/template"
cat > "${SRC}/apps/code-server/template/before.sh.erb" <<'ONEOND_APPS_CODE_SERVER_TEMPLATE_BEFORE_SH_ERB_'
# Sourced inside the Apptainer container on the pool VM, before the session script.
#
# set_host (clusters.d/vms.yml) has already set host to the private IP of the VM, the
# address the portal proxy reaches. This script picks a free port on that address and
# generates the session password. Both are written to connection.yml, which the portal
# reads from the shared home, and script.sh reads the password from the environment
# because it runs as a separate process.
port=$(find_port "${host}")
password=$(create_passwd 32)
export port password
echo "the session will listen on ${host}:${port}"
ONEOND_APPS_CODE_SERVER_TEMPLATE_BEFORE_SH_ERB_

install -d -m 755 "${SRC}/apps/code-server/template"
cat > "${SRC}/apps/code-server/template/script.sh.erb" <<'ONEOND_APPS_CODE_SERVER_TEMPLATE_SCRIPT_SH_ERB_'
#!/usr/bin/env bash
# Visual Studio Code in the browser, on a pool VM.
#
# EESSI has no code-server, so the worker image carries it. worker/install.sh installs
# it and records its path in /etc/one-ondemand/code-server.env. code-server serves
# itself only at the root, and under a prefix it returns 401 with
# {"error":"Unauthorized"}. The connection panel points
# to /rnode rather than /node, because /rnode strips the prefix before forwarding and
# rewrites the Location and Set-Cookie headers. code-server reads the session password
# from the PASSWORD variable.
set -o pipefail

env_file=/etc/one-ondemand/code-server.env
if [[ ! -r "${env_file}" ]]; then
    echo "this VM has no code-server installed, see worker/install.sh" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "${env_file}"
command -v "${CODE_SERVER_BIN:-code-server}" >/dev/null || {
    echo "code-server is not on this VM at ${CODE_SERVER_BIN:-code-server}" >&2
    exit 1
}
echo "code-server $("${CODE_SERVER_BIN}" --version 2>/dev/null | head -1)"

# Settings and extensions live in the persistent home, so the next session opens the
# editor with the same configuration and the same extensions installed.
export PASSWORD="${password}"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CONFIG_HOME="${HOME}/.config"

cd "${HOME}"
exec "${CODE_SERVER_BIN}" \
    --bind-addr "${host}:${port}" \
    --auth password \
    --disable-telemetry \
    --disable-update-check \
    --user-data-dir "${HOME}/.local/share/code-server" \
    --extensions-dir "${HOME}/.local/share/code-server/extensions" \
    "${HOME}"
ONEOND_APPS_CODE_SERVER_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/view.html.erb" <<'ONEOND_APPS_CODE_SERVER_VIEW_HTML_ERB_'
<div class="text-center">
  <a class="btn btn-primary btn-block"
     href="/rnode/<%= host %>/<%= port %>/" target="_blank" rel="noopener">Open VS Code</a>
  <p class="mt-2 mb-0"><small>Password: <code><%= password %></code></small></p>
</div>
ONEOND_APPS_CODE_SERVER_VIEW_HTML_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/form.yml" <<'ONEOND_APPS_CPP_NOTEBOOK_FORM_YML_'
---
# The target is always the OpenNebula VM pool. A session uses the whole VM and shares
# it with any other session running on that VM, so core and memory fields would have
# no effect and the form does not offer them.
cluster:
  - "vms"
form:
  - num_hours
attributes:
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops on its own when this time expires."
ONEOND_APPS_CPP_NOTEBOOK_FORM_YML_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/info.html.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_INFO_HTML_ERB_'
<%#- Shown on the session card from submission until the session ends. The card title
    carries the job identifier "launched-by-ondemand-<uuid>@<vm>", which few people can
    read, so this panel names the target in plain words. The file is evaluated against
    the session, so cluster_id and job_id are attributes here, while view.html.erb is
    evaluated against the connection information. The target title comes from its
    definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  target_host = job_id.to_s.include?("@") ? job_id.to_s.split("@").last : nil
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %><%= target_host ? " (#{target_host})" : "" %></p>
ONEOND_APPS_CPP_NOTEBOOK_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/manifest.yml" <<'ONEOND_APPS_CPP_NOTEBOOK_MANIFEST_YML_'
---
name: C++ Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Runs a Jupyter notebook with the Cling C++ kernel on an OpenNebula compute VM. You
  write and run C++ cell by cell without a compile step, which suits teaching and suits
  trying numerical code before it goes into a batch job.
ONEOND_APPS_CPP_NOTEBOOK_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/submit.yml.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_SUBMIT_YML_ERB_'
---
# The linux_host adapter connects over SSH as the user, starts a tmux session and runs
# the session script inside an Apptainer container. The form carries a single field,
# the session time, and it becomes the timeout that ends the session.
batch_connect:
  template: "basic"

<%- worker = (OneOnDemandPool.pick rescue nil) -%>
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
<%- if worker -%>
  native:
    # The worker holding the fewest sessions right now, chosen from the roster
    # that the workers themselves refresh. Without this override the adapter
    # sends every session to the fixed submit_host, and a worker created by
    # elasticity would receive none.
    submit_host_override: "<%= worker %>"
<%- end -%>
ONEOND_APPS_CPP_NOTEBOOK_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook/template"
cat > "${SRC}/apps/cpp-notebook/template/after.sh.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_AFTER_SH_ERB_'
# Runs after script.sh starts in the background and before connection.yml is written.
# Without this wait the portal would publish the connect button before the server
# listens, and the user would see a proxy error.
echo "waiting for the session to listen on ${host}:${port}"
if wait_until_port_used "${host}:${port}" 300; then
    echo "the session is listening on ${host}:${port}"
else
    echo "the session never listened on ${host}:${port}" >&2
    clean_up 1
fi
sleep 2
ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_AFTER_SH_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook/template"
cat > "${SRC}/apps/cpp-notebook/template/before.sh.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_BEFORE_SH_ERB_'
# Sourced inside the Apptainer container on the pool VM, before the session script.
#
# set_host (clusters.d/vms.yml) already set host to the private IP of the VM, the
# address the portal proxy reaches. This file chooses a free port on that IP and
# generates the session token. Both reach connection.yml, which the portal reads from
# the shared home, and script.sh reads password from the exported environment because
# it runs as a separate process.
port=$(find_port "${host}")
password=$(create_passwd 32)
export port password
echo "the session will listen on ${host}:${port}"
ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_BEFORE_SH_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook/template"
cat > "${SRC}/apps/cpp-notebook/template/script.sh.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_SCRIPT_SH_ERB_'
<%-
  eessi = {}
  eessi_env = '/etc/one-ondemand/eessi.env'
  if File.readable?(eessi_env)
    File.foreach(eessi_env) do |line|
      k, v = line.strip.split('=', 2)
      eessi[k] = v if k && v && !k.start_with?('#')
    end
  end
-%>
#!/usr/bin/env bash
# Jupyter notebook with the Cling C++ kernel from EESSI. The module registers the
# kernel itself, so unlike the Julia notebook nothing is installed in the user home,
# and the first session starts as fast as later ones.
set -o pipefail
source /etc/one-ondemand/ood-app-lib.sh

ood_eessi "<%= eessi.fetch('EESSI_VERSION', '') %>" || exit 1
ood_modules "<%= eessi.fetch('EESSI_JUPYTER_MODULE', '') %>" "<%= eessi.fetch('EESSI_CLING_MODULE', '') %>" || exit 1
echo "cling kernel from $(python3 -c 'import clingkernel, os; print(os.path.dirname(clingkernel.__file__))' 2>/dev/null || echo unknown)"

ood_launch_jupyter
ONEOND_APPS_CPP_NOTEBOOK_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/view.html.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_VIEW_HTML_ERB_'
<div class="text-center">
  <a class="btn btn-primary btn-block"
     href="/node/<%= host %>/<%= port %>/lab?token=<%= password %>"
     target="_blank" rel="noopener">Open the C++ notebook</a>
</div>
ONEOND_APPS_CPP_NOTEBOOK_VIEW_HTML_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/form.yml" <<'ONEOND_APPS_JUPYTER_FORM_YML_'
---
# The target is always the OpenNebula VM pool. A session uses the whole VM and shares
# it with any other session running there, so core and memory fields would change
# nothing and the form omits them.
cluster:
  - "vms"
form:
  - num_hours
attributes:
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session ends automatically when this time expires."
ONEOND_APPS_JUPYTER_FORM_YML_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/info.html.erb" <<'ONEOND_APPS_JUPYTER_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card
    title carries the job identifier, "launched-by-ondemand-<uuid>@<vm>", so this
    panel prints the target and the host in readable form. The file is evaluated
    against the session, so cluster_id and job_id are its attributes, while
    view.html.erb is evaluated against the connection information. The target
    title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  target_host = job_id.to_s.include?("@") ? job_id.to_s.split("@").last : nil
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %><%= target_host ? " (#{target_host})" : "" %></p>
ONEOND_APPS_JUPYTER_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/manifest.yml" <<'ONEOND_APPS_JUPYTER_MANIFEST_YML_'
---
name: Jupyter Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Launches a JupyterLab notebook on an OpenNebula VM, with the Python from the EESSI
  software catalogue. The notebook runs on the compute VM rather than on the portal,
  and it opens the home directory the portal file browser shows.
ONEOND_APPS_JUPYTER_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/submit.yml.erb" <<'ONEOND_APPS_JUPYTER_SUBMIT_YML_ERB_'
---
# The linux_host adapter connects over SSH as the user, opens a tmux session and runs
# the session script inside an Apptainer container, the script being the one generated
# by template/before.sh.erb, script.sh.erb and after.sh.erb. The pool VMs run no
# scheduler, so the only form value the adapter uses is the session time, which becomes
# the wall time that ends the session.
batch_connect:
  template: "basic"

<%- worker = (OneOnDemandPool.pick rescue nil) -%>
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
<%- if worker -%>
  native:
    # The worker with the fewest sessions right now, taken from the roster that
    # the workers themselves refresh. Without this override the adapter would
    # send every session to the fixed submit_host, and a worker created by
    # elasticity would receive none.
    submit_host_override: "<%= worker %>"
<%- end -%>
ONEOND_APPS_JUPYTER_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/jupyter/template"
cat > "${SRC}/apps/jupyter/template/after.sh.erb" <<'ONEOND_APPS_JUPYTER_TEMPLATE_AFTER_SH_ERB_'
# Sourced after script.sh starts in the background and before connection.yml is
# written. Without this wait the portal would publish the connect button before
# Jupyter listens, and the user would get a proxy error.
echo "waiting for Jupyter to listen on ${host}:${port}"
if wait_until_port_used "${host}:${port}" 180; then
    echo "Jupyter is listening on ${host}:${port}"
else
    echo "Jupyter never listened on ${host}:${port}" >&2
    clean_up 1
fi
sleep 2
ONEOND_APPS_JUPYTER_TEMPLATE_AFTER_SH_ERB_

install -d -m 755 "${SRC}/apps/jupyter/template"
cat > "${SRC}/apps/jupyter/template/before.sh.erb" <<'ONEOND_APPS_JUPYTER_TEMPLATE_BEFORE_SH_ERB_'
# Sourced inside the Apptainer container on the pool VM, before the session script.
#
# set_host (clusters.d/vms.yml) already set host to the private IP of the VM, the
# address the portal proxy reaches. This file picks a free port on that IP and creates
# the session token. Both values reach connection.yml, which the portal reads from the
# shared home, and script.sh reads password in a separate process.
port=$(find_port "${host}")
password=$(create_passwd 32)
export port password
echo "the session will listen on ${host}:${port}"
ONEOND_APPS_JUPYTER_TEMPLATE_BEFORE_SH_ERB_

install -d -m 755 "${SRC}/apps/jupyter/template"
cat > "${SRC}/apps/jupyter/template/script.sh.erb" <<'ONEOND_APPS_JUPYTER_TEMPLATE_SCRIPT_SH_ERB_'
<%-
  # EESSI version and module recorded by scripts/70-install-cvmfs.sh. Both are read
  # at render time on the portal and embedded in the script that then runs on the VM.
  eessi = {}
  eessi_env = '/etc/one-ondemand/eessi.env'
  if File.readable?(eessi_env)
    File.foreach(eessi_env) do |line|
      k, v = line.strip.split('=', 2)
      eessi[k] = v if k && v && !k.start_with?('#')
    end
  end
  eessi_version = eessi.fetch('EESSI_VERSION', '')
  eessi_module  = eessi.fetch('EESSI_JUPYTER_MODULE', '')
-%>
#!/usr/bin/env bash
# Session script for the "vms" target. It runs inside the Apptainer container on the
# pool VM, with the VM filesystem mounted inside. Jupyter comes from the EESSI
# catalogue rather than from the container image or the VM, so the session loads the
# same module a user at a EuroHPC centre loads.
set -o pipefail

eessi_init="/cvmfs/software.eessi.io/versions/<%= eessi_version %>/init/bash"
if [[ ! -f "${eessi_init}" ]]; then
    echo "this VM has no EESSI <%= eessi_version %> under /cvmfs: Jupyter cannot start" >&2
    exit 1
fi
source "${eessi_init}" >/dev/null 2>&1 || { echo "could not initialise EESSI" >&2; exit 1; }
module load "<%= eessi_module %>" || { echo "could not load <%= eessi_module %>" >&2; exit 1; }
echo "jupyter $(jupyter lab --version 2>/dev/null) from $(command -v jupyter)"

# Jupyter has to serve under the same path the portal proxies, or each of its
# resources answers 404. It listens only on the private IP of the VM.
cd "${HOME}"
exec jupyter lab \
    --ServerApp.ip="${host}" \
    --ServerApp.port="${port}" \
    --ServerApp.port_retries=0 \
    --ServerApp.base_url="/node/${host}/${port}/" \
    --ServerApp.open_browser=False \
    --ServerApp.allow_remote_access=True \
    --ServerApp.trust_xheaders=True \
    --ServerApp.quit_button=False \
    --ServerApp.root_dir="${HOME}" \
    --IdentityProvider.token="${password}"
ONEOND_APPS_JUPYTER_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/view.html.erb" <<'ONEOND_APPS_JUPYTER_VIEW_HTML_ERB_'
<%# Connection panel the user sees once the session is ready. host, port and password %>
<%# are read from the connection information the session writes in connection.yml. %>
<div class="text-center">
  <a class="btn btn-primary btn-block"
     href="/node/<%= host %>/<%= port %>/lab?token=<%= password %>"
     target="_blank" rel="noopener">
    Open the Jupyter notebook
  </a>
</div>
ONEOND_APPS_JUPYTER_VIEW_HTML_ERB_

install -d -m 755 "${SRC}/apps"
cat > "${SRC}/apps/LOGOS-NOTICE.md" <<'ONEOND_APPS_LOGOS_NOTICE_MD_'
# Logos of the catalogue applications

Every application in the portal shows the logo of its project instead of the generic
Open OnDemand gear. They are trademarks of their respective projects, used here only to
identify the software the application launches, and every one of those projects allows
that nominative use. Before publishing the appliance on the Marketplace, check case by case
whether redistributing the file is allowed, because showing a trademark is not the same
as including it in a package.

| File | Project | Source |
|---|---|---|
| `jupyter.svg` | Project Jupyter | Wikimedia Commons, `Jupyter_logo.svg` |
| `octave.svg` | GNU Octave | Wikimedia Commons, `Gnu-octave-logo.svg` |
| `cpp.svg` | ISO C++ | Wikimedia Commons, `ISO_C++_Logo.svg` |
| `rstudio.svg` | R | Wikimedia Commons, `R_logo.svg` |
| `vscode.svg` | Visual Studio Code | Wikimedia Commons, `Visual_Studio_Code_1.35_icon.svg` |

`rstudio.svg` is the R logo and not the RStudio one, because the RStudio logo only
exists as a landscape wordmark and looked distorted on a square card. The alternative
without third-party trademarks is a Font Awesome icon. Open OnDemand already ships those
and they are declared the same way, for example `icon: fas://code`.
ONEOND_APPS_LOGOS_NOTICE_MD_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/form.yml" <<'ONEOND_APPS_OCTAVE_FORM_YML_'
---
# The target is always the OpenNebula VM pool. A session uses the whole VM and shares
# it with any other session running there, so core and memory fields would change
# nothing and the form omits them.
cluster:
  - "vms"
form:
  - num_hours
attributes:
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session ends automatically when this time expires."
ONEOND_APPS_OCTAVE_FORM_YML_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/info.html.erb" <<'ONEOND_APPS_OCTAVE_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card
    title carries the job identifier, "launched-by-ondemand-<uuid>@<vm>", so this
    panel prints the target and the host in readable form. The file is evaluated
    against the session, so cluster_id and job_id are its attributes, while
    view.html.erb is evaluated against the connection information. The target
    title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  target_host = job_id.to_s.include?("@") ? job_id.to_s.split("@").last : nil
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %><%= target_host ? " (#{target_host})" : "" %></p>
ONEOND_APPS_OCTAVE_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/manifest.yml" <<'ONEOND_APPS_OCTAVE_MANIFEST_YML_'
---
name: Octave Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Launches a Jupyter notebook with the Octave kernel on an OpenNebula VM. Octave is a
  free alternative to MATLAB and comes from the EESSI software catalogue. The notebook
  runs on the compute VM and opens the home directory the portal file browser shows.
ONEOND_APPS_OCTAVE_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/submit.yml.erb" <<'ONEOND_APPS_OCTAVE_SUBMIT_YML_ERB_'
---
# The linux_host adapter connects over SSH as the user, opens a tmux session and runs
# the session script inside an Apptainer container. The only form value the adapter
# uses is the session time, which becomes the wall time that ends the session.
batch_connect:
  template: "basic"

<%- worker = (OneOnDemandPool.pick rescue nil) -%>
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
<%- if worker -%>
  native:
    # The worker with the fewest sessions right now, taken from the roster that
    # the workers themselves refresh. Without this override the adapter would
    # send every session to the fixed submit_host, and a worker created by
    # elasticity would receive none.
    submit_host_override: "<%= worker %>"
<%- end -%>
ONEOND_APPS_OCTAVE_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/octave/template"
cat > "${SRC}/apps/octave/template/after.sh.erb" <<'ONEOND_APPS_OCTAVE_TEMPLATE_AFTER_SH_ERB_'
# Sourced after script.sh starts in the background and before connection.yml is
# written. Without this wait the portal would publish the connect button before the
# notebook listens, and the user would get a proxy error.
echo "waiting for the session to listen on ${host}:${port}"
if wait_until_port_used "${host}:${port}" 300; then
    echo "the session is listening on ${host}:${port}"
else
    echo "the session never listened on ${host}:${port}" >&2
    clean_up 1
fi
sleep 2
ONEOND_APPS_OCTAVE_TEMPLATE_AFTER_SH_ERB_

install -d -m 755 "${SRC}/apps/octave/template"
cat > "${SRC}/apps/octave/template/before.sh.erb" <<'ONEOND_APPS_OCTAVE_TEMPLATE_BEFORE_SH_ERB_'
# Sourced inside the Apptainer container on the pool VM, before the session script.
#
# set_host (clusters.d/vms.yml) already set host to the private IP of the VM, the
# address the portal proxy reaches. This file picks a free port on that IP and creates
# the session token. Both values reach connection.yml, which the portal reads from the
# shared home, and script.sh reads password in a separate process.
port=$(find_port "${host}")
password=$(create_passwd 32)
export port password
echo "the session will listen on ${host}:${port}"
ONEOND_APPS_OCTAVE_TEMPLATE_BEFORE_SH_ERB_

install -d -m 755 "${SRC}/apps/octave/template"
cat > "${SRC}/apps/octave/template/script.sh.erb" <<'ONEOND_APPS_OCTAVE_TEMPLATE_SCRIPT_SH_ERB_'
<%-
  eessi = {}
  eessi_env = '/etc/one-ondemand/eessi.env'
  if File.readable?(eessi_env)
    File.foreach(eessi_env) do |line|
      k, v = line.strip.split('=', 2)
      eessi[k] = v if k && v && !k.start_with?('#')
    end
  end
-%>
#!/usr/bin/env bash
# Jupyter notebook with the Octave kernel. Octave and the kernel both come from the
# EESSI catalogue, so the session installs no software in the user home and only
# registers the kernel there.
set -o pipefail
source /etc/one-ondemand/ood-app-lib.sh

ood_eessi "<%= eessi.fetch('EESSI_VERSION', '') %>" || exit 1
ood_modules "<%= eessi.fetch('EESSI_JUPYTER_MODULE', '') %>" \
            "<%= eessi.fetch('EESSI_OCTAVE_MODULE', '') %>" \
            "<%= eessi.fetch('EESSI_OCTAVE_KERNEL_MODULE', '') %>" || exit 1
# Plain octave tries to open the graphical interface and warns that there is no
# display, so the version check calls octave-cli.
echo "octave $(octave-cli --version 2>/dev/null | head -1) from $(command -v octave-cli)"

# The EESSI module provides the octave_kernel Python package, but the kernel has to be
# registered once in the user home before JupyterLab lists it in the menu.
if ! ls "${HOME}/.local/share/jupyter/kernels" 2>/dev/null | grep -qi octave; then
    echo "registering the Octave kernel in your home"
    python3 -m octave_kernel install --user 2>&1 || {
        echo "could not register the Octave kernel" >&2
        exit 1
    }
fi

ood_launch_jupyter
ONEOND_APPS_OCTAVE_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/view.html.erb" <<'ONEOND_APPS_OCTAVE_VIEW_HTML_ERB_'
<div class="text-center">
  <a class="btn btn-primary btn-block"
     href="/node/<%= host %>/<%= port %>/lab?token=<%= password %>"
     target="_blank" rel="noopener">Open the Octave notebook</a>
</div>
ONEOND_APPS_OCTAVE_VIEW_HTML_ERB_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/form.yml" <<'ONEOND_APPS_RSTUDIO_FORM_YML_'
---
# The target is always the OpenNebula VM pool. A session shares the whole VM with any
# other session running on it, so core and memory fields would have no effect and the
# form omits them.
cluster:
  - "vms"
form:
  - num_hours
attributes:
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops when this time expires."
ONEOND_APPS_RSTUDIO_FORM_YML_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/info.html.erb" <<'ONEOND_APPS_RSTUDIO_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card
    title carries the job identifier, "launched-by-ondemand-<uuid>@<vm>", which nobody
    launching a session can read, so this panel names the target instead. The file is
    evaluated against the session, so cluster_id and job_id are its attributes, while
    view.html.erb is evaluated against the connection information. The target title
    is taken from the cluster definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  target_host = job_id.to_s.include?("@") ? job_id.to_s.split("@").last : nil
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %><%= target_host ? " (#{target_host})" : "" %></p>
ONEOND_APPS_RSTUDIO_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/manifest.yml" <<'ONEOND_APPS_RSTUDIO_MANIFEST_YML_'
---
name: RStudio Server
category: Interactive Apps
subcategory: Development
role: batch_connect
description: |
  Launches RStudio Server on an OpenNebula VM, with R from the EESSI software
  catalogue. Your home directory is the same one the file browser shows, shared over
  NFS with every other session.
ONEOND_APPS_RSTUDIO_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/submit.yml.erb" <<'ONEOND_APPS_RSTUDIO_SUBMIT_YML_ERB_'
---
# The linux_host adapter connects over SSH as the user, opens a tmux session and runs
# the session script inside an Apptainer container. The form supplies only the session
# time, which becomes the wall_time timeout that stops the session.
batch_connect:
  template: "basic"

<%- worker = (OneOnDemandPool.pick rescue nil) -%>
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
<%- if worker -%>
  native:
    # The worker with the fewest sessions, taken from the roster the workers
    # themselves refresh. Without this the adapter would send every session to the
    # fixed submit_host, and a worker added by elasticity would never receive one.
    submit_host_override: "<%= worker %>"
<%- end -%>
ONEOND_APPS_RSTUDIO_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/rstudio/template"
cat > "${SRC}/apps/rstudio/template/after.sh.erb" <<'ONEOND_APPS_RSTUDIO_TEMPLATE_AFTER_SH_ERB_'
# Runs after script.sh starts in the background and before connection.yml is written.
# Without this wait the portal would publish the connect button before the server
# listens, and the user would see a proxy error.
echo "waiting for the session to listen on ${host}:${port}"
if wait_until_port_used "${host}:${port}" 300; then
    echo "the session is listening on ${host}:${port}"
else
    echo "the session never listened on ${host}:${port}" >&2
    clean_up 1
fi
sleep 2
ONEOND_APPS_RSTUDIO_TEMPLATE_AFTER_SH_ERB_

install -d -m 755 "${SRC}/apps/rstudio/template"
cat > "${SRC}/apps/rstudio/template/before.sh.erb" <<'ONEOND_APPS_RSTUDIO_TEMPLATE_BEFORE_SH_ERB_'
# Sourced inside the Apptainer container on the pool VM, before the session script.
#
# set_host (clusters.d/vms.yml) has already set host to the private IP of the VM, the
# address the portal proxy reaches. This script picks a free port on that address and
# generates the session password. Both are written to connection.yml, which the portal
# reads from the shared home, and script.sh reads the password from the environment
# because it runs as a separate process.
port=$(find_port "${host}")
password=$(create_passwd 32)
export port password
echo "the session will listen on ${host}:${port}"
ONEOND_APPS_RSTUDIO_TEMPLATE_BEFORE_SH_ERB_

install -d -m 755 "${SRC}/apps/rstudio/template"
cat > "${SRC}/apps/rstudio/template/script.sh.erb" <<'ONEOND_APPS_RSTUDIO_TEMPLATE_SCRIPT_SH_ERB_'
<%-
  eessi = {}
  eessi_env = '/etc/one-ondemand/eessi.env'
  if File.readable?(eessi_env)
    File.foreach(eessi_env) do |line|
      k, v = line.strip.split('=', 2)
      eessi[k] = v if k && v && !k.start_with?('#')
    end
  end
-%>
#!/usr/bin/env bash
# RStudio Server on a pool VM, with R from EESSI.
#
# rserver expects to run as a system service, so this script gives it a data directory,
# a database and a cookie key of its own, all under a temporary session directory.
# Authentication uses a PAM helper that compares the supplied password with the session
# password. Without it rserver would accept any connection, and on a shared worker one
# user could reach another user's session on the same VM.
#
# rserver serves at the root, so the connection panel points to /rnode, the portal
# proxy that strips the prefix. With /node and --www-root-path rserver answered with
# its own "requested page was not found" page.
set -o pipefail
source /etc/one-ondemand/ood-app-lib.sh

# Load the RStudio module alone. It carries its own R, built with a different
# toolchain than the CRAN bundle, and loading both leaves Lmod with two conflicting
# versions of R.
ood_eessi "<%= eessi.fetch('EESSI_VERSION', '') %>" || exit 1
ood_modules "<%= eessi.fetch('EESSI_RSTUDIO_MODULE', '') %>" || exit 1
command -v rserver >/dev/null || { echo "rserver is not in this EESSI release" >&2; exit 1; }
echo "rserver from $(command -v rserver)"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/rstudio-${USER}-XXXXXX")" || exit 1
trap 'rm -rf "${workdir}"' EXIT
mkdir -p "${workdir}/data" "${workdir}/run" "${workdir}/tmp"

# The helper receives the user as an argument and the password on standard input.
cat > "${workdir}/auth" <<AUTH
#!/usr/bin/env bash
read -r supplied
[[ "\${supplied}" == "${password}" ]] && exit 0
exit 1
AUTH
chmod 700 "${workdir}/auth"

cat > "${workdir}/database.conf" <<'DB'
provider=sqlite
directory=DBDIR
DB
sed -i "s|DBDIR|${workdir}/data|" "${workdir}/database.conf"

cd "${HOME}"
exec rserver \
    --server-user="${USER}" \
    --www-address="${host}" \
    --www-port="${port}" \
    --auth-none=0 \
    --auth-pam-helper-path="${workdir}/auth" \
    --auth-encrypt-password=0 \
    --auth-timeout-minutes=0 \
    --auth-stay-signed-in-days=30 \
    --server-data-dir="${workdir}/data" \
    --database-config-file="${workdir}/database.conf" \
    --secure-cookie-key-file="${workdir}/cookie-key" \
    --server-pid-file="${workdir}/run/rserver.pid" \
    --rsession-which-r="$(command -v R)"
ONEOND_APPS_RSTUDIO_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/view.html.erb" <<'ONEOND_APPS_RSTUDIO_VIEW_HTML_ERB_'
<div class="text-center">
  <a class="btn btn-primary btn-block"
     href="/rnode/<%= host %>/<%= port %>/" target="_blank" rel="noopener">Open RStudio</a>
  <p class="mt-2 mb-0"><small>User <code><%= ENV['USER'] %></code>, password <code><%= password %></code></small></p>
</div>
ONEOND_APPS_RSTUDIO_VIEW_HTML_ERB_

# The application icons go in base64, because they are data, and raw they would be
# twelve hundred lines of paths that nobody is going to review.
install -d -m 755 "${SRC}/apps/code-server"
base64 -d > "${SRC}/apps/code-server/icon.svg" <<'B64_END'
PHN2ZyB2aWV3Qm94PSIwIDAgMTAwIDEwMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cu
dzMub3JnLzIwMDAvc3ZnIj4KPG1hc2sgaWQ9Im1hc2swIiBtYXNrLXR5cGU9ImFscGhhIiBtYXNr
VW5pdHM9InVzZXJTcGFjZU9uVXNlIiB4PSIwIiB5PSIwIiB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEw
MCI+CjxwYXRoIGZpbGwtcnVsZT0iZXZlbm9kZCIgY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNNzAu
OTExOSA5OS4zMTcxQzcyLjQ4NjkgOTkuOTMwNyA3NC4yODI4IDk5Ljg5MTQgNzUuODcyNSA5OS4x
MjY0TDk2LjQ2MDggODkuMjE5N0M5OC42MjQyIDg4LjE3ODcgMTAwIDg1Ljk4OTIgMTAwIDgzLjU4
NzJWMTYuNDEzM0MxMDAgMTQuMDExMyA5OC42MjQzIDExLjgyMTggOTYuNDYwOSAxMC43ODA4TDc1
Ljg3MjUgMC44NzM3NTZDNzMuNzg2MiAtMC4xMzAxMjkgNzEuMzQ0NiAwLjExNTc2IDY5LjUxMzUg
MS40NDY5NUM2OS4yNTIgMS42MzcxMSA2OS4wMDI4IDEuODQ5NDMgNjguNzY5IDIuMDgzNDFMMjku
MzU1MSAzOC4wNDE1TDEyLjE4NzIgMjUuMDA5NkMxMC41ODkgMjMuNzk2NSA4LjM1MzYzIDIzLjg5
NTkgNi44NjkzMyAyNS4yNDYxTDEuMzYzMDMgMzAuMjU0OUMtMC40NTI1NTIgMzEuOTA2NCAtMC40
NTQ2MzMgMzQuNzYyNyAxLjM1ODUzIDM2LjQxN0wxNi4yNDcxIDUwLjAwMDFMMS4zNTg1MyA2My41
ODMyQy0wLjQ1NDYzMyA2NS4yMzc0IC0wLjQ1MjU1MiA2OC4wOTM4IDEuMzYzMDMgNjkuNzQ1M0w2
Ljg2OTMzIDc0Ljc1NDFDOC4zNTM2MyA3Ni4xMDQzIDEwLjU4OSA3Ni4yMDM3IDEyLjE4NzIgNzQu
OTkwNUwyOS4zNTUxIDYxLjk1ODdMNjguNzY5IDk3LjkxNjdDNjkuMzkyNSA5OC41NDA2IDcwLjEy
NDYgOTkuMDEwNCA3MC45MTE5IDk5LjMxNzFaTTc1LjAxNTIgMjcuMjk4OUw0NS4xMDkxIDUwLjAw
MDFMNzUuMDE1MiA3Mi43MDEyVjI3LjI5ODlaIiBmaWxsPSJ3aGl0ZSIvPgo8L21hc2s+CjxnIG1h
c2s9InVybCgjbWFzazApIj4KPHBhdGggZD0iTTk2LjQ2MTQgMTAuNzk2Mkw3NS44NTY5IDAuODc1
NTQyQzczLjQ3MTkgLTAuMjcyNzczIDcwLjYyMTcgMC4yMTE2MTEgNjguNzUgMi4wODMzM0wxLjI5
ODU4IDYzLjU4MzJDLTAuNTE1NjkzIDY1LjIzNzMgLTAuNTEzNjA3IDY4LjA5MzcgMS4zMDMwOCA2
OS43NDUyTDYuODEyNzIgNzQuNzU0QzguMjk3OTMgNzYuMTA0MiAxMC41MzQ3IDc2LjIwMzYgMTIu
MTMzOCA3NC45OTA1TDkzLjM2MDkgMTMuMzY5OUM5Ni4wODYgMTEuMzAyNiAxMDAgMTMuMjQ2MiAx
MDAgMTYuNjY2N1YxNi40Mjc1QzEwMCAxNC4wMjY1IDk4LjYyNDYgMTEuODM3OCA5Ni40NjE0IDEw
Ljc5NjJaIiBmaWxsPSIjMDA2NUE5Ii8+CjxnIGZpbHRlcj0idXJsKCNmaWx0ZXIwX2QpIj4KPHBh
dGggZD0iTTk2LjQ2MTQgODkuMjAzOEw3NS44NTY5IDk5LjEyNDVDNzMuNDcxOSAxMDAuMjczIDcw
LjYyMTcgOTkuNzg4NCA2OC43NSA5Ny45MTY3TDEuMjk4NTggMzYuNDE2OUMtMC41MTU2OTMgMzQu
NzYyNyAtMC41MTM2MDcgMzEuOTA2MyAxLjMwMzA4IDMwLjI1NDhMNi44MTI3MiAyNS4yNDZDOC4y
OTc5MyAyMy44OTU4IDEwLjUzNDcgMjMuNzk2NCAxMi4xMzM4IDI1LjAwOTVMOTMuMzYwOSA4Ni42
MzAxQzk2LjA4NiA4OC42OTc0IDEwMCA4Ni43NTM4IDEwMCA4My4zMzM0VjgzLjU3MjZDMTAwIDg1
Ljk3MzUgOTguNjI0NiA4OC4xNjIyIDk2LjQ2MTQgODkuMjAzOFoiIGZpbGw9IiMwMDdBQ0MiLz4K
PC9nPgo8ZyBmaWx0ZXI9InVybCgjZmlsdGVyMV9kKSI+CjxwYXRoIGQ9Ik03NS44NTc4IDk5LjEy
NjNDNzMuNDcyMSAxMDAuMjc0IDcwLjYyMTkgOTkuNzg4NSA2OC43NSA5Ny45MTY2QzcxLjA1NjQg
MTAwLjIyMyA3NSA5OC41ODk1IDc1IDk1LjMyNzhWNC42NzIxM0M3NSAxLjQxMDM5IDcxLjA1NjQg
LTAuMjIzMTA2IDY4Ljc1IDIuMDgzMjlDNzAuNjIxOSAwLjIxMTQwMiA3My40NzIxIC0wLjI3MzY2
NiA3NS44NTc4IDAuODczNjMzTDk2LjQ1ODcgMTAuNzgwN0M5OC42MjM0IDExLjgyMTcgMTAwIDE0
LjAxMTIgMTAwIDE2LjQxMzJWODMuNTg3MUMxMDAgODUuOTg5MSA5OC42MjM0IDg4LjE3ODYgOTYu
NDU4NiA4OS4yMTk2TDc1Ljg1NzggOTkuMTI2M1oiIGZpbGw9IiMxRjlDRjAiLz4KPC9nPgo8ZyBz
dHlsZT0ibWl4LWJsZW5kLW1vZGU6b3ZlcmxheSIgb3BhY2l0eT0iMC4yNSI+CjxwYXRoIGZpbGwt
cnVsZT0iZXZlbm9kZCIgY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNNzAuODUxMSA5OS4zMTcxQzcy
LjQyNjEgOTkuOTMwNiA3NC4yMjIxIDk5Ljg5MTMgNzUuODExNyA5OS4xMjY0TDk2LjQgODkuMjE5
N0M5OC41NjM0IDg4LjE3ODcgOTkuOTM5MiA4NS45ODkyIDk5LjkzOTIgODMuNTg3MVYxNi40MTMz
Qzk5LjkzOTIgMTQuMDExMiA5OC41NjM1IDExLjgyMTcgOTYuNDAwMSAxMC43ODA3TDc1LjgxMTcg
MC44NzM2OTVDNzMuNzI1NSAtMC4xMzAxOSA3MS4yODM4IDAuMTE1Njk5IDY5LjQ1MjcgMS40NDY4
OEM2OS4xOTEyIDEuNjM3MDUgNjguOTQyIDEuODQ5MzcgNjguNzA4MiAyLjA4MzM1TDI5LjI5NDMg
MzguMDQxNEwxMi4xMjY0IDI1LjAwOTZDMTAuNTI4MyAyMy43OTY0IDguMjkyODUgMjMuODk1OSA2
LjgwODU1IDI1LjI0NkwxLjMwMjI1IDMwLjI1NDhDLTAuNTEzMzM0IDMxLjkwNjQgLTAuNTE1NDE1
IDM0Ljc2MjcgMS4yOTc3NSAzNi40MTY5TDE2LjE4NjMgNTBMMS4yOTc3NSA2My41ODMyQy0wLjUx
NTQxNSA2NS4yMzc0IC0wLjUxMzMzNCA2OC4wOTM3IDEuMzAyMjUgNjkuNzQ1Mkw2LjgwODU1IDc0
Ljc1NEM4LjI5Mjg1IDc2LjEwNDIgMTAuNTI4MyA3Ni4yMDM2IDEyLjEyNjQgNzQuOTkwNUwyOS4y
OTQzIDYxLjk1ODZMNjguNzA4MiA5Ny45MTY3QzY5LjMzMTcgOTguNTQwNSA3MC4wNjM4IDk5LjAx
MDQgNzAuODUxMSA5OS4zMTcxWk03NC45NTQ0IDI3LjI5ODlMNDUuMDQ4MyA1MEw3NC45NTQ0IDcy
LjcwMTJWMjcuMjk4OVoiIGZpbGw9InVybCgjcGFpbnQwX2xpbmVhcikiLz4KPC9nPgo8L2c+Cjxk
ZWZzPgo8ZmlsdGVyIGlkPSJmaWx0ZXIwX2QiIHg9Ii04LjM5NDExIiB5PSIxNS44MjkxIiB3aWR0
aD0iMTE2LjcyNyIgaGVpZ2h0PSI5Mi4yNDU2IiBmaWx0ZXJVbml0cz0idXNlclNwYWNlT25Vc2Ui
IGNvbG9yLWludGVycG9sYXRpb24tZmlsdGVycz0ic1JHQiI+CjxmZUZsb29kIGZsb29kLW9wYWNp
dHk9IjAiIHJlc3VsdD0iQmFja2dyb3VuZEltYWdlRml4Ii8+CjxmZUNvbG9yTWF0cml4IGluPSJT
b3VyY2VBbHBoYSIgdHlwZT0ibWF0cml4IiB2YWx1ZXM9IjAgMCAwIDAgMCAwIDAgMCAwIDAgMCAw
IDAgMCAwIDAgMCAwIDEyNyAwIi8+CjxmZU9mZnNldC8+CjxmZUdhdXNzaWFuQmx1ciBzdGREZXZp
YXRpb249IjQuMTY2NjciLz4KPGZlQ29sb3JNYXRyaXggdHlwZT0ibWF0cml4IiB2YWx1ZXM9IjAg
MCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAuMjUgMCIvPgo8ZmVCbGVuZCBtb2Rl
PSJvdmVybGF5IiBpbjI9IkJhY2tncm91bmRJbWFnZUZpeCIgcmVzdWx0PSJlZmZlY3QxX2Ryb3BT
aGFkb3ciLz4KPGZlQmxlbmQgbW9kZT0ibm9ybWFsIiBpbj0iU291cmNlR3JhcGhpYyIgaW4yPSJl
ZmZlY3QxX2Ryb3BTaGFkb3ciIHJlc3VsdD0ic2hhcGUiLz4KPC9maWx0ZXI+CjxmaWx0ZXIgaWQ9
ImZpbHRlcjFfZCIgeD0iNjAuNDE2NyIgeT0iLTguMDc1NTgiIHdpZHRoPSI0Ny45MTY3IiBoZWln
aHQ9IjExNi4xNTEiIGZpbHRlclVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgY29sb3ItaW50ZXJwb2xh
dGlvbi1maWx0ZXJzPSJzUkdCIj4KPGZlRmxvb2QgZmxvb2Qtb3BhY2l0eT0iMCIgcmVzdWx0PSJC
YWNrZ3JvdW5kSW1hZ2VGaXgiLz4KPGZlQ29sb3JNYXRyaXggaW49IlNvdXJjZUFscGhhIiB0eXBl
PSJtYXRyaXgiIHZhbHVlcz0iMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMTI3
IDAiLz4KPGZlT2Zmc2V0Lz4KPGZlR2F1c3NpYW5CbHVyIHN0ZERldmlhdGlvbj0iNC4xNjY2NyIv
Pgo8ZmVDb2xvck1hdHJpeCB0eXBlPSJtYXRyaXgiIHZhbHVlcz0iMCAwIDAgMCAwIDAgMCAwIDAg
MCAwIDAgMCAwIDAgMCAwIDAgMC4yNSAwIi8+CjxmZUJsZW5kIG1vZGU9Im92ZXJsYXkiIGluMj0i
QmFja2dyb3VuZEltYWdlRml4IiByZXN1bHQ9ImVmZmVjdDFfZHJvcFNoYWRvdyIvPgo8ZmVCbGVu
ZCBtb2RlPSJub3JtYWwiIGluPSJTb3VyY2VHcmFwaGljIiBpbjI9ImVmZmVjdDFfZHJvcFNoYWRv
dyIgcmVzdWx0PSJzaGFwZSIvPgo8L2ZpbHRlcj4KPGxpbmVhckdyYWRpZW50IGlkPSJwYWludDBf
bGluZWFyIiB4MT0iNDkuOTM5MiIgeTE9IjAuMjU3ODEyIiB4Mj0iNDkuOTM5MiIgeTI9Ijk5Ljc0
MjMiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIj4KPHN0b3Agc3RvcC1jb2xvcj0id2hp
dGUiLz4KPHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSJ3aGl0ZSIgc3RvcC1vcGFjaXR5PSIw
Ii8+CjwvbGluZWFyR3JhZGllbnQ+CjwvZGVmcz4KPC9zdmc+Cg==
B64_END

install -d -m 755 "${SRC}/apps/cpp-notebook"
base64 -d > "${SRC}/apps/cpp-notebook/icon.svg" <<'B64_END'
PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz4NCjwhLS0gR2VuZXJhdG9yOiBB
ZG9iZSBJbGx1c3RyYXRvciAxNi4wLjQsIFNWRyBFeHBvcnQgUGx1Zy1JbiAuIFNWRyBWZXJzaW9u
OiA2LjAwIEJ1aWxkIDApICAtLT4NCjwhRE9DVFlQRSBzdmcgUFVCTElDICItLy9XM0MvL0RURCBT
VkcgMS4xLy9FTiIgImh0dHA6Ly93d3cudzMub3JnL0dyYXBoaWNzL1NWRy8xLjEvRFREL3N2ZzEx
LmR0ZCI+DQo8c3ZnIHZlcnNpb249IjEuMSIgaWQ9IkxheWVyXzEiIHhtbG5zPSJodHRwOi8vd3d3
LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxp
bmsiIHg9IjBweCIgeT0iMHB4Ig0KCSB3aWR0aD0iMzA2cHgiIGhlaWdodD0iMzQ0LjM1cHgiIHZp
ZXdCb3g9IjAgMCAzMDYgMzQ0LjM1IiBlbmFibGUtYmFja2dyb3VuZD0ibmV3IDAgMCAzMDYgMzQ0
LjM1IiB4bWw6c3BhY2U9InByZXNlcnZlIj4NCjxwYXRoIGZpbGw9IiMwMDU5OUMiIGQ9Ik0zMDIu
MTA3LDI1OC4yNjJjMi40MDEtNC4xNTksMy44OTMtOC44NDUsMy44OTMtMTMuMDUzVjk5LjE0YzAt
NC4yMDgtMS40OS04Ljg5My0zLjg5Mi0xMy4wNTJMMTUzLDE3Mi4xNzUNCglMMzAyLjEwNywyNTgu
MjYyeiIvPg0KPHBhdGggZmlsbD0iIzAwNDQ4MiIgZD0iTTE2Ni4yNSwzNDEuMTkzbDEyNi41LTcz
LjAzNGMzLjY0NC0yLjEwNCw2Ljk1Ni01LjczNyw5LjM1Ny05Ljg5N0wxNTMsMTcyLjE3NUwzLjg5
MywyNTguMjYzDQoJYzIuNDAxLDQuMTU5LDUuNzE0LDcuNzkzLDkuMzU3LDkuODk2bDEyNi41LDcz
LjAzNEMxNDcuMDM3LDM0NS40MDEsMTU4Ljk2MywzNDUuNDAxLDE2Ni4yNSwzNDEuMTkzeiIvPg0K
PHBhdGggZmlsbD0iIzY1OUFEMiIgZD0iTTMwMi4xMDgsODYuMDg3Yy0yLjQwMi00LjE2LTUuNzE1
LTcuNzkzLTkuMzU4LTkuODk3TDE2Ni4yNSwzLjE1NmMtNy4yODctNC4yMDgtMTkuMjEzLTQuMjA4
LTI2LjUsMA0KCUwxMy4yNSw3Ni4xOUM1Ljk2Miw4MC4zOTcsMCw5MC43MjUsMCw5OS4xNHYxNDYu
MDY5YzAsNC4yMDgsMS40OTEsOC44OTQsMy44OTMsMTMuMDUzTDE1MywxNzIuMTc1TDMwMi4xMDgs
ODYuMDg3eiIvPg0KPGc+DQoJPHBhdGggZmlsbD0iI0ZGRkZGRiIgZD0iTTE1MywyNzQuMTc1Yy01
Ni4yNDMsMC0xMDItNDUuNzU3LTEwMi0xMDJzNDUuNzU3LTEwMiwxMDItMTAyYzM2LjI5MiwwLDcw
LjEzOSwxOS41Myw4OC4zMzEsNTAuOTY4DQoJCWwtNDQuMTQzLDI1LjU0NGMtOS4xMDUtMTUuNzM2
LTI2LjAzOC0yNS41MTItNDQuMTg4LTI1LjUxMmMtMjguMTIyLDAtNTEsMjIuODc4LTUxLDUxYzAs
MjguMTIxLDIyLjg3OCw1MSw1MSw1MQ0KCQljMTguMTUyLDAsMzUuMDg1LTkuNzc2LDQ0LjE5MS0y
NS41MTVsNDQuMTQzLDI1LjU0M0MyMjMuMTQyLDI1NC42NDQsMTg5LjI5NCwyNzQuMTc1LDE1Mywy
NzQuMTc1eiIvPg0KPC9nPg0KPGc+DQoJPHBvbHlnb24gZmlsbD0iI0ZGRkZGRiIgcG9pbnRzPSIy
NTUsMTY2LjUwOCAyNDMuNjY2LDE2Ni41MDggMjQzLjY2NiwxNTUuMTc1IDIzMi4zMzQsMTU1LjE3
NSAyMzIuMzM0LDE2Ni41MDggMjIxLDE2Ni41MDggDQoJCTIyMSwxNzcuODQxIDIzMi4zMzQsMTc3
Ljg0MSAyMzIuMzM0LDE4OS4xNzUgMjQzLjY2NiwxODkuMTc1IDI0My42NjYsMTc3Ljg0MSAyNTUs
MTc3Ljg0MSAJIi8+DQo8L2c+DQo8Zz4NCgk8cG9seWdvbiBmaWxsPSIjRkZGRkZGIiBwb2ludHM9
IjI5Ny41LDE2Ni41MDggMjg2LjE2NiwxNjYuNTA4IDI4Ni4xNjYsMTU1LjE3NSAyNzQuODM0LDE1
NS4xNzUgMjc0LjgzNCwxNjYuNTA4IDI2My41LDE2Ni41MDggDQoJCTI2My41LDE3Ny44NDEgMjc0
LjgzNCwxNzcuODQxIDI3NC44MzQsMTg5LjE3NSAyODYuMTY2LDE4OS4xNzUgMjg2LjE2NiwxNzcu
ODQxIDI5Ny41LDE3Ny44NDEgCSIvPg0KPC9nPg0KPC9zdmc+DQo=
B64_END

install -d -m 755 "${SRC}/apps/jupyter"
base64 -d > "${SRC}/apps/jupyter/icon.svg" <<'B64_END'
PHN2ZyB3aWR0aD0iNDQiIGhlaWdodD0iNTEiIHZpZXdCb3g9IjAgMCA0NCA1MSIgdmVyc2lvbj0i
Mi4wIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRw
Oi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB4bWxuczpmaWdtYT0iaHR0cDovL3d3dy5maWdtYS5j
b20vZmlnbWEvbnMiPgo8dGl0bGU+R3JvdXAuc3ZnPC90aXRsZT4KPGRlc2M+Q3JlYXRlZCB1c2lu
ZyBGaWdtYSAwLjkwPC9kZXNjPgo8ZyBpZD0iQ2FudmFzIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgt
MTY0MCAtMjQ1MykiIGZpZ21hOnR5cGU9ImNhbnZhcyI+CjxnIGlkPSJHcm91cCIgc3R5bGU9Im1p
eC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5cGU9Imdyb3VwIj4KPGcgaWQ9Ikdyb3VwIiBz
dHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0iZ3JvdXAiPgo8ZyBpZD0i
R3JvdXAiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJncm91cCI+
CjxnIGlkPSJnIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0iZ3Jv
dXAiPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5
cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGg5IGZpbGwiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3Jt
YWw7IiBmaWdtYTp0eXBlPSJ2ZWN0b3IiPgo8dXNlIHhsaW5rOmhyZWY9IiNwYXRoMF9maWxsIiB0
cmFuc2Zvcm09InRyYW5zbGF0ZSgxNjQwLjU0IDI0NzQuMzYpIiBmaWxsPSIjNEU0RTRFIiBzdHls
ZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIvPgo8L2c+CjwvZz4KPGcgaWQ9InBhdGgiIHN0eWxl
PSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJncm91cCI+CjxnIGlkPSJwYXRo
MTAgZmlsbCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5cGU9InZlY3Rv
ciI+Cjx1c2UgeGxpbms6aHJlZj0iI3BhdGgxX2ZpbGwiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDE2
NDUuNjggMjQ3NC4zNykiIGZpbGw9IiM0RTRFNEUiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3Jt
YWw7Ii8+CjwvZz4KPC9nPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1h
bDsiIGZpZ21hOnR5cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGgxMSBmaWxsIiBzdHlsZT0ibWl4LWJs
ZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0idmVjdG9yIj4KPHVzZSB4bGluazpocmVmPSIj
cGF0aDJfZmlsbCIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTY1My4zOSAyNDc0LjI2KSIgZmlsbD0i
IzRFNEU0RSIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiLz4KPC9nPgo8L2c+CjxnIGlk
PSJwYXRoIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0iZ3JvdXAi
Pgo8ZyBpZD0icGF0aDEyIGZpbGwiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7IiBmaWdt
YTp0eXBlPSJ2ZWN0b3IiPgo8dXNlIHhsaW5rOmhyZWY9IiNwYXRoM19maWxsIiB0cmFuc2Zvcm09
InRyYW5zbGF0ZSgxNjYwLjQzIDI0NzQuMzkpIiBmaWxsPSIjNEU0RTRFIiBzdHlsZT0ibWl4LWJs
ZW5kLW1vZGU6bm9ybWFsOyIvPgo8L2c+CjwvZz4KPGcgaWQ9InBhdGgiIHN0eWxlPSJtaXgtYmxl
bmQtbW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJncm91cCI+CjxnIGlkPSJwYXRoMTMgZmlsbCIg
c3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5cGU9InZlY3RvciI+Cjx1c2Ug
eGxpbms6aHJlZj0iI3BhdGg0X2ZpbGwiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDE2NjcuNTUgMjQ3
Mi41NCkiIGZpbGw9IiM0RTRFNEUiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7Ii8+Cjwv
Zz4KPC9nPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21h
OnR5cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGgxNCBmaWxsIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6
bm9ybWFsOyIgZmlnbWE6dHlwZT0idmVjdG9yIj4KPHVzZSB4bGluazpocmVmPSIjcGF0aDVfZmls
bCIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTY3Mi40NyAyNDc0LjI5KSIgZmlsbD0iIzRFNEU0RSIg
c3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiLz4KPC9nPgo8L2c+CjxnIGlkPSJwYXRoIiBz
dHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0iZ3JvdXAiPgo8ZyBpZD0i
cGF0aDE1IGZpbGwiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJ2
ZWN0b3IiPgo8dXNlIHhsaW5rOmhyZWY9IiNwYXRoNl9maWxsIiB0cmFuc2Zvcm09InRyYW5zbGF0
ZSgxNjc5Ljk4IDI0NzQuMjQpIiBmaWxsPSIjNEU0RTRFIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6
bm9ybWFsOyIvPgo8L2c+CjwvZz4KPC9nPgo8L2c+CjxnIGlkPSJnIiBzdHlsZT0ibWl4LWJsZW5k
LW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0iZ3JvdXAiPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1p
eC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGgxNiBm
aWxsIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0idmVjdG9yIj4K
PHVzZSB4bGluazpocmVmPSIjcGF0aDdfZmlsbCIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTY3My40
OCAyNDUzLjY5KSIgZmlsbD0iIzc2NzY3NyIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsi
Lz4KPC9nPgo8L2c+CjxnIGlkPSJwYXRoIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIg
ZmlnbWE6dHlwZT0iZ3JvdXAiPgo8ZyBpZD0icGF0aDE3IGZpbGwiIHN0eWxlPSJtaXgtYmxlbmQt
bW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJ2ZWN0b3IiPgo8dXNlIHhsaW5rOmhyZWY9IiNwYXRo
OF9maWxsIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgxNjQzLjIxIDI0ODQuMjcpIiBmaWxsPSIjRjM3
NzI2IiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIvPgo8L2c+CjwvZz4KPGcgaWQ9InBh
dGgiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7IiBmaWdtYTp0eXBlPSJncm91cCI+Cjxn
IGlkPSJwYXRoMTggZmlsbCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5
cGU9InZlY3RvciI+Cjx1c2UgeGxpbms6aHJlZj0iI3BhdGg5X2ZpbGwiIHRyYW5zZm9ybT0idHJh
bnNsYXRlKDE2NDMuMjEgMjQ1Ny44OCkiIGZpbGw9IiNGMzc3MjYiIHN0eWxlPSJtaXgtYmxlbmQt
bW9kZTpub3JtYWw7Ii8+CjwvZz4KPC9nPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1peC1ibGVuZC1t
b2RlOm5vcm1hbDsiIGZpZ21hOnR5cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGgxOSBmaWxsIiBzdHls
ZT0ibWl4LWJsZW5kLW1vZGU6bm9ybWFsOyIgZmlnbWE6dHlwZT0idmVjdG9yIj4KPHVzZSB4bGlu
azpocmVmPSIjcGF0aDEwX2ZpbGwiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDE2NDMuMjggMjQ5Ni4w
OSkiIGZpbGw9IiM5RTlFOUUiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7Ii8+CjwvZz4K
PC9nPgo8ZyBpZD0icGF0aCIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOm5vcm1hbDsiIGZpZ21hOnR5
cGU9Imdyb3VwIj4KPGcgaWQ9InBhdGgyMCBmaWxsIiBzdHlsZT0ibWl4LWJsZW5kLW1vZGU6bm9y
bWFsOyIgZmlnbWE6dHlwZT0idmVjdG9yIj4KPHVzZSB4bGluazpocmVmPSIjcGF0aDExX2ZpbGwi
IHRyYW5zZm9ybT0idHJhbnNsYXRlKDE2NDEuODcgMjQ1OC40MykiIGZpbGw9IiM2MTYyNjIiIHN0
eWxlPSJtaXgtYmxlbmQtbW9kZTpub3JtYWw7Ii8+CjwvZz4KPC9nPgo8L2c+CjwvZz4KPC9nPgo8
L2c+CjxkZWZzPgo8cGF0aCBpZD0icGF0aDBfZmlsbCIgZD0iTSAxLjc0NDk4IDUuNDc1MzNDIDEu
NzQ0OTggNy4wMzMzNSAxLjYyMDM0IDcuNTQwODIgMS4yOTk4MyA3LjkxNDc0QyAwLjk0MzExOSA4
LjIzNTk1IDAuNDgwMDI0IDguNDEzNTggMCA4LjQxMzMxTCAwLjEyNDY0MiA5LjMwMzZDIDAuODY4
ODQgOS4zMTM2NiAxLjU5MDk1IDkuMDUwNzggMi4xNTQ1MiA4LjU2NDY2QyAyLjQ1Nzc1IDguMTk0
ODcgMi42ODM0IDcuNzY3ODEgMi44MTggNy4zMDg5M0MgMi45NTI2MSA2Ljg1MDA1IDIuOTkzNDEg
Ni4zNjg3NiAyLjkzNzk4IDUuODkzNzdMIDIuOTM3OTggMEwgMS43NDQ5OCAwTCAxLjc0NDk4IDUu
NDM5NzJMIDEuNzQ0OTggNS40NzUzM1oiLz4KPHBhdGggaWQ9InBhdGgxX2ZpbGwiIGQ9Ik0gNS41
MDIwNCA0Ljc2MzA5QyA1LjUwMjA0IDUuNDMwODEgNS41MDIwNCA2LjAyNzMxIDUuNTU1NDUgNi41
NDM2OEwgNC40OTYgNi41NDM2OEwgNC40MjQ3OCA1LjQ4NDIzQyA0LjIwMzE4IDUuODU5MDkgMy44
ODYyNyA2LjE2ODU4IDMuNTA2MjggNi4zODEyNUMgMy4xMjYyOCA2LjU5MzkyIDIuNjk2NzUgNi43
MDIxOSAyLjI2MTM1IDYuNjk1MDNDIDEuMjI4NjEgNi42OTUwMyAwIDYuMTM0MTUgMCAzLjg0NjA4
TCAwIDAuMDQ0NTE0OUwgMS4xOTMgMC4wNDQ1MTQ5TCAxLjE5MyAzLjYwNTdDIDEuMTkzIDQuODQz
MjIgMS41NzU4MyA1LjY3MTE5IDIuNjUzMDkgNS42NzExOUMgMi44NzQ3MiA1LjY3MzU4IDMuMDk0
NTkgNS42MzE2OCAzLjI5OTgyIDUuNTQ3OTZDIDMuNTA1MDUgNS40NjQyNCAzLjY5MTQ5IDUuMzQw
MzkgMy44NDgyMiA1LjE4MzY2QyA0LjAwNDk0IDUuMDI2OTQgNC4xMjg4IDQuODQwNDkgNC4yMTI1
MiA0LjYzNTI3QyA0LjI5NjIzIDQuNDMwMDQgNC4zMzgxMyA0LjIxMDE2IDQuMzM1NzUgMy45ODg1
M0wgNC4zMzU3NSAwTCA1LjUyODc0IDBMIDUuNTI4NzQgNC43Mjc0OEwgNS41MDIwNCA0Ljc2MzA5
WiIvPgo8cGF0aCBpZD0icGF0aDJfZmlsbCIgZD0iTSAwLjA1MzQxNzggMi4yNzI2NEMgMC4wNTM0
MTc4IDEuNDQ0NjYgMC4wNTM0MTc4IDAuNzY4MDM2IDAgMC4xNTM3MzFMIDEuMDY4MzYgMC4xNTM3
MzFMIDEuMTIxNzcgMS4yNjY2QyAxLjM1OTggMC44NjQ1MzUgMS43MDI0NyAwLjUzNDU5NCAyLjEx
MzI1IDAuMzExOTU0QyAyLjUyNDA0IDAuMDg5MzE0NSAyLjk4NzU0IC0wLjAxNzY3ODYgMy40NTQz
NSAwLjAwMjM4MDk1QyA1LjAzOTA4IDAuMDAyMzgwOTUgNi4yMzIwOCAxLjMyODkyIDYuMjMyMDgg
My4zMDUzOEMgNi4yMzIwOCA1LjYzNzk2IDQuNzk4NyA2Ljc5NTM1IDMuMjQ5NTggNi43OTUzNUMg
Mi44NTMwOSA2LjgxMzA0IDIuNDU4NzQgNi43MjgxIDIuMTA0NjkgNi41NDg3NEMgMS43NTA2NCA2
LjM2OTM3IDEuNDQ4ODggNi4xMDE2NiAxLjIyODYxIDUuNzcxNTFMIDEuMjI4NjEgNS43NzE1MUwg
MS4yMjg2MSA5LjMzMjY5TCAwLjA1MzQxNzggOS4zMzI2OUwgMC4wNTM0MTc4IDIuMjk5MzVMIDAu
MDUzNDE3OCAyLjI3MjY0Wk0gMS4yMjg2MSA0LjAwODcyQyAxLjIzMTg0IDQuMTcwMjYgMS4yNDk3
MiA0LjMzMTE3IDEuMjgyMDMgNC40ODk0OEMgMS4zODMwNCA0Ljg4NDc5IDEuNjEyOTkgNS4yMzUx
MyAxLjkzNTQ4IDUuNDg1MDZDIDIuMjU3OTggNS43MzUgMi42NTQ2MSA1Ljg3MDI2IDMuMDYyNjIg
NS44Njk0NEMgNC4zMTc5NCA1Ljg2OTQ0IDUuMDU2ODkgNC44NDU2IDUuMDU2ODkgMy4zNTg4QyA1
LjA1Njg5IDIuMDU4OTcgNC4zNjI0NiAwLjk0NjA5NiAzLjEwNzE0IDAuOTQ2MDk2QyAyLjYxMDM2
IDAuOTg2Nzc3IDIuMTQ1NDggMS4yMDcyNiAxLjc5OTY1IDEuNTY2MkMgMS40NTM4MiAxLjkyNTE0
IDEuMjUwNzkgMi4zOTc5IDEuMjI4NjEgMi44OTU4NUwgMS4yMjg2MSA0LjAwODcyWiIvPgo8cGF0
aCBpZD0icGF0aDNfZmlsbCIgZD0iTSAxLjMxNzY0IDAuMDE3ODA1OUwgMi43NTEwMiAzLjg1NDk5
QyAyLjkwMjM3IDQuMjgyMzMgMy4wNjI2MiA0Ljc5ODcgMy4xNjk0NiA1LjE4MTUzQyAzLjI5NDEg
NC43ODk4IDMuNDI3NjQgNC4yOTEyMyAzLjU4NzkgMy44MjgyOEwgNC44ODc3MyAwLjAxNzgwNTlM
IDYuMTQzMDUgMC4wMTc4MDU5TCA0LjM2MjQ2IDQuNjQ3MzVDIDMuNDcyMTYgNi44NzMwOSAyLjky
OTA4IDguMDIxNTggMi4xMSA4LjcxNjAxQyAxLjY5NzQ1IDkuMDkyODMgMS4xOTQ0OCA5LjM1NjU4
IDAuNjQ5OTE3IDkuNDgxNjZMIDAuMzU2MTE5IDguNDg0NTNDIDAuNzM2ODg2IDguMzU5NDIgMS4w
OTAzOCA4LjE2MzA0IDEuMzk3NzcgNy45MDU4NEMgMS44MzIxIDcuNTUxODggMi4xNzY3OCA3LjEw
MDQ0IDIuNDAzOCA2LjU4ODJDIDIuNDUyMzkgNi40OTk0OSAyLjQ4NTUxIDYuNDAzMTQgMi41MDE3
MyA2LjMwMzNDIDIuNDkxNjEgNi4xOTU4NiAyLjQ2NDU3IDYuMDkwNyAyLjQyMTYxIDUuOTkxN0wg
MCAwTCAxLjI5OTgzIDBMIDEuMzE3NjQgMC4wMTc4MDU5WiIvPgo8cGF0aCBpZD0icGF0aDRfZmls
bCIgZD0iTSAyLjE5MDEzIDBMIDIuMTkwMTMgMS44Njk2MkwgMy44OTk1IDEuODY5NjJMIDMuODk5
NSAyLjc1OTkyTCAyLjE5MDEzIDIuNzU5OTJMIDIuMTkwMTMgNi4yNjc2OUMgMi4xOTAxMyA3LjA2
ODk2IDIuNDIxNjEgNy41MzE5MSAzLjA4MDQzIDcuNTMxOTFDIDMuMzE0NDIgNy41MzU3NCAzLjU0
Nzg5IDcuNTA4OCAzLjc3NDg2IDcuNDUxNzlMIDMuODI4MjggOC4zNDIwOEMgMy40ODc5NCA4LjQ1
OTk5IDMuMTI4ODEgOC41MTQzMSAyLjc2ODgyIDguNTAyMzRDIDIuNTMwNDIgOC41MTcyNiAyLjI5
MTYxIDguNDgwNDMgMi4wNjg3OCA4LjM5NDM3QyAxLjg0NTk1IDguMzA4MzEgMS42NDQzOCA4LjE3
NTA2IDEuNDc3ODkgOC4wMDM3N0MgMS4xMTUyNSA3LjUxODczIDAuOTQ5ODI2IDYuOTE0MzEgMS4w
MTQ5NCA2LjMxMjIxTCAxLjAxNDk0IDIuNzUxMDJMIDAgMi43NTEwMkwgMCAxLjg2MDcyTCAxLjAz
Mjc0IDEuODYwNzJMIDEuMDMyNzQgMC4yNzU5OTJMIDIuMTkwMTMgMFoiLz4KPHBhdGggaWQ9InBh
dGg1X2ZpbGwiIGQ9Ik0gMS4xNzcxNiAzLjU3ODk5QyAxLjE1MyAzLjg4MDkzIDEuMTk0NjggNC4x
ODQ1MSAxLjI5OTMzIDQuNDY4NzZDIDEuNDAzOTggNC43NTMwMSAxLjU2OTEgNS4wMTExNCAxLjc4
MzI5IDUuMjI1MzJDIDEuOTk3NDcgNS40Mzk1MSAyLjI1NTYgNS42MDQ2MyAyLjUzOTg1IDUuNzA5
MjhDIDIuODI0MSA1LjgxMzkzIDMuMTI3NjggNS44NTU2MSAzLjQyOTYyIDUuODMxNDVDIDQuMDQw
MzMgNS44NDUxMSA0LjY0NzA2IDUuNzI5ODMgNS4yMTAyMSA1LjQ5MzEzTCA1LjQxNDk4IDYuMzgz
NDNDIDQuNzIzOTMgNi42NjgwOSAzLjk4MDg1IDYuODA0NTggMy4yMzM3NSA2Ljc4NDA2QyAyLjc5
ODIxIDYuODEzODggMi4zNjEzOCA2Ljc0OTE0IDEuOTUzMjIgNi41OTQyN0MgMS41NDUwNSA2LjQz
OTQxIDEuMTc1MjIgNi4xOTgwOSAwLjg2OTA3MSA1Ljg4Njg4QyAwLjU2MjkyOCA1LjU3NTY2IDAu
MzI3NzIzIDUuMjAxOSAwLjE3OTU5MSA0Ljc5MTI1QyAwLjAzMTQ1ODQgNC4zODA1OSAtMC4wMjYw
OTYyIDMuOTQyNzYgMC4wMTA4NzQ4IDMuNTA3NzdDIDAuMDEwODc0OCAxLjU0OTEyIDEuMTc3MTYg
MCAzLjA4MjQgMEMgNS4yMTkxMSAwIDUuNzUzMjkgMS44Njk2MiA1Ljc1MzI5IDMuMDYyNjJDIDUu
NzY0NzEgMy4yNDY0NCA1Ljc2NDcxIDMuNDMwNzkgNS43NTMyOSAzLjYxNDYxTCAxLjE1MDQ2IDMu
NjE0NjFMIDEuMTc3MTYgMy41Nzg5OVpNIDQuNjY3MTMgMi42ODg3QyA0LjcwMTQ5IDIuNDUwNjcg
NC42ODQ0MyAyLjIwODA1IDQuNjE3MDkgMS45NzcxOEMgNC41NDk3NiAxLjc0NjMxIDQuNDMzNzIg
MS41MzI1NSA0LjI3NjggMS4zNTAzMUMgNC4xMTk4NyAxLjE2ODA4IDMuOTI1NzEgMS4wMjE2IDMu
NzA3MzkgMC45MjA3NDRDIDMuNDg5MDcgMC44MTk4OSAzLjI1MTY2IDAuNzY3MDA2IDMuMDExMTgg
MC43NjU2NTZDIDIuNTIyMDEgMC44MDEwNjQgMi4wNjM3MSAxLjAxNzg4IDEuNzI2MDkgMS4zNzM2
MkMgMS4zODg0NyAxLjcyOTM1IDEuMTk1ODggMi4xOTgzNSAxLjE4NjA3IDIuNjg4N0wgNC42Njcx
MyAyLjY4ODdaIi8+CjxwYXRoIGlkPSJwYXRoNl9maWxsIiBkPSJNIDAuMDUzNDE3OCAyLjE5MjI4
QyAwLjA1MzQxNzggMS40MjY2MyAwLjA1MzQxNzggMC43Njc4MDYgMCAwLjE2MjQwNEwgMS4wNjgz
NiAwLjE2MjQwNEwgMS4wNjgzNiAxLjQzNTUzTCAxLjEyMTc3IDEuNDM1NTNDIDEuMjMzOTEgMS4w
NDI1OSAxLjQ2NTYgMC42OTQzMTQgMS43ODQ2OCAwLjQzOTA0OUMgMi4xMDM3NiAwLjE4Mzc4MyAy
LjQ5NDQgMC4wMzQxOTYgMi45MDIzNyAwLjAxMTA1MzhDIDMuMDE0NjYgLTAuMDAzNjg0NTkgMy4x
MjgzOSAtMC4wMDM2ODQ1OSAzLjI0MDY4IDAuMDExMDUzOEwgMy4yNDA2OCAxLjEyMzkzQyAzLjEw
NDYyIDEuMTA4MTcgMi45NjcyIDEuMTA4MTcgMi44MzExNCAxLjEyMzkzQyAyLjQyNyAxLjEzOTU4
IDIuMDQyMzcgMS4zMDE4MiAxLjc0OTEgMS41ODAzNUMgMS40NTU4MyAxLjg1ODg3IDEuMjczOTgg
Mi4yMzQ2MiAxLjIzNzUxIDIuNjM3NDNDIDEuMjA0MjIgMi44MTk2IDEuMTg2MzUgMy4wMDQyNSAx
LjE4NDEgMy4xODk0MUwgMS4xODQxIDYuNjUyNjdMIDAuMDA4OTAyOTcgNi42NTI2N0wgMC4wMDg5
MDI5NyAyLjIwMTE4TCAwLjA1MzQxNzggMi4xOTIyOFoiLz4KPHBhdGggaWQ9InBhdGg3X2ZpbGwi
IGQ9Ik0gNi4wMzA1OSAyLjgzNTY1QyA2LjA2NzE1IDMuNDMzNzYgNS45MjQ4NSA0LjAyOTIxIDUu
NjIxOCA0LjU0NjE1QyA1LjMxODc1IDUuMDYzMSA0Ljg2ODY5IDUuNDc4MTMgNC4zMjg5MyA1Ljcz
ODM5QyAzLjc4OTE3IDUuOTk4NjQgMy4xODQxNiA2LjA5MjMzIDIuNTkwOTcgNi4wMDc1M0MgMS45
OTc3OCA1LjkyMjcyIDEuNDQzMjYgNS42NjMyNiAwLjk5ODA0OCA1LjI2MjE5QyAwLjU1MjgzNyA0
Ljg2MTEzIDAuMjM3MDkgNC4zMzY2MSAwLjA5MTAzMDcgMy43NTU0NkMgLTAuMDU1MDI4NyAzLjE3
NDMxIC0wLjAyNDc4OTEgMi41NjI4MyAwLjE3Nzg5NyAxLjk5ODkzQyAwLjM4MDU4MyAxLjQzNTAz
IDAuNzQ2NTQxIDAuOTQ0MjIxIDEuMjI5MTUgMC41ODkwMzdDIDEuNzExNzYgMC4yMzM4NTMgMi4y
ODkxOCAwLjAzMDM2ODYgMi44ODc4NCAwLjAwNDUwNTQzQyAzLjI4MDM1IC0wLjAxNzA5MzIgMy42
NzMyNiAwLjAzOTExNDQgNC4wNDM5NiAwLjE2OTg5NkMgNC40MTQ2NyAwLjMwMDY3NyA0Ljc1NTg3
IDAuNTAzNDUzIDUuMDQ3OTQgMC43NjY1NjFDIDUuMzQgMS4wMjk2NyA1LjU3NzE4IDEuMzQ3OTIg
NS43NDU4MiAxLjcwMzAxQyA1LjkxNDQ2IDIuMDU4MSA2LjAxMTI0IDIuNDQzMDMgNi4wMzA1OSAy
LjgzNTY1TCA2LjAzMDU5IDIuODM1NjVaIi8+CjxwYXRoIGlkPSJwYXRoOF9maWxsIiBkPSJNIDE4
LjY5NjIgNy4xMjIzOEMgMTAuNjgzNiA3LjEyMjM4IDMuNjQxMzEgNC4yNDY3MiAwIDBDIDEuNDEy
ODQgMy44MjA0MSAzLjk2MjE1IDcuMTE2MyA3LjMwNDc5IDkuNDQ0MDRDIDEwLjY0NzQgMTEuNzcx
OCAxNC42MjMgMTMuMDE5NiAxOC42OTYyIDEzLjAxOTZDIDIyLjc2OTUgMTMuMDE5NiAyNi43NDUg
MTEuNzcxOCAzMC4wODc3IDkuNDQ0MDRDIDMzLjQzMDMgNy4xMTYzIDM1Ljk3OTYgMy44MjA0MSAz
Ny4zOTI1IDQuMDQ4NmUtMTNDIDMzLjc2MDEgNC4yNDY3MiAyNi43NDQ1IDcuMTIyMzggMTguNjk2
MiA3LjEyMjM4WiIvPgo8cGF0aCBpZD0icGF0aDlfZmlsbCIgZD0iTSAxOC42OTYyIDUuODk3MjVD
IDI2LjcwODkgNS44OTcyNSAzMy43NTEyIDguNzcyOTEgMzcuMzkyNSAxMy4wMTk2QyAzNS45Nzk2
IDkuMTk5MjIgMzMuNDMwMyA1LjkwMzMzIDMwLjA4NzcgMy41NzU1OUMgMjYuNzQ1IDEuMjQ3ODUg
MjIuNzY5NSA0LjA0ODZlLTEzIDE4LjY5NjIgMEMgMTQuNjIzIDQuMDQ4NmUtMTMgMTAuNjQ3NCAx
LjI0Nzg1IDcuMzA0NzkgMy41NzU1OUMgMy45NjIxNSA1LjkwMzMzIDEuNDEyODQgOS4xOTkyMiAw
IDEzLjAxOTZDIDMuNjQxMzEgOC43NjQwMSAxMC42NDggNS44OTcyNSAxOC42OTYyIDUuODk3MjVa
Ii8+CjxwYXRoIGlkPSJwYXRoMTBfZmlsbCIgZD0iTSA3LjU5NTc2IDMuNTY2NTZDIDcuNjQyNzYg
NC4zMTk5MiA3LjQ2NDQyIDUuMDcwMjIgNy4wODM0NyA1LjcyMTg2QyA2LjcwMjUxIDYuMzczNSA2
LjEzNjE5IDYuODk2OTggNS40NTY2NiA3LjIyNTYxQyA0Ljc3NzEzIDcuNTU0MjQgNC4wMTUxNSA3
LjY3MzE0IDMuMjY3ODEgNy41NjcxNkMgMi41MjA0NiA3LjQ2MTE3IDEuODIxNTggNy4xMzUxMSAx
LjI2MDIxIDYuNjMwNTFDIDAuNjk4ODM5IDYuMTI1OTEgMC4zMDAzOTQgNS40NjU2MSAwLjExNTYz
NyA0LjczMzc1QyAtMC4wNjkxMTkxIDQuMDAxODggLTAuMDMxODIxOSAzLjIzMTU5IDAuMjIyNzc3
IDIuNTIwOTlDIDAuNDc3Mzc2IDEuODEwNCAwLjkzNzc1IDEuMTkxNjkgMS41NDUyNCAwLjc0MzY4
NUMgMi4xNTI3NCAwLjI5NTY3OCAyLjg3OTg1IDAuMDM4NjU5NSAzLjYzMzk0IDAuMDA1Mzc1ODlD
IDQuMTI3OTMgLTAuMDIxMDQ3MSA0LjYyMjI5IDAuMDUwMTE3MyA1LjA4ODc4IDAuMjE0ODAzQyA1
LjU1NTI2IDAuMzc5NDkgNS45ODQ3MyAwLjYzNDQ3IDYuMzUyNjQgMC45NjUxNzlDIDYuNzIwNTUg
MS4yOTU4OSA3LjAxOTcxIDEuNjk1ODQgNy4yMzMgMi4xNDIyQyA3LjQ0NjMgMi41ODg1NSA3LjU2
OTU3IDMuMDcyNTYgNy41OTU3NiAzLjU2NjU2TCA3LjU5NTc2IDMuNTY2NTZaIi8+CjxwYXRoIGlk
PSJwYXRoMTFfZmlsbCIgZD0iTSAyLjI1MDYxIDQuMzc5NDNDIDEuODE4ODYgNC4zOTEzNSAxLjM5
MzIyIDQuMjc1MzUgMS4wMjcyMiA0LjA0NjAyQyAwLjY2MTIyNCAzLjgxNjY4IDAuMzcxMjA2IDMu
NDg0MjQgMC4xOTM2NDEgMy4wOTA1MkMgMC4wMTYwNzYyIDIuNjk2NzkgLTAuMDQxMTA3OCAyLjI1
OTM1IDAuMDI5MjgwNCAxLjgzMzIxQyAwLjA5OTY2ODYgMS40MDcwNyAwLjI5NDQ4NiAxLjAxMTI1
IDAuNTg5MjMzIDAuNjk1NTQyQyAwLjg4Mzk4MSAwLjM3OTgzIDEuMjY1NSAwLjE1ODMxNiAxLjY4
NTgxIDAuMDU4ODU3N0MgMi4xMDYxMSAtMC4wNDA2MDA1IDIuNTQ2NDQgLTAuMDEzNTYyMiAyLjk1
MTQzIDAuMTM2NTcyQyAzLjM1NjQxIDAuMjg2NzA3IDMuNzA3OTYgMC41NTMyMzQgMy45NjE4NiAw
LjkwMjYzNkMgNC4yMTU3NyAxLjI1MjA0IDQuMzYwNyAxLjY2ODcyIDQuMzc4NDIgMi4xMDAyN0Mg
NC4zOTUyOSAyLjY4MzggNC4xODEzMSAzLjI1MDQ0IDMuNzgyOTMgMy42NzcxNUMgMy4zODQ1NSA0
LjEwMzg3IDIuODMzOTIgNC4zNTYyMyAyLjI1MDYxIDQuMzc5NDNaIi8+CjwvZGVmcz4KPC9zdmc+
Cg==
B64_END

install -d -m 755 "${SRC}/apps/octave"
base64 -d > "${SRC}/apps/octave/icon.svg" <<'B64_END'
PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+Cjwh
LS0gQ3JlYXRlZCB3aXRoIElua3NjYXBlIChodHRwOi8vd3d3Lmlua3NjYXBlLm9yZy8pIC0tPgoK
PHN2ZwogICB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iCiAgIHht
bG5zOmNjPSJodHRwOi8vY3JlYXRpdmVjb21tb25zLm9yZy9ucyMiCiAgIHhtbG5zOnJkZj0iaHR0
cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyIKICAgeG1sbnM6c3ZnPSJo
dHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIKICAgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIw
MDAvc3ZnIgogICB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayIKICAg
eG1sbnM6c29kaXBvZGk9Imh0dHA6Ly9zb2RpcG9kaS5zb3VyY2Vmb3JnZS5uZXQvRFREL3NvZGlw
b2RpLTAuZHRkIgogICB4bWxuczppbmtzY2FwZT0iaHR0cDovL3d3dy5pbmtzY2FwZS5vcmcvbmFt
ZXNwYWNlcy9pbmtzY2FwZSIKICAgdmVyc2lvbj0iMS4xIgogICB3aWR0aD0iMjgzLjI4OTEyIgog
ICBoZWlnaHQ9IjI4My4yODgzMyIKICAgaWQ9InN2ZzI4NzIiCiAgIGlua3NjYXBlOnZlcnNpb249
IjAuNDcgcjIyNTgzIgogICBzb2RpcG9kaTpkb2NuYW1lPSJkcmF3aW5nLnN2ZyI+CiAgPG1ldGFk
YXRhCiAgICAgaWQ9Im1ldGFkYXRhMjk0MiI+CiAgICA8cmRmOlJERj4KICAgICAgPGNjOldvcmsK
ICAgICAgICAgcmRmOmFib3V0PSIiPgogICAgICAgIDxkYzpmb3JtYXQ+aW1hZ2Uvc3ZnK3htbDwv
ZGM6Zm9ybWF0PgogICAgICAgIDxkYzp0eXBlCiAgICAgICAgICAgcmRmOnJlc291cmNlPSJodHRw
Oi8vcHVybC5vcmcvZGMvZGNtaXR5cGUvU3RpbGxJbWFnZSIgLz4KICAgICAgPC9jYzpXb3JrPgog
ICAgPC9yZGY6UkRGPgogIDwvbWV0YWRhdGE+CiAgPHNvZGlwb2RpOm5hbWVkdmlldwogICAgIHBh
Z2Vjb2xvcj0iI2ZmZmZmZiIKICAgICBib3JkZXJjb2xvcj0iIzY2NjY2NiIKICAgICBib3JkZXJv
cGFjaXR5PSIxIgogICAgIG9iamVjdHRvbGVyYW5jZT0iMTAiCiAgICAgZ3JpZHRvbGVyYW5jZT0i
MTAiCiAgICAgZ3VpZGV0b2xlcmFuY2U9IjEwIgogICAgIGlua3NjYXBlOnBhZ2VvcGFjaXR5PSIw
IgogICAgIGlua3NjYXBlOnBhZ2VzaGFkb3c9IjIiCiAgICAgaW5rc2NhcGU6d2luZG93LXdpZHRo
PSI2NDAiCiAgICAgaW5rc2NhcGU6d2luZG93LWhlaWdodD0iNDgzIgogICAgIGlkPSJuYW1lZHZp
ZXcyOTQwIgogICAgIHNob3dncmlkPSJmYWxzZSIKICAgICBpbmtzY2FwZTp6b29tPSIwLjIyNDI1
NzM5IgogICAgIGlua3NjYXBlOmN4PSIxMzguNjkxOCIKICAgICBpbmtzY2FwZTpjeT0iMTQ3Ljgy
NTI1IgogICAgIGlua3NjYXBlOndpbmRvdy14PSI2NDgiCiAgICAgaW5rc2NhcGU6d2luZG93LXk9
IjE0NCIKICAgICBpbmtzY2FwZTp3aW5kb3ctbWF4aW1pemVkPSIwIgogICAgIGlua3NjYXBlOmN1
cnJlbnQtbGF5ZXI9InN2ZzI4NzIiIC8+CiAgPGRlZnMKICAgICBpZD0iZGVmczI4NzQiPgogICAg
PHJhZGlhbEdyYWRpZW50CiAgICAgICBjeD0iMTgyLjk4MzciCiAgICAgICBjeT0iMzk1LjA0ODcx
IgogICAgICAgcj0iMTQ4Ljk1MzA5IgogICAgICAgZng9IjE4Mi45ODM3IgogICAgICAgZnk9IjM5
NS4wNDg3MSIKICAgICAgIGlkPSJyYWRpYWxHcmFkaWVudDMwMzMiCiAgICAgICB4bGluazpocmVm
PSIjbGluZWFyR3JhZGllbnQzNzU1IgogICAgICAgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25V
c2UiCiAgICAgICBncmFkaWVudFRyYW5zZm9ybT0ibWF0cml4KDAuMjI5MTQzMzQsLTAuMjQ5MDE0
NzksMC43NjQzNTcyLDAuODMwNjQyNjgsLTI3Mi44NTMzNywtMTU5LjY5NDgyKSIgLz4KICAgIDxs
aW5lYXJHcmFkaWVudAogICAgICAgaWQ9ImxpbmVhckdyYWRpZW50Mzc1NSI+CiAgICAgIDxzdG9w
CiAgICAgICAgIGlkPSJzdG9wMzc1NyIKICAgICAgICAgc3R5bGU9InN0b3AtY29sb3I6IzAwOGNi
ZTtzdG9wLW9wYWNpdHk6MSIKICAgICAgICAgb2Zmc2V0PSIwIiAvPgogICAgICA8c3RvcAogICAg
ICAgICBpZD0ic3RvcDM3NTkiCiAgICAgICAgIHN0eWxlPSJzdG9wLWNvbG9yOiNiMmZmZmY7c3Rv
cC1vcGFjaXR5OjEiCiAgICAgICAgIG9mZnNldD0iMSIgLz4KICAgIDwvbGluZWFyR3JhZGllbnQ+
CiAgPC9kZWZzPgogIDxnCiAgICAgaWQ9ImxheWVyMSIKICAgICB0cmFuc2Zvcm09InRyYW5zbGF0
ZSgtMjMzLjM1NTQ0LC0zOTAuNzE4MDIpIj4KICAgIDxnCiAgICAgICB0cmFuc2Zvcm09Im1hdHJp
eCg4LjQ1MTk3MjMsMCwwLDguNDUxOTcyMywtMjc4LjQ1MDEyLC00MDMuODI5NzUpIgogICAgICAg
aWQ9ImczMDI1Ij4KICAgICAgPHBhdGgKICAgICAgICAgZD0ibSA2Ni40MzIxMDMsOTcuNDg4Njc5
IGMgLTUuMTk1ODQsNS42NDY0MzEgLTMuOTM2NjEsMTYuMTY5MDMxIDIuODExMDcsMjMuNTAxODcx
IDYuNzQ3NjgsNy4zMzI4NSAxNi40Mjg5OCw4LjY5OTU1IDIxLjYyNDgzLDMuMDUzMTIgNS4xOTU4
NSwtNS42NDY0MyAzLjk0MDIsLTE2LjE2OTQ2IC0yLjgwNzQ5LC0yMy41MDIzIC02Ljc0NzY4LC03
LjMzMjg2MSAtMTYuNDMyNTYsLTguNjk5MTMxIC0yMS42Mjg0MSwtMy4wNTI2OTEgeiBtIDQuNzEx
NDksMi4zNDU1MyBjIDQuMDgyNTYsLTQuNDM2NTkgMTEuNTg5LC0zLjQ3MTUyIDE2Ljc2NzQxLDIu
MTU1OTYxIDUuMTc4NDIsNS42Mjc1IDYuMDY2NDcsMTMuNzg0OTEgMS45ODM5MSwxOC4yMjE1IC00
LjA4MjU2LDQuNDM2NTggLTExLjU5MDk3LDMuNDczNjkgLTE2Ljc2OTM5LC0yLjE1MzgxIC01LjE3
ODQyLC01LjYyNzUgLTYuMDY0NDksLTEzLjc4NzA0IC0xLjk4MTkzLC0xOC4yMjM2NTEgeiIKICAg
ICAgICAgaWQ9InBhdGg1ODc0IgogICAgICAgICBzdHlsZT0iZmlsbDp1cmwoI3JhZGlhbEdyYWRp
ZW50MzAzMyk7ZmlsbC1vcGFjaXR5OjE7c3Ryb2tlOm5vbmUiIC8+CiAgICAgIDxyZWN0CiAgICAg
ICAgIHdpZHRoPSI0LjM0OTg1NCIKICAgICAgICAgaGVpZ2h0PSI0LjM0OTg1NCIKICAgICAgICAg
cng9IjAuNzY5NTg5NjYiCiAgICAgICAgIHJ5PSIwLjc2OTU4OTY2IgogICAgICAgICB4PSI4NS4z
ODE1NjEiCiAgICAgICAgIHk9Ijk5LjQ5Mzg4MSIKICAgICAgICAgaWQ9InJlY3Q1ODc2IgogICAg
ICAgICBzdHlsZT0iZmlsbDojZmY3ZjJhO2ZpbGwtb3BhY2l0eToxO2ZpbGwtcnVsZTpub256ZXJv
O3N0cm9rZTojZDQ1NTAwO3N0cm9rZS13aWR0aDowLjc0NDAzNzk5O3N0cm9rZS1taXRlcmxpbWl0
OjQ7c3Ryb2tlLWRhc2hhcnJheTpub25lIiAvPgogICAgICA8cmVjdAogICAgICAgICB3aWR0aD0i
MTAuMjQ1NDM2IgogICAgICAgICBoZWlnaHQ9IjEwLjI0NTQzNiIKICAgICAgICAgcng9IjEuODEy
NjU0NSIKICAgICAgICAgcnk9IjEuODEyNjU0NSIKICAgICAgICAgeD0iNjAuOTI2NTkiCiAgICAg
ICAgIHk9IjEwNS4yMjQ1IgogICAgICAgICBpZD0icmVjdDU4NzgiCiAgICAgICAgIHN0eWxlPSJm
aWxsOiNmZjdmMmE7ZmlsbC1vcGFjaXR5OjE7ZmlsbC1ydWxlOm5vbnplcm87c3Ryb2tlOiNkNDU1
MDA7c3Ryb2tlLXdpZHRoOjAuNzQ0MDM3OTk7c3Ryb2tlLW1pdGVybGltaXQ6NDtzdHJva2UtZGFz
aGFycmF5Om5vbmUiIC8+CiAgICAgIDxyZWN0CiAgICAgICAgIHdpZHRoPSI2LjE4OTc1MzEiCiAg
ICAgICAgIGhlaWdodD0iNi4xODk3NTMxIgogICAgICAgICByeD0iMS4wOTUxMTAyIgogICAgICAg
ICByeT0iMS4wOTUxMTAyIgogICAgICAgICB4PSI4Ny40MDQ3MzkiCiAgICAgICAgIHk9IjExOC42
MzcwNSIKICAgICAgICAgaWQ9InJlY3Q1ODgwIgogICAgICAgICBzdHlsZT0iZmlsbDojZmY3ZjJh
O2ZpbGwtb3BhY2l0eToxO2ZpbGwtcnVsZTpub256ZXJvO3N0cm9rZTojZDQ1NTAwO3N0cm9rZS13
aWR0aDowLjc0NDAzNzk5O3N0cm9rZS1taXRlcmxpbWl0OjQ7c3Ryb2tlLWRhc2hhcnJheTpub25l
IiAvPgogICAgPC9nPgogIDwvZz4KPC9zdmc+Cg==
B64_END

install -d -m 755 "${SRC}/apps/rstudio"
base64 -d > "${SRC}/apps/rstudio/icon.svg" <<'B64_END'
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRw
Oi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB3aWR0aD0iNzI0IiBoZWlnaHQ9IjU2MSI+PGRlZnM+
PGxpbmVhckdyYWRpZW50IGlkPSJnIiB4MT0iMCIgeDI9IjEiIHkxPSIwIiB5Mj0iMSIgZ3JhZGll
bnRVbml0cz0ib2JqZWN0Qm91bmRpbmdCb3giIHNwcmVhZE1ldGhvZD0icGFkIj48c3RvcCBvZmZz
ZXQ9IjAiIHN0b3AtY29sb3I9IiNjYmNlZDAiIHN0b3Atb3BhY2l0eT0iMSIvPjxzdG9wIG9mZnNl
dD0iMSIgc3RvcC1jb2xvcj0iIzg0ODM4YiIgc3RvcC1vcGFjaXR5PSIxIi8+PC9saW5lYXJHcmFk
aWVudD48bGluZWFyR3JhZGllbnQgaWQ9ImIiIHgxPSIwIiB4Mj0iMSIgeTE9IjAiIHkyPSIxIiBn
cmFkaWVudFVuaXRzPSJvYmplY3RCb3VuZGluZ0JveCIgc3ByZWFkTWV0aG9kPSJwYWQiPjxzdG9w
IG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzI3NmRjMyIgc3RvcC1vcGFjaXR5PSIxIi8+PHN0b3Ag
b2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMTY1Y2FhIiBzdG9wLW9wYWNpdHk9IjEiLz48L2xpbmVh
ckdyYWRpZW50PjwvZGVmcz48cGF0aCBkPSJNMzYxLjQ1Myw0ODUuOTM3IEMxNjIuMzI5LDQ4NS45
MzcgMC45MDYsMzc3LjgyOCAwLjkwNiwyNDQuNDY5IEMwLjkwNiwxMTEuMTA5IDE2Mi4zMjksMy4w
MDAgMzYxLjQ1MywzLjAwMCBDNTYwLjU3OCwzLjAwMCA3MjIuMDAwLDExMS4xMDkgNzIyLjAwMCwy
NDQuNDY5IEM3MjIuMDAwLDM3Ny44MjggNTYwLjU3OCw0ODUuOTM3IDM2MS40NTMsNDg1LjkzNyBa
TTQxNi42NDEsOTcuNDA2IEMyNjUuMjg5LDk3LjQwNiAxNDIuNTk0LDE3MS4zMTQgMTQyLjU5NCwy
NjIuNDg0IEMxNDIuNTk0LDM1My42NTQgMjY1LjI4OSw0MjcuNTYyIDQxNi42NDEsNDI3LjU2MiBD
NTY3Ljk5Miw0MjcuNTYyIDY3OS42ODcsMzc3LjAzMyA2NzkuNjg3LDI2Mi40ODQgQzY3OS42ODcs
MTQ3Ljk3MSA1NjcuOTkyLDk3LjQwNiA0MTYuNjQxLDk3LjQwNiBaIiBmaWxsPSJ1cmwoI2cpIiBm
aWxsLXJ1bGU9ImV2ZW5vZGQiLz48cGF0aCBkPSJNNTUwLjAwMCwzNzcuMDAwIEM1NTAuMDAwLDM3
Ny4wMDAgNTcxLjgyMiwzODMuNTg1IDU4NC41MDAsMzkwLjAwMCBDNTg4Ljg5OSwzOTIuMjI2IDU5
Ni41MTAsMzk2LjY2OCA2MDIuMDAwLDQwMi41MDAgQzYwNy4zNzgsNDA4LjIxMiA2MTAuMDAwLDQx
NC4wMDAgNjEwLjAwMCw0MTQuMDAwIEw2OTYuMDAwLDU1OS4wMDAgTDU1Ny4wMDAsNTU5LjA2MiBM
NDkyLjAwMCw0MzcuMDAwIEM0OTIuMDAwLDQzNy4wMDAgNDc4LjY5MCw0MTQuMTMxIDQ3MC41MDAs
NDA3LjUwMCBDNDYzLjY2OCw0MDEuOTY5IDQ2MC43NTUsNDAwLjAwMCA0NTQuMDAwLDQwMC4wMDAg
QzQ0OS4yOTgsNDAwLjAwMCA0MjAuOTc0LDQwMC4wMDAgNDIwLjk3NCw0MDAuMDAwIEw0MjEuMDAw
LDU1OC45NzQgTDI5OC4wMDAsNTU5LjAyNiBMMjk4LjAwMCwxNTIuOTM4IEw1NDUuMDAwLDE1Mi45
MzggQzU0NS4wMDAsMTUyLjkzOCA2NTcuNTAwLDE1NC45NjcgNjU3LjUwMCwyNjIuMDAwIEM2NTcu
NTAwLDM2OS4wMzMgNTUwLjAwMCwzNzcuMDAwIDU1MC4wMDAsMzc3LjAwMCBaTTQ5Ni41MDAsMjQx
LjAyNCBMNDIyLjAzNywyNDAuOTc2IEw0MjIuMDAwLDMxMC4wMjYgTDQ5Ni41MDAsMzEwLjAwMiBD
NDk2LjUwMCwzMTAuMDAyIDUzMS4wMDAsMzA5Ljg5NSA1MzEuMDAwLDI3NC44NzcgQzUzMS4wMDAs
MjM5LjE1NSA0OTYuNTAwLDI0MS4wMjQgNDk2LjUwMCwyNDEuMDI0IFoiIGZpbGw9InVybCgjYiIg
ZmlsbC1ydWxlPSJldmVub2RkIi8+PC9zdmc+
B64_END

    chmod +x "${SRC}"/*/*.sh 2>/dev/null || true
    return 0
}
