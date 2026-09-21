#!/usr/bin/env bash
# Open OnDemand appliance for OpenNebula, one image and three roles.
#
# Open OnDemand gives HPC users a browser interface to a cluster. This appliance carries the
# three roles of the deployment, and ONEAPP_ROLE picks the role at boot. The OneFlow service
# template sets that variable per role:
#
#   portal   the web portal, with its own LDAP directory and Dex authentication
#   storage  the shared home over NFS and the site cache for the EESSI catalogue
#   worker   a compute VM that runs user sessions as jobs of the Slurm cluster of the service
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
    # The role and the values the service template derives per role.
    'ONEAPP_ROLE'                        'configure' 'Role this VM plays, portal, storage or worker'                'M|list|portal,storage,worker'
    'ONEAPP_NFS_HOST'                    'configure' 'Address of the storage role, for the shared home'             'O|text'
    'ONEAPP_LDAP_HOST'                   'configure' 'Address of the portal role, where the directory lives'        'O|text'
    'ONEAPP_CVMFS_PROXY'                 'configure' 'URL of the site cache for the software catalogue'             'O|text'
    'ONEAPP_NFS_ADMIN_IPS'               'configure' 'Addresses allowed to act as root on the shared home'          'O|text'
    'ONEAPP_NFS_NET'                     'configure' 'Network allowed to mount the shared home'                     'O|text'
    'ONEAPP_SQUID_NETS'                  'configure' 'Networks allowed to use the site cache'                       'O|text'
    # The service inputs, one tab of the instantiate wizard per prefix.
    'ONEAPP_PORTAL_HOST_NAME'            'configure' 'Public host name of the portal, empty to use its address'     'O|text'
    'ONEAPP_PORTAL_LETSENCRYPT_ENABLED'  'configure' "Request a Let's Encrypt certificate for the host name"        'O|boolean'
    'ONEAPP_PORTAL_CERTIFICATE_ENABLED'  'configure' 'Use a certificate of your own'                                'O|boolean'
    'ONEAPP_PORTAL_CERTIFICATE_CHAIN'    'configure' 'PEM certificate chain'                                        'O|text64'
    'ONEAPP_PORTAL_CERTIFICATE_KEY'      'configure' 'PEM private key'                                              'O|text64'
    'ONEAPP_AUTH_LOCAL_USERS'            'configure' 'Initial users, user:password separated by spaces, uid optional' 'O|text'
    'ONEAPP_AUTH_OIDC_ENABLED'           'configure' 'Sign in through an OpenID Connect provider as well'           'O|boolean'
    'ONEAPP_AUTH_OIDC_ISSUER'            'configure' 'Issuer URL of the provider'                                   'O|text'
    'ONEAPP_AUTH_OIDC_CLIENT_ID'         'configure' 'Client id registered at the provider'                         'O|text'
    'ONEAPP_AUTH_OIDC_CLIENT_SECRET'     'configure' 'Client secret registered at the provider'                     'O|password'
    'ONEAPP_AUTH_OIDC_NAME'              'configure' 'Name of the provider on the login page'                       'O|text'
    'ONEAPP_HOME_NFS_ENABLED'            'configure' 'Use an NFS server of your own instead of the storage role'    'O|boolean'
    'ONEAPP_HOME_NFS_SERVER'             'configure' 'Address of the NFS server'                                    'O|text'
    'ONEAPP_HOME_NFS_EXPORT'             'configure' 'Path of the home export on that server'                                   'O|text'
    'ONEAPP_SOFTWARE_PROXY_ENABLED'      'configure' 'Use a CernVM-FS proxy of your own instead of the storage role' 'O|boolean'
    'ONEAPP_SOFTWARE_PROXY_URL'          'configure' 'URL of that proxy'                                             'O|text'
    # Advanced attributes, set in the vm_template_contents of a role or in the CONTEXT of a
    # standalone VM, never asked by the wizard.
    'ONEAPP_SLURM_CONTROLLER_ENABLED'    'configure' 'Submit batch jobs to a second Slurm cluster of the site as well' 'O|boolean'
    'ONEAPP_SLURM_CONTROLLER_HOST'       'configure' 'Address of the controller of that cluster'                    'O|text'
    'ONEAPP_WORKER_IDLE_SECONDS'         'configure' 'Seconds the oldest worker stays empty before it drains and the pool shrinks' 'O|number'
    'ONEAPP_WORKER_DRAIN_SECONDS'        'configure' 'Seconds a drained worker waits for its removal before it returns to service' 'O|number'
    'ONEAPP_POOL_RANGE'                  'configure' 'Worker address range, first-last, for a portal outside a OneFlow service' 'O|text'
    'ONEAPP_SLURM_STATE_EXPORT'          'configure' 'Export of the storage role that keeps the Slurm controller state' 'O|text'
    'ONEAPP_SLURM_DEF_MEM_PER_CPU'       'configure' 'Memory in MB a job gets per core when it asks for none'      'O|number'
    'ONEAPP_SLURM_TITLE'                 'configure' 'Name of the external Slurm cluster in the portal'             'O|text'
    # Two more values the scripts read at boot. The image template declares no reference for
    # them, so they reach a VM through its CONTEXT and not through a top-level attribute in
    # the vm_template_contents of a role.
    'ONEAPP_OOD_SSL_EMAIL'               'configure' "Contact address for Let's Encrypt"                            'O|text'
    'ONEAPP_EESSI_VERSION'               'configure' 'EESSI release to load in sessions'                            'O|text'
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
  worker   a compute VM that runs user sessions as jobs of the Slurm cluster of the service

Deploy it with the Open OnDemand Service appliance, which wires the three roles together with
OneFlow and grows the pool of compute VMs with the number of open sessions.

Scientific software comes from EESSI over CernVM-FS, cached by the storage role, so a notebook
loads the same modules a user would find at a EuroHPC centre and the image does not age with
the software it serves. Six interactive applications ship with it, JupyterLab, Octave, a C++
notebook, RStudio, VS Code and an Xfce desktop.

After deployment the portal answers on https://<ONEAPP_PORTAL_HOST_NAME>/ and the initial
users are the ones given in ONEAPP_AUTH_LOCAL_USERS. Adding a user later is one entry in the
directory on the portal role, and their home and their sessions follow from it.

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
portal      = $(cat /etc/one-ondemand/portal-url 2>/dev/null || printf 'https://%s/\n' "${ONEAPP_PORTAL_HOST_NAME:-$(hostname -I | awk '{print $1}')}")
users       = ${ONEAPP_AUTH_LOCAL_USERS:-demo1:demo1pass}
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
    # The one-apps wrapper sets umask 0077, which would leave every file root only.
    umask 022
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
# The accounting database first, while MariaDB still answers.
mysql -e "DROP DATABASE IF EXISTS slurm_acct_db" >/dev/null 2>&1 || true
for unit in apache2 ondemand-dex slapd nfs-server nfs-kernel-server squid sssd ood-slurm-elastic \
            munge slurmd slurmctld slurmdbd mariadb ood-slurm-reconcile.timer ood-slurm-backup.timer \
            ood-export-refresh.timer; do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
ok "no role service is left started or enabled"

msg "removing the configuration of this deployment"
# Mounts first, an image with /home mounted over NFS does not boot if the server is not there.
umount -l /home 2>/dev/null || true
umount -l /cvmfs/software.eessi.io 2>/dev/null || true
umount -l /var/lib/one-ondemand/slurm 2>/dev/null || true
sed -i '\#:/export/home /home nfs4 #d;\# /cvmfs/software.eessi.io cvmfs #d;\# /var/lib/one-ondemand/slurm nfs4 #d' /etc/fstab
rm -f /etc/cvmfs/default.local
rm -rf /var/lib/cvmfs/shared /var/lib/cvmfs/software.eessi.io
ok "fstab, CernVM-FS proxy and cache cleaned"

# Worker role, identity against the LDAP of the portal.
systemctl stop sssd >/dev/null 2>&1 || true
rm -f /etc/sssd/sssd.conf
rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
sed -i '/# one-ondemand worker$/d;/# one-ondemand portal$/d' /etc/hosts
ok "identity and pool names removed"

# Slurm, the key of the service, the configuration the portal renders, the state of the
# controller and the accounting database seeded by the build.
rm -f /etc/munge/munge.key /etc/slurm/slurm.conf /etc/slurm/cgroup.conf /etc/slurm/gres.conf \
      /etc/slurm/slurmdbd.conf /etc/one-ondemand/slurmdbd.pass /etc/one-ondemand/ldap-admin.pass \
      /etc/one-ondemand/nfs.env /etc/one-ondemand/nfs_host /etc/one-ondemand/portal-url
# The package file, with its option commented out, is what marks a VM as no Slurm node.
printf '# Additional options that are passed to the slurmd daemon\n#SLURMD_OPTIONS=""\n' > /etc/default/slurmd
rm -rf /var/lib/one-ondemand/slurm /var/spool/slurmctld /var/spool/slurmd /var/lib/ood-slurm \
       /etc/systemd/system/slurmctld.service.d 2>/dev/null || true
ok "munge key, Slurm configuration, state and accounting removed"

# Portal role, the LDAP tree with the seeded users, the site configuration of Open OnDemand and
# its certificate. The tree is created again at boot (scripts/20-install-identity.sh).
rm -rf /var/lib/ldap/* /etc/ldap/slapd.d/* 2>/dev/null || true
rm -rf /etc/ood/config/clusters.d/* /etc/ood/config/ondemand.d/* \
       /etc/ood/config/apps/dashboard/initializers/* 2>/dev/null || true
rm -f  /etc/ood/config/ood_portal.yml
rm -rf /etc/letsencrypt /etc/ssl/one-ondemand 2>/dev/null || true
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
           /opt/one-ondemand/scripts/40-configure-slurm-controller.sh \
           /opt/one-ondemand/config/slurm/slurm.conf.tpl \
           /usr/local/sbin/ood-appliance-configure \
           /usr/local/bin/ood-slurm-elastic.sh \
           /opt/ood/ood-portal-generator/sbin/update_ood_portal; do
    [[ -e "$req" ]] || die "${req} is missing, the cleanup took away something that had to stay"
done
for secret in /etc/one-ondemand/ldap-admin.pass /etc/one-ondemand/slurmdbd.pass /etc/munge/munge.key; do
    [[ -e "$secret" ]] && die "${secret} is still there, the image would ship a secret"
done
for cmd in apptainer cvmfs_config exportfs squid slapadd slurmd slurmctld slurmdbd munged mariadbd; do
    command -v "$cmd" >/dev/null || die "${cmd} has disappeared from the image"
done
for pkg in ondemand ondemand-dex nfs-kernel-server squid slapd slurmd slurmctld slurmdbd slurm-client munge mariadb-server; do
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
#   portal    ONEAPP_NFS_HOST and ONEAPP_CVMFS_PROXY from the service, then the wizard
#             inputs ONEAPP_PORTAL_*, ONEAPP_AUTH_*, ONEAPP_HOME_NFS_* and
#             ONEAPP_SOFTWARE_PROXY_*, all optional,
#             ONEAPP_POOL_RANGE when the compute network is larger than a /24, and the
#             ONEAPP_SLURM_* advanced attributes
#   storage   ONEAPP_HOME_NFS_EXPORT and ONEAPP_SOFTWARE_PROXY_ENABLED, the rest comes from
#             its NIC and from OneGate
#   worker    ONEAPP_NFS_HOST, ONEAPP_LDAP_HOST, ONEAPP_CVMFS_PROXY, ONEAPP_HOME_NFS_*,
#             ONEAPP_SOFTWARE_PROXY_*
#
# Usage:  ONEAPP_ROLE=worker /usr/local/sbin/ood-appliance-configure

set -uo pipefail
# The one-apps service wrapper runs this with umask 0077, so anything created with a plain
# redirection would be readable by root only. Configuration that other users read, such as the
# CernVM-FS client settings the cvmfs user parses or the cluster and application files each
# user's PUN reads, needs the normal mode. Secrets are tightened where they are written.
umask 022
# one-context runs without HOME, and the EESSI modulefiles build paths from it, so a module
# load here would fail on a nil value that a shell session never sees.
export HOME="${HOME:-/root}"
LOG=/var/log/ood-appliance-configure.log
exec > >(tee -a "$LOG") 2>&1
printf '\n===== %s =====\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env

DIR="${ONEAPP_APPLIANCE_DIR:-/opt/one-ondemand}"
ROLE="${ONEAPP_ROLE:-}"

# A check that stops the role is reported through OneGate as well, as the ERROR attribute of
# the VM, so the operator reads it in Sunstone or in onevm show without opening a console.
# The message is the last ERROR line of the log, which is what the failing script printed.
# The onegate client splits its data on commas and a double quote would end the value, so
# both are replaced before publishing. The trap goes before the library is loaded, because
# the library itself stops the role when a wizard field is not valid.
report_failure() {
    local rc=$? msg
    (( rc == 0 )) && return 0
    msg="$(grep -E '\] ERROR: ' "$LOG" | tail -1 | sed 's/^\[[^]]*\] ERROR: //; s/"/'"'"'/g; s/,/;/g')"
    if . /etc/one-ondemand/onegate-lib.sh 2>/dev/null && onegate_ready; then
        onegate_call vm update --data "ERROR=\"one-ondemand ${ROLE:-?}: ${msg:-configuration failed, see ${LOG}}\"" \
            >/dev/null 2>&1 || true
    fi
}
trap report_failure EXIT

source "${DIR}/scripts/00-lib.sh"
require_root

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
# The portal and the storage VM take their role as host name, so logs, certificates and the
# prompt say what the machine is instead of carrying the name of the VM the image was built
# on. The worker derives its own from its address in worker/configure.sh.
if [[ "$ROLE" != "worker" && "$(hostname)" != "ood-${ROLE}" ]]; then
    hostnamectl set-hostname "ood-${ROLE}" 2>/dev/null || hostname "ood-${ROLE}"
    sed -i "s/^127\.0\.1\.1 .*/127.0.1.1 ood-${ROLE}/" /etc/hosts 2>/dev/null || true
    grep -q "^127.0.1.1 ood-${ROLE}" /etc/hosts || echo "127.0.1.1 ood-${ROLE}" >> /etc/hosts
fi
case "$ROLE" in
storage)
    # The elasticity publisher belongs to the worker role, see the portal case below.
    systemctl disable --now ood-slurm-elastic.service >/dev/null 2>&1 || true
    run "home NFS server"      bash "${DIR}/storage/10-install-nfs.sh"
    # With a CernVM-FS proxy of the site, the portal and the workers use that one.
    if is_yes "$ONEAPP_SOFTWARE_PROXY_ENABLED"; then
        msg "ONEAPP_SOFTWARE_PROXY_ENABLED is YES, the storage role runs no Squid"
    else
        run "site Squid for EESSI" bash "${DIR}/storage/20-install-squid.sh"
    fi
    ;;
portal)
    # The home server is checked first so a missing address fails at the top of the log.
    # The worker range is not required, pool_range derives it from the compute interface
    # when ONEAPP_POOL_RANGE is empty.
    if is_yes "$ONEAPP_HOME_NFS_ENABLED"; then
        [[ -n "$ONEAPP_HOME_NFS_SERVER" ]] \
            || die "the portal role needs ONEAPP_HOME_NFS_SERVER when ONEAPP_HOME_NFS_ENABLED is YES"
    else
        [[ -n "${ONEAPP_NFS_HOST:-}" ]] \
            || die "the portal role needs ONEAPP_NFS_HOST, the address of the storage role"
    fi
    if is_yes "$ONEAPP_SOFTWARE_PROXY_ENABLED"; then
        [[ -n "$ONEAPP_SOFTWARE_PROXY_URL" ]] \
            || die "the portal role needs ONEAPP_SOFTWARE_PROXY_URL when ONEAPP_SOFTWARE_PROXY_ENABLED is YES"
    else
        : "${ONEAPP_CVMFS_PROXY:?the portal role needs ONEAPP_CVMFS_PROXY}"
    fi
    # The elasticity publisher belongs to the worker role. On the portal it would only spend
    # OneGate calls, and it would confuse the reading of the panel.
    systemctl disable --now ood-slurm-elastic.service >/dev/null 2>&1 || true
    run "Open OnDemand"         bash "${DIR}/scripts/10-install-ood.sh"
    run "LDAP and Dex identity" bash "${DIR}/scripts/20-install-identity.sh"
    run "shared home"           bash "${DIR}/scripts/25-mount-home.sh"
    run "Slurm controller"      bash "${DIR}/scripts/40-configure-slurm-controller.sh"
    run "portal configuration"  bash "${DIR}/scripts/30-configure-portal.sh"
    run "application catalog"   bash "${DIR}/scripts/60-install-apps.sh"
    run "EESSI on the portal"   bash "${DIR}/scripts/70-install-cvmfs.sh"
    run "Slurm target"          bash "${DIR}/scripts/90-configure-slurm-target.sh"
    run "external Slurm cluster" bash "${DIR}/scripts/80-configure-external-slurm.sh"
    ;;
worker)
    # The three addresses are optional on purpose. A worker without them is a standalone
    # machine with Apptainer, and that is what the marketplace certification harness
    # instantiates. worker/configure.sh skips each block and says so in the log.
    run "Slurm node" bash "${DIR}/worker/configure.sh"
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
    # The portal also publishes the address users type, so it shows in the attributes of
    # the portal VM in Sunstone and in onevm show, next to READY.
    if [[ "$ROLE" == "portal" && -s /etc/one-ondemand/portal-url ]]; then
        onegate_call vm update --data "OOD_URL=$(cat /etc/one-ondemand/portal-url)" >/dev/null 2>&1 \
            && ok "OOD_URL published: $(cat /etc/one-ondemand/portal-url)" \
            || warn "could not publish OOD_URL"
    fi
    onegate_call vm update --data "READY=YES" >/dev/null 2>&1 \
        && ok "READY=YES published to ${ONEGATE_ENDPOINT}" \
        || warn "could not publish READY=YES to ${ONEGATE_ENDPOINT}"
    # A configure that succeeds after a failed one clears the ERROR the failure left.
    onegate_call vm update --erase ERROR >/dev/null 2>&1 || true
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
# The one-apps service wrapper runs this with umask 0077. Files the image ships for other
# users, such as the applications each user's PUN reads, need the normal mode, so it is set
# here and appliance/configure.sh does the same at boot.
umask 022
# one-context runs without HOME, and the EESSI modulefiles build paths from it, so a module
# load here would fail on a nil value that a shell session never sees.
export HOME="${HOME:-/root}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ONEAPP_APPLIANCE_DIR:-/opt/one-ondemand}"
t0=$(date +%s)

msg "=== common packages ==="
# unattended-upgrades starts on the base image at boot and can install a kernel while this
# runs, which made two builds of the same code differ by a kernel. It is stopped for the
# build; its timers stay enabled, so the deployed VM keeps receiving security updates.
systemctl stop unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
apt_install apt-transport-https ca-certificates wget curl gnupg python3

# --- Slurm, the scheduler of every session ------------------------------------------------
# Every worker runs slurmd and the portal runs the controller and the accounting. The
# packages come from Ubuntu 24.04 (Slurm 23.11), without their recommends, which are every
# plugin of the scheduler and its development files. The munge package generates a key and
# starts munged with it; the key is removed with the image and the configure of each role
# installs the one of the service.
msg "=== Slurm ==="
APT_NO_RECOMMENDS=1 apt_install slurmd slurm-client munge slurmctld slurmdbd mariadb-server libpmix2t64
ok "slurm $(dpkg-query -W -f='${Version}' slurmd 2>/dev/null), munge $(dpkg-query -W -f='${Version}' munge 2>/dev/null), mariadb $(dpkg-query -W -f='${Version}' mariadb-server 2>/dev/null)"

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
for unit in apache2 ondemand-dex slapd nfs-server nfs-kernel-server squid sssd \
            munge slurmd slurmctld slurmdbd mariadb; do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
# The elasticity publisher stays enabled because it belongs to the worker role, and on the
# other two roles it starts, finds no cluster and publishes nothing, which does no harm, so
# the configure of those roles stops it.
ok "role services disabled, they are enabled per role at boot"
# The munge package generated a key at install time. It must not travel inside the image,
# the portal generates the key of the service at first boot and the workers take it from
# OneGate.
rm -f /etc/munge/munge.key

# The packages above can bring a newer kernel than the base image carries. The build runs
# on the old one, so autoremove keeps it, and both would then travel in every download of
# the appliance. Only the newest kernel stays; the first boot of the image uses it.
msg "=== one kernel, and nothing that nothing depends on ==="
newest="$(ls /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)"
old_kernels="$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 'linux-modules-[0-9]*' \
    'linux-modules-extra-[0-9]*' 'linux-headers-[0-9]*' 2>/dev/null | grep -v -F "${newest%-generic}" || true)"
if [[ -n "$old_kernels" ]]; then
    echo "linux-base linux-base/removing-running-kernel boolean false" | debconf-set-selections
    # shellcheck disable=SC2086
    apt-get purge -y -qq $old_kernels >/dev/null 2>&1 \
        || warn "could not remove the old kernel packages, the image keeps them"
fi
apt-get autoremove --purge -y -qq >/dev/null 2>&1 || warn "apt-get autoremove failed, the image keeps what it has"
apt-get clean
ok "kernels present: $(ls /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | tr '\n' ' ')"

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
cat > "${SRC}/config/clusters.d/external-slurm.yml" <<'ONEOND_CONFIG_CLUSTERS_D_EXTERNAL_SLURM_YML_'
# Definition of a Slurm cluster of the site as a second Open OnDemand target, for batch jobs.
# Installed at /etc/ood/config/clusters.d/external-slurm.yml by
# scripts/80-configure-external-slurm.sh
#
# The cluster of the service runs on the portal (clusters.d/slurm.yml). This one runs
# elsewhere, so every command goes to its controller over SSH as the user, through the proxy
# in /opt/one-ondemand/bin/slurm, the pattern the AWS and Azure integrations use. The
# controller shares the home and the users with the portal, so the key the portal already
# created for each user opens the session.
#
# The @@ placeholders are substituted by scripts/80-configure-external-slurm.sh.
v2:
  metadata:
    title: "@@TITLE@@"
    hidden: false
  login:
    host: "@@CONTROLLER@@"
  job:
    adapter: "slurm"
    bin: "/usr/bin"
    bin_overrides:
      sbatch: "/opt/one-ondemand/bin/slurm/sbatch"
      squeue: "/opt/one-ondemand/bin/slurm/squeue"
      scancel: "/opt/one-ondemand/bin/slurm/scancel"
      scontrol: "/opt/one-ondemand/bin/slurm/scontrol"
      sinfo: "/opt/one-ondemand/bin/slurm/sinfo"
      sacct: "/opt/one-ondemand/bin/slurm/sacct"
      sacctmgr: "/opt/one-ondemand/bin/slurm/sacctmgr"
ONEOND_CONFIG_CLUSTERS_D_EXTERNAL_SLURM_YML_

install -d -m 755 "${SRC}/config/clusters.d"
cat > "${SRC}/config/clusters.d/slurm.yml" <<'ONEOND_CONFIG_CLUSTERS_D_SLURM_YML_'
# The Slurm cluster of the service as the Open OnDemand target of every session.
# Installed at /etc/ood/config/clusters.d/slurm.yml by scripts/90-configure-slurm-target.sh.
#
# The portal is the controller, so the stock slurm adapter runs sbatch, squeue and the
# rest locally, as the user, against /etc/slurm/slurm.conf. Every interactive app and the
# Job Composer submit here, so Slurm sees the whole load of the pool and no two sessions
# share a core.
#
# The @@ placeholders are substituted by scripts/90-configure-slurm-target.sh.
v2:
  metadata:
    title: "Slurm"
    hidden: false
  # No login section: the Shell app opens a terminal on the portal itself, where every
  # user has their home, see the shell env in scripts/30-configure-portal.sh.
  # No cluster key: with one local cluster the clients talk to slurmctld directly, and a
  # pause of slurmdbd never blocks a session.
  job:
    adapter: "slurm"
    bin: "/usr/bin"
    conf: "/etc/slurm/slurm.conf"
    # The session script sources everything it needs, so the environment of the PUN is
    # not copied into the job.
    copy_environment: false
  batch_connect:
    basic:
      # The host published in the session is the address of the node on the compute
      # network, the one the portal proxy reaches and host_regex accepts.
      set_host: "host=$(hostname -I | tr ' ' '\\n' | grep '^@@COMPUTE_PREFIX_RE@@' | head -1)"
    vnc:
      # The Desktop app. Same host rule, and websockify from the distribution package
      # rather than the /opt/websockify/run the template assumes.
      set_host: "host=$(hostname -I | tr ' ' '\\n' | grep '^@@COMPUTE_PREFIX_RE@@' | head -1)"
      websockify_cmd: "/usr/bin/websockify"
    ssh_allow: false
ONEOND_CONFIG_CLUSTERS_D_SLURM_YML_

install -d -m 755 "${SRC}/config/slurm"
cat > "${SRC}/config/slurm/cgroup.conf" <<'ONEOND_CONFIG_SLURM_CGROUP_CONF_'
# Installed at /etc/slurm/cgroup.conf on the portal and served to the workers with the rest
# of the configuration. cgroup v2 fences every job to the cores and the memory it asked for.
CgroupPlugin=autodetect
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainDevices=yes
ONEOND_CONFIG_SLURM_CGROUP_CONF_

install -d -m 755 "${SRC}/config/slurm"
cat > "${SRC}/config/slurm/slurm.conf.tpl" <<'ONEOND_CONFIG_SLURM_SLURM_CONF_TPL_'
# Slurm cluster of the Open OnDemand service, served by the portal.
# Installed at /etc/slurm/slurm.conf by scripts/40-configure-slurm-controller.sh, which
# substitutes the @@ placeholders. The workers run slurmd in configless mode and fetch
# this file from the portal, so it exists on the portal only and a change here is applied
# with `scontrol reconfigure`.
ClusterName=ood
SlurmctldHost=ood-portal(@@PORTAL_IP@@)
AuthType=auth/munge
SlurmUser=slurm
# The controller state lives on the storage VM over NFS, so a portal that OneFlow replaces
# finds the queue and the nodes where it left them. Measured on 16 September 2026, an
# sbatch takes 0.035 s there against 0.020 s on the local disk.
StateSaveLocation=@@STATE_DIR@@
SlurmdSpoolDir=/var/spool/slurmd
# Under the runtime directories the Debian units create for each daemon.
SlurmctldPidFile=/run/slurmctld/slurmctld.pid
SlurmdPidFile=/run/slurm/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
# Workers register themselves as dynamic nodes (slurmd -Z) and take their configuration
# from the controller, so no node is declared here. MaxNodeCount bounds how many can exist,
# the size of the address range the workers can take on the compute network.
SlurmctldParameters=enable_configless
MaxNodeCount=@@MAX_NODES@@
ReturnToService=2
SlurmdTimeout=60
# Cores and memory are consumable, so two sessions never share a core and a job that grows
# past its memory is stopped, which is what makes the cores of the pool exclusive.
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
DefMemPerCPU=@@DEF_MEM_PER_CPU@@
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity
JobAcctGatherType=jobacct_gather/cgroup
PrologFlags=Contain
GresTypes=gpu
# A session is never requeued on another node: its browser connection points at the node
# that started it.
JobRequeue=0
# Every task gets a runtime directory and a D-Bus of its own, see the prolog.
TaskProlog=/opt/one-ondemand/worker/slurm-task-prolog.sh
TaskEpilog=/opt/one-ondemand/worker/slurm-task-epilog.sh
SchedulerType=sched/backfill
MpiDefault=none
MailProg=/bin/true
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
# One partition with every node, dynamic ones included (Nodes=ALL). The limit matches the
# longest session the forms offer.
PartitionName=main Nodes=ALL Default=YES MaxTime=12:00:00 DefaultTime=01:00:00 OverSubscribe=NO State=UP
ONEOND_CONFIG_SLURM_SLURM_CONF_TPL_

install -d -m 755 "${SRC}/config/slurm"
cat > "${SRC}/config/slurm/slurmdbd.conf.tpl" <<'ONEOND_CONFIG_SLURM_SLURMDBD_CONF_TPL_'
# Accounting daemon of the Slurm cluster, on the portal, over the local MariaDB.
# Installed at /etc/slurm/slurmdbd.conf by scripts/40-configure-slurm-controller.sh.
AuthType=auth/munge
DbdHost=localhost
SlurmUser=slurm
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurmdbd/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageHost=localhost
StorageUser=slurm
StoragePass=@@DB_PASS@@
StorageLoc=slurm_acct_db
ONEOND_CONFIG_SLURM_SLURMDBD_CONF_TPL_

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

# is_yes VALUE: true for yes, true and 1, in any case. A switch of the instantiate wizard
# arrives in the CONTEXT as the string YES or NO, and this is the only place that spelling
# is compared, so every script reads a switch through it and never the raw string.
is_yes() {
    case "${1:-}" in
        [Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|1) return 0 ;;
        *) return 1 ;;
    esac
}

# --- portal parameters (tab PORTAL of the wizard) ------------------------------------
ONEAPP_OOD_VERSION="${ONEAPP_OOD_VERSION:-4.2}"
ONEAPP_OOD_RELEASE_DEB="${ONEAPP_OOD_RELEASE_DEB:-ondemand-release-web_4.2.0-noble_all.deb}"
ONEAPP_OOD_APT_BASE="${ONEAPP_OOD_APT_BASE:-https://apt.osc.edu/ondemand}"
# Empty by default. A published image must not carry the name of the site it was built
# on, so when it is not given the portal names itself after its own address.
ONEAPP_PORTAL_HOST_NAME="${ONEAPP_PORTAL_HOST_NAME:-}"
# Two switches instead of a list. The default is a self-signed certificate, the first switch
# asks Let's Encrypt for one, and the second installs the chain and the key given below.
ONEAPP_PORTAL_LETSENCRYPT_ENABLED="${ONEAPP_PORTAL_LETSENCRYPT_ENABLED:-NO}"
ONEAPP_PORTAL_CERTIFICATE_ENABLED="${ONEAPP_PORTAL_CERTIFICATE_ENABLED:-NO}"
ONEAPP_PORTAL_CERTIFICATE_CHAIN="${ONEAPP_PORTAL_CERTIFICATE_CHAIN:-}"
ONEAPP_PORTAL_CERTIFICATE_KEY="${ONEAPP_PORTAL_CERTIFICATE_KEY:-}"
ONEAPP_OOD_SSL_EMAIL="${ONEAPP_OOD_SSL_EMAIL:-}"
# The certificate mode is derived here, once, and it is the only thing the portal reads.
# With both switches on the customer certificate is installed, not the Let's Encrypt one,
# and 30-configure-portal.sh checks that the chain and the key are there when it installs
# them.
if is_yes "$ONEAPP_PORTAL_CERTIFICATE_ENABLED"; then
    SSL_MODE=custom
elif is_yes "$ONEAPP_PORTAL_LETSENCRYPT_ENABLED"; then
    SSL_MODE=letsencrypt
else
    SSL_MODE=selfsigned
fi

# --- identity parameters (tab AUTH of the wizard) -------------------------------------
ONEAPP_LDAP_DOMAIN="${ONEAPP_LDAP_DOMAIN:-ood.local}"
ONEAPP_LDAP_BASE="${ONEAPP_LDAP_BASE:-dc=ood,dc=local}"
# Empty by default. A published image must not ship a password, so when none is given the
# portal generates one the first time it configures the directory and keeps it root only in
# /etc/one-ondemand/ldap-admin.pass. ldap_admin_pass below resolves it.
ONEAPP_LDAP_ADMIN_PASS="${ONEAPP_LDAP_ADMIN_PASS:-}"
ONEAPP_AUTH_LOCAL_USERS="${ONEAPP_AUTH_LOCAL_USERS:-demo1:demo1pass}"
# An OpenID Connect provider beside the local directory, only when its switch is on. With
# the switch off the four values below are ignored even if they are filled in.
ONEAPP_AUTH_OIDC_ENABLED="${ONEAPP_AUTH_OIDC_ENABLED:-NO}"
ONEAPP_AUTH_OIDC_ISSUER="${ONEAPP_AUTH_OIDC_ISSUER:-}"
ONEAPP_AUTH_OIDC_CLIENT_ID="${ONEAPP_AUTH_OIDC_CLIENT_ID:-}"
ONEAPP_AUTH_OIDC_CLIENT_SECRET="${ONEAPP_AUTH_OIDC_CLIENT_SECRET:-}"
ONEAPP_AUTH_OIDC_NAME="${ONEAPP_AUTH_OIDC_NAME:-Institutional login}"

# --- home parameters (tab HOME of the wizard) ----------------------------------------
# The home comes from the storage role of the service, ONEAPP_NFS_HOST, unless the switch
# points the portal and the workers at an NFS server the site already runs. The export path
# is the one on that server; with the switch off the storage role exports /export/home.
ONEAPP_HOME_NFS_ENABLED="${ONEAPP_HOME_NFS_ENABLED:-NO}"
ONEAPP_HOME_NFS_SERVER="${ONEAPP_HOME_NFS_SERVER:-}"
ONEAPP_HOME_NFS_EXPORT="${ONEAPP_HOME_NFS_EXPORT:-/export/home}"

# --- software catalogue parameters (tab SOFTWARE of the wizard) -----------------------
# The EESSI catalogue comes through the cache of the storage role, ONEAPP_CVMFS_PROXY, unless
# the switch points the portal and the workers at a CernVM-FS proxy the site already runs.
ONEAPP_SOFTWARE_PROXY_ENABLED="${ONEAPP_SOFTWARE_PROXY_ENABLED:-NO}"
ONEAPP_SOFTWARE_PROXY_URL="${ONEAPP_SOFTWARE_PROXY_URL:-}"

# --- advanced attributes, not in the wizard -------------------------------------------
# An operator sets these in the vm_template_contents of a role or in the CONTEXT of a
# standalone VM. ONEAPP_POOL_RANGE has no default because pool_range below derives it, and
# ONEAPP_WORKER_IDLE_SECONDS is read from the context by worker/slurm-elastic.sh alone.
ONEAPP_METRICS_PORT="${ONEAPP_METRICS_PORT:-9101}"
# The Slurm cluster of the service, always on: the export of the storage role that keeps the
# controller state, and the memory a job gets per core when it asks for none.
ONEAPP_SLURM_STATE_EXPORT="${ONEAPP_SLURM_STATE_EXPORT:-/export/slurm}"
ONEAPP_SLURM_DEF_MEM_PER_CPU="${ONEAPP_SLURM_DEF_MEM_PER_CPU:-1024}"
# A second Slurm cluster of the site, beside the one of the service, for batch jobs only
# (scripts/80-configure-external-slurm.sh). It shares the users and the home of the portal.
ONEAPP_SLURM_CONTROLLER_ENABLED="${ONEAPP_SLURM_CONTROLLER_ENABLED:-NO}"
ONEAPP_SLURM_CONTROLLER_HOST="${ONEAPP_SLURM_CONTROLLER_HOST:-}"
ONEAPP_SLURM_TITLE="${ONEAPP_SLURM_TITLE:-External Slurm}"

# --- target parameters ---------------------------------------------------------
# EESSI catalogue version and the module with JupyterLab and ipykernel for the kernel.
ONEAPP_EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
ONEAPP_EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"

export ONEAPP_OOD_VERSION ONEAPP_OOD_RELEASE_DEB ONEAPP_OOD_APT_BASE \
       ONEAPP_PORTAL_HOST_NAME ONEAPP_OOD_SSL_EMAIL \
       ONEAPP_LDAP_DOMAIN ONEAPP_LDAP_BASE ONEAPP_LDAP_ADMIN_PASS ONEAPP_AUTH_LOCAL_USERS

export DEBIAN_FRONTEND=noninteractive

# --- output --------------------------------------------------------------------
msg()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf '[%s]   ok: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '[%s]   warning: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() { [[ "$(id -u)" -eq 0 ]] || die "it has to be run as root"; }

# --- a switch that is off empties the fields of its section -----------------------------
# The wizard hides the fields of a section while its switch is off, but it still sends what
# was typed in them before. No script reads a field of a section whose switch is off, and a
# field of a section whose switch is on is checked here before any script uses it.
if ! is_yes "$ONEAPP_PORTAL_CERTIFICATE_ENABLED"; then
    ONEAPP_PORTAL_CERTIFICATE_CHAIN=""; ONEAPP_PORTAL_CERTIFICATE_KEY=""
fi
if ! is_yes "$ONEAPP_AUTH_OIDC_ENABLED"; then
    ONEAPP_AUTH_OIDC_ISSUER=""; ONEAPP_AUTH_OIDC_CLIENT_ID=""; ONEAPP_AUTH_OIDC_CLIENT_SECRET=""
    ONEAPP_AUTH_OIDC_NAME="Institutional login"
fi
if is_yes "$ONEAPP_HOME_NFS_ENABLED"; then
    [[ "$ONEAPP_HOME_NFS_EXPORT" == /* && "$ONEAPP_HOME_NFS_EXPORT" != *[[:space:]]* ]] \
        || die "ONEAPP_HOME_NFS_EXPORT has to be an absolute path without spaces, not '${ONEAPP_HOME_NFS_EXPORT}'"
else
    ONEAPP_HOME_NFS_SERVER=""; ONEAPP_HOME_NFS_EXPORT="/export/home"
fi
if is_yes "$ONEAPP_SOFTWARE_PROXY_ENABLED"; then
    [[ "$ONEAPP_SOFTWARE_PROXY_URL" == http://* || "$ONEAPP_SOFTWARE_PROXY_URL" == https://* ]] \
        && [[ "$ONEAPP_SOFTWARE_PROXY_URL" != *[[:space:]]* ]] \
        || die "ONEAPP_SOFTWARE_PROXY_URL has to be an http:// or https:// URL, not '${ONEAPP_SOFTWARE_PROXY_URL}'"
else
    ONEAPP_SOFTWARE_PROXY_URL=""
fi
if ! is_yes "$ONEAPP_SLURM_CONTROLLER_ENABLED"; then
    ONEAPP_SLURM_CONTROLLER_HOST=""; ONEAPP_SLURM_TITLE="External Slurm"
fi

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

# apt_install PKG...: install without prompting, and only if something is missing. With
# APT_NO_RECOMMENDS=1 the recommended packages stay out, for the packages whose recommends
# are plugins and development files the appliance never uses.
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
    apt-get install -y ${APT_NO_RECOMMENDS:+--no-install-recommends} \
        -o Dpkg::Options::=--force-confold "${missing[@]}" >/dev/null \
        || die "installation failed for: ${missing[*]}"
    ok "installed: ${missing[*]}"
}

# service_up UNIT: start and enable it, and check that it ended up active.
service_up() {
    local unit="$1" out
    # enable and start are two calls on purpose. For a unit that systemd generates from an
    # LSB init script, which is what slapd still is on Ubuntu 24.04, `enable --now` hands the
    # whole call to systemd-sysv-install and returns 0 without starting anything.
    out="$(systemctl enable "$unit" 2>&1)" \
        || warn "could not enable ${unit} at boot: ${out}"
    out="$(systemctl start "$unit" 2>&1)" \
        || die "service ${unit} did not start: ${out}"
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

# ldap_users_check: stops on an entry of ONEAPP_AUTH_LOCAL_USERS that would leave the
# directory inconsistent, with a message that names the entry, so a typo in the wizard shows
# as the ERROR of the VM instead of as two users sharing files. An entry is user:password
# with an optional :uid.
ldap_users_check() {
    local entry user pass uid seen_users=" " seen_uids=" "
    for entry in $ONEAPP_AUTH_LOCAL_USERS; do
        IFS=: read -r user pass uid <<<"$entry"
        [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] \
            || die "ONEAPP_AUTH_LOCAL_USERS: '${entry}' has no valid user name (lowercase letters, digits, _ and -)"
        [[ -n "$pass" ]] || die "ONEAPP_AUTH_LOCAL_USERS: '${entry}' has no password"
        [[ -z "$uid" || ( "$uid" =~ ^[0-9]+$ && "$uid" -ge 1000 ) ]] \
            || die "ONEAPP_AUTH_LOCAL_USERS: '${entry}' needs a numeric uid of 1000 or more, or no uid at all"
        [[ "$seen_users" == *" ${user} "* ]] && die "ONEAPP_AUTH_LOCAL_USERS: user ${user} appears twice"
        [[ -n "$uid" && "$seen_uids" == *" ${uid} "* ]] && die "ONEAPP_AUTH_LOCAL_USERS: uid ${uid} is given to two users"
        seen_users+="${user} "; [[ -n "$uid" ]] && seen_uids+="${uid} "
    done
}

# ldap_users_each: splits each entry of ONEAPP_AUTH_LOCAL_USERS and calls the given
# function with user, password and uid. An entry without a uid gets the next free number
# from 10001, in the order of the list, skipping the uids given to other entries, so the
# same list always produces the same accounts.
ldap_users_each() {
    local fn="$1" entry user pass uid given=" " next=10001
    ldap_users_check
    for entry in $ONEAPP_AUTH_LOCAL_USERS; do
        IFS=: read -r user pass uid <<<"$entry"
        [[ -n "$uid" ]] && given+="${uid} "
    done
    for entry in $ONEAPP_AUTH_LOCAL_USERS; do
        IFS=: read -r user pass uid <<<"$entry"
        if [[ -z "$uid" ]]; then
            while [[ "$given" == *" ${next} "* ]]; do next=$(( next + 1 )); done
            uid=$next; next=$(( next + 1 ))
        fi
        "$fn" "$user" "$pass" "$uid"
    done
}

# ldap_admin_pass: the LDAP administrator password, from the context, from the file the portal
# keeps, or generated now and written to that file with mode 600. Only the portal calls it.
ldap_admin_pass() {
    local f=/etc/one-ondemand/ldap-admin.pass
    if [[ -n "$ONEAPP_LDAP_ADMIN_PASS" ]]; then
        printf '%s' "$ONEAPP_LDAP_ADMIN_PASS"
    elif [[ -s "$f" ]]; then
        cat "$f"
    else
        install -d -m 755 /etc/one-ondemand
        local pw
        pw="$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-24)"
        (umask 077; printf '%s' "$pw" > "$f")
        printf '%s' "$pw"
    fi
}

# compute_net_cidr: the network of the last NIC in the context, in CIDR notation. In the
# service that NIC is the compute network, because the roles get the management network first
# and the compute network second. Empty when the context carries no NIC.
compute_net_cidr() {
    [[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env
    local i ip mask
    for i in 3 2 1 0; do
        ip="ETH${i}_IP"; mask="ETH${i}_MASK"
        [[ -n "${!ip:-}" ]] || continue
        python3 -c 'import ipaddress, sys; print(ipaddress.ip_network(f"{sys.argv[1]}/{sys.argv[2]}", strict=False))' \
            "${!ip}" "${!mask:-255.255.255.0}" 2>/dev/null
        return
    done
}

# compute_addr: the address of this VM on the compute network and where it came from, as
# "ethN a.b.c.d". It is the last NIC in the context, for the same reason as compute_net_cidr,
# or the last address of hostname -I on a VM with no context. Empty when there is none.
# Call it in a command substitution, because it sources the context environment.
compute_addr() {
    [[ -r /var/run/one-context/one_env ]] && . /var/run/one-context/one_env
    local i ip
    for i in 3 2 1 0; do
        ip="ETH${i}_IP"
        [[ -n "${!ip:-}" ]] || continue
        printf 'eth%s %s\n' "$i" "${!ip}"
        return
    done
    ip="$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | tail -1)"
    [[ -n "$ip" ]] && printf 'hostname-I %s\n' "$ip"
}

# pool_range: sets POOL_RANGE, the address range reserved for the workers as "first-last".
# It is ONEAPP_POOL_RANGE when that is given. Otherwise the portal takes the whole /24
# around its own compute address, x.y.z.1 to x.y.z.254, and says so in the log. The
# exclusion list of 90-configure-vm-pool.sh already takes the portal and the storage out of
# it. A compute network larger than a /24 needs an explicit ONEAPP_POOL_RANGE.
pool_range() {
    POOL_RANGE="${ONEAPP_POOL_RANGE:-}"
    [[ -n "$POOL_RANGE" ]] && return 0
    local iface ip
    read -r iface ip < <(compute_addr)
    [[ -n "${ip:-}" ]] || die "ONEAPP_POOL_RANGE is empty and this VM has no IPv4 address to derive it from"
    POOL_RANGE="${ip%.*}.1-${ip%.*}.254"
    msg "worker range ${POOL_RANGE} derived from ${iface} (${ip}), ONEAPP_POOL_RANGE not given"
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
ONEAPP_LDAP_ADMIN_PASS="$(ldap_admin_pass)"
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
#   ONEAPP_NFS_HOST          private IP of the storage VM (required unless the switch is on)
#   ONEAPP_HOME_NFS_ENABLED  YES to mount an NFS server the site already runs instead
#   ONEAPP_HOME_NFS_SERVER   address of that server (required when the switch is on)
#   ONEAPP_HOME_NFS_EXPORT   path of the export (/export/home)
#
# Usage:  ONEAPP_NFS_HOST=172.20.0.221 ./25-mount-home.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

# The home comes from the storage role of the service, or from a server of the site when
# the switch is on, and then that address has to be given.
if is_yes "$ONEAPP_HOME_NFS_ENABLED"; then
    NFS_HOST="${ONEAPP_HOME_NFS_SERVER:?ONEAPP_HOME_NFS_ENABLED is YES, set ONEAPP_HOME_NFS_SERVER to the address of the NFS server}"
else
    NFS_HOST="${ONEAPP_NFS_HOST:?ONEAPP_NFS_HOST is missing, set it to the private IP of the storage VM}"
fi
HOME_EXPORT="$ONEAPP_HOME_NFS_EXPORT"
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
# The storage role grants root to this portal once OneGate tells it the portal address,
# from a timer, so the first attempts can find root_squash still in force.
probe="/home/.one-ondemand-probe.$$"
msg "checking that root can create homes in the export"
wait_for 180 bash -c "touch '${probe}' 2>/dev/null && rm -f '${probe}'" \
    || die "root cannot write to /home over NFS after 180s, the server did not grant no_root_squash to this portal"
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
SERVERNAME="$ONEAPP_PORTAL_HOST_NAME"
BASE="$ONEAPP_LDAP_BASE"
ONEAPP_LDAP_ADMIN_PASS="$(ldap_admin_pass)"

# Without a name given, the portal answers on its own address. A published image cannot
# default to any particular host name, and an address always works for a first login over
# https, with the certificate carrying it as an IP entry rather than a DNS one.
if [[ -z "$SERVERNAME" ]]; then
    SERVERNAME="$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1)"
    [[ -n "$SERVERNAME" ]] || die "ONEAPP_PORTAL_HOST_NAME is missing and this VM has no IPv4 address"
    warn "no ONEAPP_PORTAL_HOST_NAME, the portal answers on ${SERVERNAME}"
fi
# The address users type. configure.sh publishes it to OneGate as OOD_URL of this VM, so
# it shows in the attributes of the portal VM in Sunstone and in onevm show.
install -d -m 755 /etc/one-ondemand
printf 'https://%s/\n' "$SERVERNAME" > /etc/one-ondemand/portal-url
if [[ "$SERVERNAME" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    SERVERNAME_SAN="IP:${SERVERNAME}"
else
    SERVERNAME_SAN="DNS:${SERVERNAME}"
fi

# The origin allowed to use the per user key, besides the portal loopback: the address of
# this VM on the compute network, because the proxy to an external Slurm cluster opens an
# SSH session on its controller with this same key and arrives from that address.
read -r _ PORTAL_COMPUTE_IP < <(compute_addr)
[[ -n "${PORTAL_COMPUTE_IP:-}" ]] || die "this VM has no address on the compute network"

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
elif [[ "$SSL_MODE" == "custom" ]]; then
    # A certificate the customer already owns, given as two base64 encoded PEM inputs, which
    # is how a text64 user input reaches the context. A value that already starts with the
    # PEM header is taken as is. SSL_MODE comes from 00-lib.sh, custom when the switch
    # ONEAPP_PORTAL_CERTIFICATE_ENABLED is on.
    #
    # Both inputs are decoded into temporary files and checked there, and only a pair that
    # passes reaches ${cert} and ${key}. A rejected input written straight to those paths
    # would count as an existing certificate on the next run, so the corrected input would
    # never be installed and Apache would fail to start on a file that is not PEM.
    pem_input() {
        if [[ "$1" == "-----BEGIN"* ]]; then printf '%s\n' "$1"; else printf '%s' "$1" | base64 -d; fi
    }
    [[ -n "$ONEAPP_PORTAL_CERTIFICATE_CHAIN" && -n "$ONEAPP_PORTAL_CERTIFICATE_KEY" ]] \
        || die "ONEAPP_PORTAL_CERTIFICATE_ENABLED is YES, so ONEAPP_PORTAL_CERTIFICATE_CHAIN and ONEAPP_PORTAL_CERTIFICATE_KEY are required"
    tmp_cert="$(mktemp)"
    tmp_key="$(mktemp)"
    trap 'rm -f "$tmp_cert" "$tmp_key"' EXIT
    pem_input "$ONEAPP_PORTAL_CERTIFICATE_CHAIN" > "$tmp_cert"
    pem_input "$ONEAPP_PORTAL_CERTIFICATE_KEY" > "$tmp_key"
    openssl x509 -in "$tmp_cert" -noout >/dev/null 2>&1 || die "ONEAPP_PORTAL_CERTIFICATE_CHAIN is not a PEM certificate"
    openssl pkey -in "$tmp_key" -noout >/dev/null 2>&1 || die "ONEAPP_PORTAL_CERTIFICATE_KEY is not a PEM private key"
    install -m 644 "$tmp_cert" "$cert"
    install -m 600 "$tmp_key" "$key"
    rm -f "$tmp_cert" "$tmp_key"
    trap - EXIT
    ok "customer certificate installed at ${cert}"
elif [[ "$SSL_MODE" == "letsencrypt" ]]; then
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
# certificate in the exchange that decides who each user is. A customer certificate goes
# through the same step, which is harmless for one that is already trusted.
if [[ ! -L "$cert" ]]; then
    trust=/usr/local/share/ca-certificates/one-ondemand-portal.crt
    if ! cmp -s "$cert" "$trust"; then
        install -m 644 "$cert" "$trust"
        update-ca-certificates >/dev/null 2>&1 || die "could not update the certificate store"
        ok "the system now trusts the ${SSL_MODE} certificate of the portal"
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

# An external identity provider, through the OIDC connector of Dex, beside the local LDAP.
# It is added only when the switch ONEAPP_AUTH_OIDC_ENABLED is on, and then the issuer and
# the client id are required. The secret may be empty for a provider that allows public
# clients, and it is written as given. With the switch off the four values are ignored. The
# user still needs an account in the directory under the same name, because a session runs
# as a Unix user with a home; the claim used as the name is preferred_username, or the part
# of the email before the at sign, which user_map_match already keeps.
# The account name the portal maps to a Unix user is the preferred_username claim of the
# provider. Not every provider sends one (Google does not), so claimMapping falls back to
# the email, and user_map_match below keeps the part before the at sign. userNameKey is
# left at its default, name, because setting it to preferred_username makes Dex refuse
# every provider that omits that claim.
# The check runs here and not inside oidc_connector, because that function runs in a
# command substitution where die would only end the subshell.
if is_yes "$ONEAPP_AUTH_OIDC_ENABLED"; then
    [[ -n "$ONEAPP_AUTH_OIDC_ISSUER" && -n "$ONEAPP_AUTH_OIDC_CLIENT_ID" ]] \
        || die "ONEAPP_AUTH_OIDC_ENABLED is YES, so ONEAPP_AUTH_OIDC_ISSUER and ONEAPP_AUTH_OIDC_CLIENT_ID are required"
    ok "OpenID Connect provider ${ONEAPP_AUTH_OIDC_NAME} at ${ONEAPP_AUTH_OIDC_ISSUER} on the login page"
fi
oidc_connector() {
    is_yes "$ONEAPP_AUTH_OIDC_ENABLED" || return 0
    cat <<CONN
    - type: oidc
      id: oidc
      name: ${ONEAPP_AUTH_OIDC_NAME:-Institutional login}
      config:
        issuer: ${ONEAPP_AUTH_OIDC_ISSUER}
        clientID: ${ONEAPP_AUTH_OIDC_CLIENT_ID}
        clientSecret: ${ONEAPP_AUTH_OIDC_CLIENT_SECRET}
        redirectURI: https://${SERVERNAME}/dex/callback
        insecureSkipEmailVerified: true
        scopes: [openid, profile, email]
        claimMapping:
          preferred_username: email
CONN
}

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
$(oidc_connector)
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
# deployment has no login nodes, and the proxy to an external Slurm cluster opens another
# one to its controller. It is the same key for both, and it only works from the portal,
# over localhost or from its address on the compute network. A key created by an earlier
# version with another origin is corrected here.
sshdir="${home}/.ssh"
key="${sshdir}/id_ed25519_portal"
origin='from="127.0.0.1,::1,@@PORTAL_COMPUTE_IP@@"'
if [[ ! -f "$key" ]]; then
    group="$(id -gn "$user")"
    install -d -m 0700 -o "$user" -g "$group" "$sshdir"
    if runuser -u "$user" -- ssh-keygen -q -t ed25519 -N "" -C "one-ondemand-portal" -f "$key" </dev/null; then
        printf '%s %s\n' "$origin" "$(cat "${key}.pub")" >> "${sshdir}/authorized_keys"
        grep -qs "id_ed25519_portal" "${sshdir}/config" \
            || printf 'Host *\n    IdentityFile %s\n    StrictHostKeyChecking accept-new\n' "$key" >> "${sshdir}/config"
        chown "$user:$group" "${sshdir}/authorized_keys" "${sshdir}/config"
        chmod 600 "${sshdir}/authorized_keys" "${sshdir}/config"
        logger -t ood-prehook "web terminal key created for ${user}"
    else
        logger -t ood-prehook "could not create the web terminal key of ${user}"
    fi
fi
if [[ -f "${key}.pub" && -f "${sshdir}/authorized_keys" ]]; then
    pub="$(cut -d' ' -f2 "${key}.pub")"
    if grep -qF "$pub" "${sshdir}/authorized_keys" && ! grep -F "$pub" "${sshdir}/authorized_keys" | grep -qF "$origin"; then
        awk -v pub="$pub" -v pre="$origin" \
            'index($0, pub) { sub(/^from="[^"]*" */, ""); $0 = pre " " $0 } { print }' \
            "${sshdir}/authorized_keys" > "${sshdir}/authorized_keys.new" \
            && cat "${sshdir}/authorized_keys.new" > "${sshdir}/authorized_keys" && rm -f "${sshdir}/authorized_keys.new"
        logger -t ood-prehook "web terminal key origin of ${user} set to the portal"
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
        # As the user, so the directories on the way belong to the user too. install -d
        # would leave ondemand/data/sys owned by root and the dashboard could never create
        # its own directory beside myjobs.
        runuser -u "$user" -- mkdir -p "$myjobs_dir" && chmod 700 "$myjobs_dir"
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
# The hook is written with a quoted heredoc, so the portal address is substituted here
# instead of being expanded inside it.
sed -i "s|@@PORTAL_COMPUTE_IP@@|${PORTAL_COMPUTE_IP}|g" /opt/one-ondemand/bin/pun_prehook
if grep -q '@@PORTAL_COMPUTE_IP@@' /opt/one-ondemand/bin/pun_prehook; then
    die "the portal address was not substituted in the pre-PUN hook"
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

# --- OneGate library --------------------------------------------------------------------
# The exporter, the Slurm reconciler and the boot phase ask OneGate about the service. The
# image already carries the library (worker/install.sh), and this keeps it current.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install -d -m 755 /etc/one-ondemand
install -m 644 "${REPO_ROOT}/worker/onegate-lib.sh" /etc/one-ondemand/onegate-lib.sh
bash -n /etc/one-ondemand/onegate-lib.sh || die "onegate-lib.sh is not valid bash"

# --- metrics --------------------------------------------------------------------------
# One Prometheus endpoint for the whole service. The exporter reads what the workers
# publish to OneGate and adds the portal's own count of per user web servers. It listens on
# every address of the VM, so scrape it over the management network and keep the port
# out of any public firewall rule.
METRICS_PORT="${ONEAPP_METRICS_PORT:-9101}"
install -m 755 "${REPO_ROOT}/scripts/ood-metrics-exporter.py" /usr/local/bin/ood-metrics-exporter
cat > /etc/systemd/system/ood-metrics-exporter.service <<UNIT
[Unit]
Description=Prometheus metrics of the Open OnDemand service
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ood-metrics-exporter ${METRICS_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
service_up ood-metrics-exporter
wait_for 30 bash -c "curl -sf http://127.0.0.1:${METRICS_PORT}/metrics | grep -q ood_exporter_scrape_ok" \
    || die "the metrics exporter does not answer on port ${METRICS_PORT}"
ok "metrics on http://<portal>:${METRICS_PORT}/metrics"

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
cat > "${SRC}/scripts/40-configure-slurm-controller.sh" <<'ONEOND_SCRIPTS_40_CONFIGURE_SLURM_CONTROLLER_SH_'
#!/usr/bin/env bash
# Starts the Slurm controller of the service on the portal.
#
# Every session of the portal is a Slurm job, so the portal runs slurmctld, slurmdbd with
# MariaDB for the accounting, and munge. The workers register themselves as dynamic nodes
# and take their configuration from here (configless), so this VM holds the only copy of
# slurm.conf and cgroup.conf, rendered from config/slurm.
#
# Two things outlive this VM. The controller state (the queue and the nodes) and the munge
# key live on the storage VM, on the export /export/slurm that the storage grants to the
# portal alone, so a portal that OneFlow replaces finds the same key and the same queue. The
# accounting database stays local and a timer dumps it to that export every half hour, and
# a fresh portal restores the newest dump before it starts slurmdbd.
#
# The key is published to OneGate as SLURM_MUNGE_KEY, the way the OneSlurm appliance does
# it, and each worker reads it from there at boot. Anyone who can read the template of the
# portal VM can read the key, the same exposure OneSlurm has.
#
# It is idempotent. Variables:
#   ONEAPP_NFS_HOST                address of the storage role; without it the state and
#                                  the key stay on the local disk, out loud
#   ONEAPP_SLURM_STATE_EXPORT      export of the storage VM for the state (/export/slurm)
#   ONEAPP_SLURM_DEF_MEM_PER_CPU   memory a job gets per core when it asks for none (1024)
#   ONEAPP_POOL_RANGE              bounds MaxNodeCount, derived from the compute interface
#                                  when empty (see pool_range in 00-lib.sh)
#
# Usage:  ONEAPP_NFS_HOST=172.20.0.221 ./40-configure-slurm-controller.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NFS_HOST="${ONEAPP_NFS_HOST:-}"
STATE_EXPORT="${ONEAPP_SLURM_STATE_EXPORT:-/export/slurm}"
STATE_MOUNT=/var/lib/one-ondemand/slurm
DEF_MEM_PER_CPU="${ONEAPP_SLURM_DEF_MEM_PER_CPU:-1024}"
PASS_FILE=/etc/one-ondemand/slurmdbd.pass
CLUSTER=ood

[[ "$DEF_MEM_PER_CPU" =~ ^[0-9]+$ ]] || die "ONEAPP_SLURM_DEF_MEM_PER_CPU must be a number of MB"
for pkg in slurmctld slurmdbd slurm-client munge mariadb-server; do
    dpkg -s "$pkg" >/dev/null 2>&1 || die "the package ${pkg} is not in the image, appliance/install.sh did not run"
done

read -r iface PORTAL_IP < <(compute_addr)
[[ -n "${PORTAL_IP:-}" ]] || die "this VM has no address on the compute network for the controller"
pool_range
first="${POOL_RANGE%%-*}"; last="${POOL_RANGE##*-}"
[[ "$first" =~ ^[0-9]+(\.[0-9]+){3}$ && "$last" =~ ^[0-9]+(\.[0-9]+){3}$ ]] \
    || die "ONEAPP_POOL_RANGE must be \"first-last\", for example 172.20.0.50-172.20.0.249"
MAX_NODES="$(python3 -c 'import ipaddress, sys
print(int(ipaddress.ip_address(sys.argv[2])) - int(ipaddress.ip_address(sys.argv[1])) + 1)' "$first" "$last")"
(( MAX_NODES >= 1 )) || die "ONEAPP_POOL_RANGE ${POOL_RANGE} is backwards, the last address comes before the first"
ok "controller at ${PORTAL_IP} (${iface}), up to ${MAX_NODES} nodes in ${POOL_RANGE}"

# --- state on the storage VM ---------------------------------------------------------------
# The storage exports /export/slurm to the portal address once OneGate tells it which VM is
# the portal, from the same timer that grants root on the home, so the mount may have to
# wait for it. Without a storage address the state stays here, and a replaced portal starts
# with an empty queue and a new key, which the log says.
install -d -m 755 /etc/one-ondemand "$STATE_MOUNT"
if [[ -n "$NFS_HOST" ]]; then
    msg "mounting ${NFS_HOST}:${STATE_EXPORT} on ${STATE_MOUNT}"
    backup_once /etc/fstab
    sed -i "\#^[^ ]*:[^ ]* ${STATE_MOUNT} nfs4 #d" /etc/fstab
    printf '%s:%s %s nfs4 _netdev,hard,noatime 0 0\n' "$NFS_HOST" "$STATE_EXPORT" "$STATE_MOUNT" >> /etc/fstab
    systemctl daemon-reload >/dev/null 2>&1 || true
    findmnt -n "$STATE_MOUNT" >/dev/null 2>&1 \
        || wait_for 180 mount "$STATE_MOUNT" \
        || die "could not mount ${NFS_HOST}:${STATE_EXPORT} after 180s, does the storage VM export it to this portal?"
    wait_for 180 bash -c "touch '${STATE_MOUNT}/.probe' 2>/dev/null && rm -f '${STATE_MOUNT}/.probe'" \
        || die "root cannot write to ${STATE_MOUNT}, the storage did not grant no_root_squash to this portal"
    ok "state on ${NFS_HOST}:${STATE_EXPORT}"
else
    warn "no ONEAPP_NFS_HOST: the controller state and the munge key stay on this VM"
fi
install -d -m 700 -o slurm -g slurm "${STATE_MOUNT}/state"
install -d -m 700 "${STATE_MOUNT}/etc" "${STATE_MOUNT}/backup"
install -d -m 755 -o slurm -g slurm /var/log/slurm /var/spool/slurmd

# --- munge key --------------------------------------------------------------------------------
# Generated once and kept beside the state, installed for munged, and loaded with a
# restart: the package starts munged with a key of its own at install time, and a running
# munged never rereads the file.
msg "installing the munge key"
if [[ ! -s "${STATE_MOUNT}/etc/munge.key" ]]; then
    (umask 077; dd if=/dev/urandom of="${STATE_MOUNT}/etc/munge.key" bs=1024 count=1 status=none) \
        || die "could not generate the munge key"
    ok "new munge key generated"
else
    ok "munge key of an earlier portal reused"
fi
install -d -m 700 -o munge -g munge /etc/munge
install -m 400 -o munge -g munge "${STATE_MOUNT}/etc/munge.key" /etc/munge/munge.key
systemctl enable munge >/dev/null 2>&1 || true
systemctl restart munge || die "munge did not start"
munge -n | unmunge >/dev/null 2>&1 || die "munge does not validate its own credential"
ok "munge active with the service key"

# --- configuration, before any client runs -------------------------------------------------------------------------------
# sacctmgr and sinfo read slurm.conf, so it is written before the accounting daemon starts.
msg "writing /etc/slurm/slurm.conf and cgroup.conf"
sed -e "s|@@PORTAL_IP@@|${PORTAL_IP}|" -e "s|@@STATE_DIR@@|${STATE_MOUNT}/state|" \
    -e "s|@@MAX_NODES@@|${MAX_NODES}|" -e "s|@@DEF_MEM_PER_CPU@@|${DEF_MEM_PER_CPU}|" \
    "${REPO_DIR}/config/slurm/slurm.conf.tpl" > /etc/slurm/slurm.conf
install -m 644 "${REPO_DIR}/config/slurm/cgroup.conf" /etc/slurm/cgroup.conf
chmod 644 /etc/slurm/slurm.conf
grep -qE '@@[A-Z_]+@@' /etc/slurm/slurm.conf && die "a placeholder was left in /etc/slurm/slurm.conf"

# --- accounting database ----------------------------------------------------------------------
msg "preparing the accounting database"
service_up mariadb
if [[ ! -s "$PASS_FILE" ]]; then
    (umask 077; openssl rand -hex 16 > "$PASS_FILE") || die "could not write ${PASS_FILE}"
fi
DB_PASS="$(cat "$PASS_FILE")"
mysql -e "CREATE DATABASE IF NOT EXISTS slurm_acct_db;
          CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY '${DB_PASS}';
          ALTER USER 'slurm'@'localhost' IDENTIFIED BY '${DB_PASS}';
          GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost'; FLUSH PRIVILEGES;" \
    || die "could not create the accounting database"
# An empty database on a portal with a dump on the export is a replaced portal, and the
# history comes back from the newest dump before slurmdbd creates its tables.
if [[ "$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='slurm_acct_db'")" == "0" ]]; then
    # Newest first, the names carry the UTC time of the dump.
    while read -r dump; do
        # A dump that ends without the completion mark was cut short and is skipped.
        gunzip -c "$dump" 2>/dev/null | tail -c 200 | grep -q '^-- Dump completed' \
            || { warn "$(basename "$dump") is incomplete, skipped"; continue; }
        if gunzip -c "$dump" | mysql slurm_acct_db; then
            ok "accounting restored from $(basename "$dump")"
        else
            die "could not restore the accounting from ${dump}"
        fi
        break
    done < <(ls -1 "${STATE_MOUNT}"/backup/slurm_acct_db-*.sql.gz 2>/dev/null | sort -r)
fi
sed "s|@@DB_PASS@@|${DB_PASS}|" "${REPO_DIR}/config/slurm/slurmdbd.conf.tpl" > /etc/slurm/slurmdbd.conf
chown slurm:slurm /etc/slurm/slurmdbd.conf; chmod 600 /etc/slurm/slurmdbd.conf
service_up slurmdbd
wait_for 60 sacctmgr -n list cluster || die "slurmdbd does not answer"
if ! sacctmgr -n list cluster | awk '{print $1}' | grep -qx "$CLUSTER"; then
    sacctmgr -i add cluster "$CLUSTER" >/dev/null || die "could not register the cluster ${CLUSTER} in slurmdbd"
fi
ok "accounting on MariaDB, cluster ${CLUSTER} registered"

# --- controller -------------------------------------------------------------------------------
# slurmctld must not start before the state is reachable, or it would start with an empty
# queue on the local directory that the mount later covers.
install -d -m 755 /etc/systemd/system/slurmctld.service.d
cat > /etc/systemd/system/slurmctld.service.d/one-ondemand.conf <<UNIT
# Generated by one-ondemand/scripts/40-configure-slurm-controller.sh
[Unit]
RequiresMountsFor=${STATE_MOUNT}
UNIT
systemctl daemon-reload
if systemctl is-active --quiet slurmctld; then
    scontrol reconfigure >/dev/null 2>&1 || warn "scontrol reconfigure failed, the controller keeps its configuration"
fi
service_up slurmctld
wait_for 60 sinfo || die "slurmctld does not answer"
ok "slurmctld $(scontrol show config | awk '/^SLURM_VERSION/{print $3}') up, $(sinfo -h -o '%D' | head -1) nodes registered"

# --- the key for the workers, and the timers ---------------------------------------------
msg "publishing the munge key and installing the timers"
if . /etc/one-ondemand/onegate-lib.sh 2>/dev/null && onegate_ready; then
    # Base64 without its padding: OneGate splits an attribute on the first "=" only, but an
    # "=" inside the value makes the update fail with an internal error (checked on 16
    # September 2026), and the worker puts the padding back before decoding.
    onegate_call vm update --data "SLURM_MUNGE_KEY=$(base64 -w0 /etc/munge/munge.key | tr -d '=')" >/dev/null 2>&1 \
        && ok "SLURM_MUNGE_KEY published to ${ONEGATE_ENDPOINT}" \
        || die "could not publish SLURM_MUNGE_KEY, the workers cannot join the cluster"
else
    warn "OneGate does not answer, the workers will not find the munge key there"
fi
install -m 755 "${REPO_DIR}/scripts/slurm-node-reconcile.sh" /usr/local/bin/ood-slurm-reconcile
install -m 755 "${REPO_DIR}/scripts/slurm-backup.sh" /usr/local/bin/ood-slurm-backup
cat > /etc/systemd/system/ood-slurm-reconcile.service <<'UNIT'
[Unit]
Description=Reconcile the Slurm nodes with the workers of the Open OnDemand service
After=slurmctld.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ood-slurm-reconcile
UNIT
cat > /etc/systemd/system/ood-slurm-reconcile.timer <<'UNIT'
[Unit]
Description=Reconcile the Slurm nodes every 30 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
UNIT
cat > /etc/systemd/system/ood-slurm-backup.service <<UNIT
[Unit]
Description=Dump the Slurm accounting database to the storage VM
After=mariadb.service
RequiresMountsFor=${STATE_MOUNT}

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ood-slurm-backup ${STATE_MOUNT}/backup
UNIT
cat > /etc/systemd/system/ood-slurm-backup.timer <<'UNIT'
[Unit]
Description=Dump the Slurm accounting database every 30 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
AccuracySec=1min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ood-slurm-reconcile.timer ood-slurm-backup.timer >/dev/null 2>&1 \
    || die "the Slurm timers do not start"
/usr/local/bin/ood-slurm-reconcile || warn "the first reconcile run failed, the timer retries"
ok "reconcile every 30 s, accounting dump every 30 min to ${STATE_MOUNT}/backup"

# --- verification ---------------------------------------------------------------------------
for unit in munge mariadb slurmdbd slurmctld; do
    systemctl is-active --quiet "$unit" || die "${unit} is not active"
done
ss -Hltn | awk '{print $4}' | grep -qE ':6817$' || die "slurmctld does not listen on 6817"
ok "Slurm controller ready on ${PORTAL_IP}, state in ${STATE_MOUNT}/state"
ONEOND_SCRIPTS_40_CONFIGURE_SLURM_CONTROLLER_SH_

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

    for f in manifest.yml form.yml.erb submit.yml.erb; do
        [[ -f "${dest}/${f}" ]] || die "application ${name} is missing ${f}"
    done
    ok "${name} installed in ${dest}"

    # The manifest is YAML. The form and the submit template are ERB and can only be
    # validated once they are rendered, so only the manifest is checked here.
    if command -v ruby >/dev/null 2>&1; then
        ruby -e "require 'yaml'; YAML.load_file('${dest}/manifest.yml')" 2>&1 | sed 's/^/    /' \
            || die "${name}/manifest.yml is not valid YAML"
        ok "${name}: manifest is valid"
    fi
done

# --- stock desktop ------------------------------------------------------------------
# The package installs a desktop (bc_desktop) meant to be configured per cluster under
# /etc/ood/config/apps/bc_desktop. This appliance ships its own desktop application
# (apps/desktop, same vnc template, aware of the worker roster and the EESSI catalogue),
# and the stock one would appear beside it in the listing with no configuration option
# that hides it. Its manifest and its form are diverted with dpkg-divert, the way Debian
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
#   ONEAPP_CVMFS_PROXY            Squid URL (required unless the switch is on)
#   ONEAPP_SOFTWARE_PROXY_ENABLED YES to use a CernVM-FS proxy the site already runs instead
#   ONEAPP_SOFTWARE_PROXY_URL     URL of that proxy (required when the switch is on)
#   ONEAPP_EESSI_VERSION          EESSI version (2025.06)
#   ONEAPP_EESSI_JUPYTER_MODULE   EESSI module with JupyterLab and ipykernel
#
# Usage:  ONEAPP_CVMFS_PROXY=http://172.20.0.222:3128 ./70-install-cvmfs.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

if is_yes "$ONEAPP_SOFTWARE_PROXY_ENABLED"; then
    PROXY="${ONEAPP_SOFTWARE_PROXY_URL:?ONEAPP_SOFTWARE_PROXY_ENABLED is YES, set ONEAPP_SOFTWARE_PROXY_URL to the URL of the proxy}"
else
    PROXY="${ONEAPP_CVMFS_PROXY:?ONEAPP_CVMFS_PROXY with the Squid URL is missing}"
fi
STATE_DIR=/etc/one-ondemand
MOUNT=/cvmfs/software.eessi.io
EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"

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

# The first load of JupyterLab fills the site cache and takes minutes on a fresh one, so it
# runs in the background and the portal publishes READY meanwhile. See 71-eessi-warmup.sh.
systemctl stop ood-eessi-warmup.service >/dev/null 2>&1 || true
systemd-run --quiet --unit ood-eessi-warmup --collect \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/71-eessi-warmup.sh" \
    || die "could not start the EESSI warm up"
ok "EESSI warm up started in the background, result in /var/log/ood-appliance-configure.log"
ONEOND_SCRIPTS_70_INSTALL_CVMFS_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/71-eessi-warmup.sh" <<'ONEOND_SCRIPTS_71_EESSI_WARMUP_SH_'
#!/usr/bin/env bash
# Loads the EESSI Jupyter module once on the portal, so the site cache holds its files before
# the first session asks for them, and checks that the module brings ipykernel.
#
# 70-install-cvmfs.sh starts it in the background. On a fresh site cache the load takes
# minutes, because every file comes from the EESSI servers, and the worker should not wait
# for it. The result goes to the appliance log, and a failure is published to OneGate as the
# ERROR attribute of the VM, as the boot checks do.
#
# Usage:  ./71-eessi-warmup.sh   (reads /etc/one-ondemand/eessi.env)

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root
export HOME="${HOME:-/root}"
LOG=/var/log/ood-appliance-configure.log
[[ -t 1 ]] || exec >> "$LOG" 2>&1

. /etc/one-ondemand/eessi.env
init="/cvmfs/software.eessi.io/versions/${EESSI_VERSION}/init/bash"
t0=$(date +%s)
msg "warming the site cache with ${EESSI_JUPYTER_MODULE} from the portal"
if out="$(bash -c "source '${init}' >/dev/null 2>&1 && module load '${EESSI_JUPYTER_MODULE}' && python -c 'import ipykernel'" 2>&1)"; then
    ok "${EESSI_JUPYTER_MODULE} loads and brings ipykernel, $(( $(date +%s) - t0 ))s"
else
    printf '%s\n' "$out" | tail -n 8 | sed 's/^/    /'
    if . /etc/one-ondemand/onegate-lib.sh 2>/dev/null && onegate_ready; then
        onegate_call vm update --data "ERROR=\"one-ondemand portal: could not load ${EESSI_JUPYTER_MODULE} from EESSI ${EESSI_VERSION}\"" \
            >/dev/null 2>&1 || true
    fi
    die "could not load ${EESSI_JUPYTER_MODULE} from EESSI ${EESSI_VERSION}"
fi
ONEOND_SCRIPTS_71_EESSI_WARMUP_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/80-configure-external-slurm.sh" <<'ONEOND_SCRIPTS_80_CONFIGURE_EXTERNAL_SLURM_SH_'
#!/usr/bin/env bash
# Declares a Slurm cluster of the site as a second target of the portal, for batch jobs.
#
# The sessions run on the cluster of the service, whose controller is this portal. Runs on
# the portal when the advanced attribute ONEAPP_SLURM_CONTROLLER_ENABLED is on and
# ONEAPP_SLURM_CONTROLLER_HOST names the controller of another Slurm cluster that shares
# the portal's users, over LDAP, and its home, over NFS, which is what the official OneSlurm
# service does when it is given the portal and the storage addresses. The commands of that
# cluster go to its controller over SSH as the user through a proxy, with the key the portal
# keeps in the user's home, and the Job Composer and Active Jobs then show the cluster
# beside the one of the service.
#
# It is idempotent. Variables:
#   ONEAPP_SLURM_CONTROLLER_ENABLED  YES to declare the cluster, anything else removes it
#   ONEAPP_SLURM_CONTROLLER_HOST     address or host name of the Slurm controller (required
#                                    when the switch is on, ignored otherwise)
#   ONEAPP_SLURM_TITLE               name of the cluster in the portal (External Slurm)
#
# Usage:  ONEAPP_SLURM_CONTROLLER_ENABLED=YES ONEAPP_SLURM_CONTROLLER_HOST=172.20.0.100 ./80-configure-external-slurm.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_FILE=/etc/ood/config/clusters.d/external-slurm.yml
PROXY_DIR=/opt/one-ondemand/bin/slurm
STATE_DIR=/etc/one-ondemand
CONTROLLER="$ONEAPP_SLURM_CONTROLLER_HOST"
TITLE="$ONEAPP_SLURM_TITLE"

if ! is_yes "$ONEAPP_SLURM_CONTROLLER_ENABLED"; then
    rm -f "$CLUSTER_FILE" "${STATE_DIR}/slurm_controller"
    ok "no external Slurm cluster, the portal offers the cluster of the service only"
    exit 0
fi
[[ -n "$CONTROLLER" ]] \
    || die "ONEAPP_SLURM_CONTROLLER_ENABLED is YES, so ONEAPP_SLURM_CONTROLLER_HOST is required"

install -d -m 755 "$STATE_DIR" "$PROXY_DIR"
printf '%s\n' "$CONTROLLER" > "${STATE_DIR}/slurm_controller"
chmod 644 "${STATE_DIR}/slurm_controller"
install -m 755 "${REPO_DIR}/scripts/slurm-proxy.sh" "${PROXY_DIR}/slurm-proxy"
for cmd in sbatch squeue scancel scontrol sinfo sacct sacctmgr; do
    ln -sfn slurm-proxy "${PROXY_DIR}/${cmd}"
done
ok "Slurm commands proxied to ${CONTROLLER} from ${PROXY_DIR}"

msg "writing ${CLUSTER_FILE}"
sed -e "s|@@CONTROLLER@@|${CONTROLLER}|g" -e "s|@@TITLE@@|${TITLE}|g" \
    "${REPO_DIR}/config/clusters.d/external-slurm.yml" > "$CLUSTER_FILE"
chmod 644 "$CLUSTER_FILE"
ruby -e "require 'yaml'; YAML.load_file('${CLUSTER_FILE}')" 2>&1 | sed 's/^/    /' \
    || die "${CLUSTER_FILE} is not valid YAML"

# The controller answers on port 22 or the proxy is useless. Its sshd may still be coming
# up when the portal configures itself, so this waits a little and only warns, because the
# portal is complete without the cluster and the Job Composer reads the file on each use.
if wait_for 60 bash -c "</dev/tcp/${CONTROLLER}/22" 2>/dev/null; then
    ok "cluster ${TITLE} declared, controller ${CONTROLLER} answers on port 22"
else
    warn "controller ${CONTROLLER} does not answer on port 22 yet, the cluster is declared anyway"
fi
ONEOND_SCRIPTS_80_CONFIGURE_EXTERNAL_SLURM_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/90-configure-slurm-target.sh" <<'ONEOND_SCRIPTS_90_CONFIGURE_SLURM_TARGET_SH_'
#!/usr/bin/env bash
# Declares the Slurm cluster of the service as the portal target.
#
# The controller runs on this VM (scripts/40-configure-slurm-controller.sh), so the cluster
# file only names the local configuration and the way a session publishes its address. The
# workers register themselves with the controller, so nothing about them is declared here
# and a worker OneFlow creates later is a target the moment it registers.
#
# It is idempotent. Variables:
#   ONEAPP_POOL_RANGE   range of the compute network, "first-last", whose first three
#                       octets tell a session which of its addresses to publish. Empty by
#                       default, then the /24 around the compute address of this VM.
#   ONEAPP_AUTH_LOCAL_USERS  the first user of the list checks that a job runs
#
# Usage:  ./90-configure-slurm-target.sh

source "$(dirname "${BASH_SOURCE[0]}")/00-lib.sh"
require_root

pool_range
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_FILE=/etc/ood/config/clusters.d/slurm.yml

first="${POOL_RANGE%%-*}"
[[ "$first" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "ONEAPP_POOL_RANGE must be \"first-last\", for example 172.20.0.50-172.20.0.249"
[[ -s /etc/slurm/slurm.conf ]] || die "/etc/slurm/slurm.conf is missing, the Slurm controller is not configured"

# --- target definition ---------------------------------------------------------------------
msg "writing ${CLUSTER_FILE}"
# The session publishes its address on the compute network, so the first three octets of
# the range become the pattern. Two backslashes survive YAML's double quotes as one, and
# sed halves them again, so each dot becomes four backslashes here to reach grep as one.
prefix_re="$(printf '%s' "${first%.*}." | sed 's/\./\\\\\\\\./g')"
sed "s|@@COMPUTE_PREFIX_RE@@|${prefix_re}|g" "${REPO_DIR}/config/clusters.d/slurm.yml" > "$CLUSTER_FILE"
chmod 644 "$CLUSTER_FILE"
grep -qE '@@[A-Z_]+@@' "$CLUSTER_FILE" && die "a placeholder was left in ${CLUSTER_FILE}"
ruby -e "require 'yaml'; YAML.load_file('${CLUSTER_FILE}')" 2>&1 | sed 's/^/    /' \
    || die "${CLUSTER_FILE} is not valid YAML"
ok "target slurm declared, sessions publish their ${first%.*}.x address"

# --- the job composer in the menu -------------------------------------------------------------
menu=/etc/ood/config/ondemand.d/one-ondemand.yml
if ! grep -q '"Jobs"' "$menu" 2>/dev/null; then
    sed -i 's/^  - "sessions"$/  - "Jobs"\n  - "sessions"/' "$menu"
fi
grep -q '"Jobs"' "$menu" || die "could not add the Jobs group to the menu"
ok "job composer in the menu"

# --- verification -------------------------------------------------------------------------------
# The cluster answers the same commands the adapter runs. A job is not submitted here,
# because a worker may not have registered yet, and the portal is complete without one.
msg "checking the cluster from the portal"
sinfo -h -o '%P %D' | sed 's/^/    /'
first_user="$(cut -d: -f1 <<<"${ONEAPP_AUTH_LOCAL_USERS%% *}")"
runuser -u "$first_user" -- squeue -h >/dev/null 2>&1 \
    || die "${first_user} cannot query the cluster with squeue"
ok "${first_user} reaches the cluster, $(sinfo -h -o '%D' | head -1) nodes registered so far"

for u in $(cut -d: -f1 <<<"$(tr ' ' '\n' <<<"$ONEAPP_AUTH_LOCAL_USERS")"); do
    /opt/ood/nginx_stage/sbin/nginx_stage nginx_clean -u "$u" -f >/dev/null 2>&1 || true
done
ok "Slurm target declared"
ONEOND_SCRIPTS_90_CONFIGURE_SLURM_TARGET_SH_

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

# Anything that stats the mount point before this configuration exists, such as a findmnt or
# a shell completion, makes autofs record a failed mount and refuse the repository for its
# negative timeout, 60 seconds by default. The probe therefore retries past that window.
probe_ok() { cvmfs_config probe "$REPO" 2>&1 | grep -q OK; }
if ! probe_ok; then
    msg "the first probe of ${REPO} failed, retrying while autofs forgets it"
    deadline=$(( $(date +%s) + 90 ))
    until probe_ok; do
        (( $(date +%s) < deadline )) || die "cvmfs_config probe ${REPO} failed, does it reach the proxy ${PROXY}?"
        sleep 5
    done
fi
[[ -f "${MOUNT}/versions/${EESSI_VERSION}/init/bash" ]] || die "EESSI ${EESSI_VERSION} is not present in ${MOUNT}"
ok "EESSI ${EESSI_VERSION} available in ${MOUNT} (mode ${MODE}, proxy ${PROXY}, cache ${QUOTA_MB} MB)"
ONEOND_SCRIPTS_CVMFS_CLIENT_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/ood-metrics-exporter.py" <<'ONEOND_SCRIPTS_OOD_METRICS_EXPORTER_PY_'
#!/usr/bin/env python3
"""Prometheus metrics for an Open OnDemand service on OpenNebula, served by the portal.

Every 30 seconds it reads the service through OneGate and exposes, per worker, what the
workers publish there (the jobs on the node, the Slurm queue figures, IDLE_SECONDS,
OLDEST_IDLE, HEALTHY), the cardinality of each role, and the portal's own count of running
per user web servers. One endpoint, so a
Prometheus scrapes the whole service in one place. Host metrics such as CPU and memory are
OpenNebula's and are not repeated here.

Standard library only, so it runs on the portal without anything to install. Listens on
the port given as the first argument, 9101 by default, on every address of the VM.
"""
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

REFRESH_SECONDS = 30
ONEGATE = ["bash", "-c",
           ". /etc/one-ondemand/onegate-lib.sh && onegate_ready && "
           "onegate_call service show --json --extended"]
NGINX_STAGE = "/opt/ood/nginx_stage/sbin/nginx_stage"

WORKER_GAUGES = {
    "ACTIVE_SESSIONS": ("ood_worker_active_sessions", "Slurm jobs running on the worker, sessions included"),
    "IDLE_SECONDS": ("ood_worker_idle_seconds", "Seconds since the last job on the worker ended"),
    "OLDEST_IDLE": ("ood_worker_oldest_idle", "1 when the oldest worker of the role is drained and empty, so OneFlow may remove it"),
    "SLURM_PENDING": ("ood_slurm_pending", "Jobs waiting for a worker of this role, as seen by the worker"),
    "SLURM_IDLE_NODES": ("ood_slurm_idle_nodes", "Idle nodes of the cluster, as seen by the worker"),
    "SLURM_ALLOC_NODES": ("ood_slurm_alloc_nodes", "Nodes with a job, as seen by the worker"),
    "HEALTHY": ("ood_worker_healthy", "1 when the worker passed its last check of NFS, CernVM-FS, munge and slurmd"),
}

state = {"text": "", "ts": 0}


def run(cmd, timeout=20):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return out.stdout if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def worker_address(vm):
    nics = vm.get("TEMPLATE", {}).get("NIC", [])
    nics = [nics] if isinstance(nics, dict) else nics
    return next((n["IP"] for n in nics if n.get("IP")), "")


def collect():
    lines = []
    scrape_ok = 0
    doc = run(ONEGATE)
    try:
        service = json.loads(doc)["SERVICE"] if doc else None
    except (ValueError, KeyError):
        service = None
    if service is not None:
        scrape_ok = 1
        lines.append("# HELP ood_service_state OneFlow state of the service, as its numeric code")
        lines.append("# TYPE ood_service_state gauge")
        lines.append('ood_service_state{service="%s"} %s' % (service.get("name", ""), service.get("state", -1)))
        lines.append("# HELP ood_role_cardinality VMs the role has")
        lines.append("# TYPE ood_role_cardinality gauge")
        for role in service.get("roles", []):
            lines.append('ood_role_cardinality{role="%s"} %s' % (role.get("name", ""), role.get("cardinality", 0)))
        for key, (name, help_text) in WORKER_GAUGES.items():
            lines.append("# HELP %s %s" % (name, help_text))
            lines.append("# TYPE %s gauge" % name)
            for role in service.get("roles", []):
                if not str(role.get("name", "")).startswith("worker"):
                    continue
                for node in role.get("nodes", []):
                    vm = (node.get("vm_info") or {}).get("VM", {})
                    value = (vm.get("USER_TEMPLATE") or {}).get(key)
                    if value is None:
                        continue
                    lines.append('%s{vm_id="%s",name="%s",address="%s"} %s'
                                 % (name, vm.get("ID", ""), vm.get("NAME", ""), worker_address(vm), value))
    lines.append("# HELP ood_portal_puns Per user web servers running on the portal")
    lines.append("# TYPE ood_portal_puns gauge")
    puns = run([NGINX_STAGE, "nginx_list"])
    lines.append("ood_portal_puns %d" % len([u for u in puns.splitlines() if u.strip()]))
    lines.append("# HELP ood_exporter_scrape_ok 1 when the last read of the service through OneGate succeeded")
    lines.append("# TYPE ood_exporter_scrape_ok gauge")
    lines.append("ood_exporter_scrape_ok %d" % scrape_ok)
    return "\n".join(lines) + "\n"


def refresher():
    while True:
        try:
            state["text"] = collect()
            state["ts"] = time.time()
        except Exception as exc:  # the exporter must not die on a bad read
            state["text"] = "ood_exporter_scrape_ok 0\n# %s\n" % exc
        time.sleep(REFRESH_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = state["text"].encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9101
    threading.Thread(target=refresher, daemon=True).start()
    HTTPServer(("", port), Handler).serve_forever()
ONEOND_SCRIPTS_OOD_METRICS_EXPORTER_PY_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/slurm-backup.sh" <<'ONEOND_SCRIPTS_SLURM_BACKUP_SH_'
#!/usr/bin/env bash
# Dumps the Slurm accounting database to the storage VM.
#
# Runs on the portal every 30 minutes from a timer. The database is local to the portal,
# and a portal that OneFlow replaces restores the newest dump before it starts slurmdbd
# (scripts/40-configure-slurm-controller.sh), so at most half an hour of history is lost.
# The last 48 dumps are kept, one day.
#
# Usage:  ood-slurm-backup /var/lib/one-ondemand/slurm/backup
set -u -o pipefail
dir="${1:?backup directory}"
[[ -d "$dir" ]] || exit 0
out="${dir}/slurm_acct_db-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
# The dump is kept only when mysqldump finished and wrote its completion mark, so a dump
# cut short by a failure never replaces the last good one.
if mysqldump --single-transaction slurm_acct_db 2>/dev/null > "${out}.sql" \
        && tail -c 200 "${out}.sql" | grep -q '^-- Dump completed' \
        && gzip -c "${out}.sql" > "${out}.tmp"; then
    chmod 600 "${out}.tmp" && mv -f "${out}.tmp" "$out" && rm -f "${out}.sql"
    ls -1t "${dir}"/slurm_acct_db-*.sql.gz 2>/dev/null | tail -n +49 | xargs -r rm -f
else
    rm -f "${out}.tmp" "${out}.sql"
    logger -t ood-slurm-backup "the dump of slurm_acct_db failed"
    exit 1
fi
ONEOND_SCRIPTS_SLURM_BACKUP_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/slurm-node-reconcile.sh" <<'ONEOND_SCRIPTS_SLURM_NODE_RECONCILE_SH_'
#!/usr/bin/env bash
# Keeps the Slurm view of the pool in step with the workers of the service.
#
# Runs on the portal every 30 seconds from a timer. It does two things.
#
# 1. It writes what the application forms read, so a form offers only what exists:
#    /var/lib/ood-slurm/roles, one worker role per line, from the features the nodes
#    registered with, and /var/lib/ood-slurm/shape, the largest node in cores, memory
#    and GPUs, so nobody can ask for a session no node could run.
#
# 2. It removes the nodes whose VM is gone. OneFlow terminates a worker without telling
#    Slurm, and a node that is down for good would stay in sinfo forever. Each worker
#    publishes its node name to OneGate as SLURM_NODENAME, so a registered node that no
#    VM of the service claims and that holds no job is deleted. A node nobody claims but
#    that still runs a job is drained instead, because only an empty dynamic node can be
#    deleted. Nothing is deleted when OneGate does not answer or when no worker has
#    published its name yet, the same rule the OneSlurm appliance follows.
set -u

STATE_DIR=/var/lib/ood-slurm
ONEGATE_LIB="${ONEGATE_LIB:-/etc/one-ondemand/onegate-lib.sh}"
log() { logger -t ood-slurm-reconcile "$*"; }
slurm() { timeout 20 "$@" 2>/dev/null; }

install -d -m 755 "$STATE_DIR"

# --- what the forms read ---------------------------------------------------------------------
nodes="$(slurm sinfo -h -N -o '%N %T %c %m %f %G')" || exit 0
roles="$(awk '{print $5}' <<<"$nodes" | tr ',' '\n' | grep -E '^worker' | sort -u)"
shape="$(awk '
    { if ($3 > c) c = $3; if ($4 > m) m = $4;
      n = split($6, g, ","); for (i = 1; i <= n; i++) if (g[i] ~ /^gpu:/) { split(g[i], p, ":"); v = p[length(p)] + 0; if (v > gp) gp = v } }
    END { printf "{\"cpus\": %d, \"mem_mb\": %d, \"gpus\": %d, \"nodes\": %d}\n", c, m, gp, NR }' <<<"$nodes")"
for pair in "roles:${roles}" "shape:${shape}"; do
    f="${STATE_DIR}/${pair%%:*}"
    if [[ "${pair#*:}" != "$(cat "$f" 2>/dev/null)" ]]; then
        printf '%s\n' "${pair#*:}" > "${f}.tmp" && chmod 644 "${f}.tmp" && mv -f "${f}.tmp" "$f"
    fi
done

# --- nodes whose VM is gone -----------------------------------------------------------------
[[ -r "$ONEGATE_LIB" ]] || exit 0
# shellcheck source=/dev/null
. "$ONEGATE_LIB"
onegate_ready 2>/dev/null || exit 0
live="$(onegate_call service show --json --extended 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("SERVICE", {}).get("roles", []):
    if not str(r.get("name", "")).startswith("worker"):
        continue
    for n in r.get("nodes", []):
        vm = (n.get("vm_info") or {}).get("VM", {})
        name = str((vm.get("USER_TEMPLATE") or {}).get("SLURM_NODENAME", "")).strip()
        if name:
            print(name)
')"
[[ -n "$live" ]] || exit 0
while read -r name state _; do
    [[ -n "$name" ]] || continue
    grep -qx "$name" <<<"$live" && continue
    # A node with a job still finishes it; the next run finds it empty and deletes it.
    if [[ -n "$(slurm squeue -h -w "$name" -o %i)" ]]; then
        [[ "$state" == drain* ]] || { slurm scontrol update NodeName="$name" State=DRAIN Reason="vm gone" && log "drained ${name}, its VM is gone and it still runs a job"; }
        continue
    fi
    slurm scontrol delete NodeName="$name" && log "deleted ${name}, its VM is gone" \
        || log "could not delete ${name}"
done <<<"$nodes"
ONEOND_SCRIPTS_SLURM_NODE_RECONCILE_SH_

install -d -m 755 "${SRC}/scripts"
cat > "${SRC}/scripts/slurm-proxy.sh" <<'ONEOND_SCRIPTS_SLURM_PROXY_SH_'
#!/usr/bin/env bash
# Runs the Slurm command this file is named after on the controller, as the calling user.
#
# The portal has no Slurm client and the controller has the real one, so sbatch, squeue,
# scancel, sinfo, sacct, scontrol and sacctmgr are links to this file, one per name. Every
# argument is quoted for the remote shell, and standard input travels with the call, which
# is how sbatch receives the job script from Open OnDemand.
set -u
cmd="$(basename "$0")"
controller="$(cat /etc/one-ondemand/slurm_controller 2>/dev/null || true)"
[[ -n "$controller" ]] || { echo "no Slurm controller configured on this portal" >&2; exit 1; }
quoted=""
for arg in "$@"; do quoted+=" $(printf '%q' "$arg")"; done
exec ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    -o LogLevel=ERROR "$controller" "$cmd"$quoted
ONEOND_SCRIPTS_SLURM_PROXY_SH_

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
# The portal address is not known when this runs, because the storage role starts first
# and OneFlow does not fix the address of a VM. storage/export-refresh.sh, installed here
# on a timer, asks OneGate which VM plays the portal and keeps the exports pointed at it.
#
# It is idempotent, so it rewrites its exports file and reloads it.
#
# The export lives on the root disk unless the VM carries a second disk. With one, the homes
# go there, so an operator who attaches a persistent image to the storage role keeps them
# across services (README, "Keeping the home").
#
# Variables:
#   ONEAPP_NFS_NET          network with read and write access, by default the one of the
#                           last NIC
#   ONEAPP_NFS_ADMIN_IPS    IPs with no_root_squash, space separated; in the service the
#                           portal address comes from OneGate instead, see export-refresh.sh
#   (the home export is always /export/home, the path the portal and the workers mount
#   unless ONEAPP_HOME_NFS_ENABLED points them at a server of the site)
#   ONEAPP_SLURM_STATE_EXPORT  export that keeps the Slurm controller state, the munge key
#                           and the accounting dumps of the portal (/export/slurm); the
#                           portal alone mounts it, with root
#
# Usage:  ONEAPP_NFS_ADMIN_IPS="172.20.0.220" ./10-install-nfs.sh

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/00-lib.sh"
require_root

# The compute network is the one of the last NIC in the context, unless given. The portal
# address comes from OneGate later, or from ONEAPP_NFS_ADMIN_IPS on a VM outside a service.
NFS_NET="${ONEAPP_NFS_NET:-$(compute_net_cidr)}"
NFS_ADMIN_IPS="${ONEAPP_NFS_ADMIN_IPS:-}"
# The storage role always exports /export/home. ONEAPP_HOME_NFS_EXPORT is the path on a
# server of the site, read by the portal and the workers when that switch is on.
HOME_EXPORT=/export/home
SLURM_EXPORT="${ONEAPP_SLURM_STATE_EXPORT:-/export/slurm}"
EXPORTS_FILE=/etc/exports.d/one-ondemand.exports
STATE_DIR=/etc/one-ondemand

[[ "$NFS_NET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] \
    || die "'${NFS_NET}' is not a network in CIDR notation, set ONEAPP_NFS_NET or give the VM a NIC"
for ip in $NFS_ADMIN_IPS; do
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'${ip}' in ONEAPP_NFS_ADMIN_IPS is not an address"
done

msg "installing the NFS server"
# The Marketplace image arrives with no package lists, so without this update apt
# finds no candidate for any package.
wait_apt_lock
apt-get update -qq || die "apt-get update failed"
apt_install nfs-kernel-server
ok "nfs-kernel-server installed"

install -d -m 755 "$HOME_EXPORT"
# The Slurm state is a few files the portal writes, so it lives on the root disk of this VM
# and not on the home disk; what has to survive a new portal is here either way.
install -d -m 755 "$SLURM_EXPORT"

# --- home disk ------------------------------------------------------------------------
# The first disk that is not the root disk and has no partitions is the home disk. The
# context comes as a CD-ROM, so it never matches. A blank disk is formatted and labelled;
# one that already carries the label is mounted as it is, with whatever it holds. A disk
# with any other filesystem belongs to someone else and is left alone, out loud.
HOME_LABEL=ood-home
home_disk() {
    local root_dev dev
    root_dev="$(lsblk -n -o PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)"
    for dev in $(lsblk -dn -o NAME,TYPE | awk '$2 == "disk" {print $1}'); do
        [[ "$dev" == "${root_dev:-vda}" ]] && continue
        [[ "$(lsblk -n -o TYPE "/dev/${dev}" | grep -c part)" -eq 0 ]] || continue
        printf '/dev/%s' "$dev"
        return 0
    done
    return 1
}
if disk="$(home_disk)"; then
    fs_label="$(blkid -o value -s LABEL "$disk" 2>/dev/null || true)"
    fs_type="$(blkid -o value -s TYPE "$disk" 2>/dev/null || true)"
    if [[ "$fs_label" == "$HOME_LABEL" ]]; then
        ok "${disk} carries the home from an earlier service"
    elif [[ -z "$fs_type" ]]; then
        msg "formatting the blank disk ${disk} for the homes"
        mkfs.ext4 -q -L "$HOME_LABEL" "$disk" || die "mkfs.ext4 ${disk} failed"
    else
        die "${disk} holds a ${fs_type} filesystem that is not the home, refusing to format it"
    fi
    backup_once /etc/fstab
    sed -i "\#^LABEL=${HOME_LABEL} #d" /etc/fstab
    printf 'LABEL=%s %s ext4 defaults,nofail 0 2\n' "$HOME_LABEL" "$HOME_EXPORT" >> /etc/fstab
    findmnt -n "$HOME_EXPORT" >/dev/null 2>&1 || mount "$HOME_EXPORT" || die "could not mount ${disk} on ${HOME_EXPORT}"
    ok "homes on ${disk}, mounted at ${HOME_EXPORT}"
else
    ok "no home disk attached, the homes live on the root disk at ${HOME_EXPORT}"
fi

# --- exports ----------------------------------------------------------------------
# The refresher writes the exports file, here once and then every 20 seconds from a timer,
# so the portal gets root on the export as soon as OneGate knows its address. The per IP
# entries go before the network one, because exportfs applies the most specific match.
install -d -m 755 /etc/exports.d "$STATE_DIR"
{
    printf 'NFS_NET=%s\n' "$NFS_NET"
    printf 'HOME_EXPORT=%s\n' "$HOME_EXPORT"
    printf 'SLURM_EXPORT=%s\n' "$SLURM_EXPORT"
    printf 'NFS_ADMIN_IPS=%s\n' "$NFS_ADMIN_IPS"
} > "${STATE_DIR}/nfs.env"
chmod 644 "${STATE_DIR}/nfs.env"
install -m 755 "$(dirname "${BASH_SOURCE[0]}")/export-refresh.sh" /usr/local/bin/ood-export-refresh
cat > /etc/systemd/system/ood-export-refresh.service <<'UNIT'
[Unit]
Description=Keep root on the Open OnDemand home export granted to the portal
After=nfs-server.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ood-export-refresh
UNIT
cat > /etc/systemd/system/ood-export-refresh.timer <<'UNIT'
[Unit]
Description=Refresh the Open OnDemand home export every 20 seconds

[Timer]
OnBootSec=20
OnUnitActiveSec=20
AccuracySec=5

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now nfs-server >/dev/null 2>&1 || die "nfs-server does not start"
/usr/local/bin/ood-export-refresh || die "the export refresher failed"
systemctl enable --now ood-export-refresh.timer >/dev/null 2>&1 || die "the export refresher timer does not start"
ok "exports loaded, root for: $(grep -o '^[^#]* [0-9.]*(' "$EXPORTS_FILE" | awk '{print $2}' | tr -d '(' | tr '\n' ' ')"

# --- verification ---------------------------------------------------------------------
msg "checking that the export is visible"
showmount -e localhost 2>&1 | sed 's/^/    /'
showmount -e localhost 2>/dev/null | grep -q "^${HOME_EXPORT} " \
    || die "the server does not announce ${HOME_EXPORT}"
ok "NFS server serving ${HOME_EXPORT} to ${NFS_NET} and ${SLURM_EXPORT} to the portal, which OneGate names"
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

NETS="${ONEAPP_SQUID_NETS:-$(compute_net_cidr)}"
[[ -n "$NETS" ]] || die "ONEAPP_SQUID_NETS is missing and the context has no NIC to take the network from"
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

install -d -m 755 "${SRC}/storage"
cat > "${SRC}/storage/export-refresh.sh" <<'ONEOND_STORAGE_EXPORT_REFRESH_SH_'
#!/usr/bin/env bash
# Keeps root on the home export granted to the portal, and to nobody else.
#
# The storage role starts before the portal, so when it writes its exports it cannot know
# the portal address, and a service input cannot carry it either, because OneFlow does not
# fix the address of a VM. This runs from a timer on the storage VM, asks OneGate which VM
# plays the portal role in the service, and rewrites the exports file when the set of
# addresses with root changes. The workers keep root_squash, because they run user code, and
# only the portal, the role that creates each home on first login, gets no_root_squash.
#
# The Slurm state export goes to the same addresses and to nobody else, because the
# controller state and the munge key must not be readable from a worker.
#
# A storage VM outside a service keeps the addresses ONEAPP_NFS_ADMIN_IPS gave it.
#
# Reads /etc/one-ondemand/nfs.env, written by storage/10-install-nfs.sh.
set -u

ENV_FILE=/etc/one-ondemand/nfs.env
EXPORTS_FILE=/etc/exports.d/one-ondemand.exports
ONEGATE_LIB="${ONEGATE_LIB:-/etc/one-ondemand/onegate-lib.sh}"

[[ -r "$ENV_FILE" ]] || exit 0
# shellcheck source=/dev/null
. "$ENV_FILE"
: "${NFS_NET:?}" "${HOME_EXPORT:?}"
SLURM_EXPORT="${SLURM_EXPORT:-/export/slurm}"

admin="${NFS_ADMIN_IPS:-}"
if [[ -r "$ONEGATE_LIB" ]]; then
    # shellcheck source=/dev/null
    . "$ONEGATE_LIB"
    if onegate_ready 2>/dev/null; then
        portal="$(onegate_call service show --json --extended 2>/dev/null | python3 -c '
import ipaddress, json, sys
net = ipaddress.ip_network(sys.argv[1])
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("SERVICE", {}).get("roles", []):
    if r.get("name") != "portal":
        continue
    for n in r.get("nodes", []):
        nics = ((n.get("vm_info") or {}).get("VM", {})).get("TEMPLATE", {}).get("NIC", [])
        nics = [nics] if isinstance(nics, dict) else nics
        for nic in nics:
            ip = nic.get("IP")
            if ip and ipaddress.ip_address(ip) in net:
                print(ip)
' "$NFS_NET")"
        admin="$(printf '%s\n' $admin $portal | grep -v '^$' | sort -u | tr '\n' ' ')"
    fi
fi

content="$({
    printf '# Generated by one-ondemand/storage/export-refresh.sh, rewritten when the portal changes\n'
    for ip in $admin; do
        printf '%s %s(rw,sync,no_subtree_check,no_root_squash,fsid=1)\n' "$HOME_EXPORT" "$ip"
    done
    printf '%s %s(rw,sync,no_subtree_check,root_squash,fsid=1)\n' "$HOME_EXPORT" "$NFS_NET"
    for ip in $admin; do
        [[ -d "$SLURM_EXPORT" ]] && printf '%s %s(rw,sync,no_subtree_check,no_root_squash,fsid=2)\n' "$SLURM_EXPORT" "$ip"
    done
})"

if [[ "$content" != "$(cat "$EXPORTS_FILE" 2>/dev/null)" ]]; then
    printf '%s\n' "$content" > "${EXPORTS_FILE}.tmp"
    chmod 644 "${EXPORTS_FILE}.tmp"
    mv -f "${EXPORTS_FILE}.tmp" "$EXPORTS_FILE"
    exportfs -ra && logger -t ood-export-refresh "root on ${HOME_EXPORT} for: ${admin:-nobody yet}"
fi
ONEOND_STORAGE_EXPORT_REFRESH_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/apptainer-gpu.sh" <<'ONEOND_WORKER_APPTAINER_GPU_SH_'
#!/usr/bin/env bash
# Apptainer with the GPU passed through when the VM has one, for the containers a user runs
# inside a session.
#
# On a VM without a GPU this is plain apptainer; on one with an NVIDIA device and its driver
# it adds --nv to exec, run and shell, which is what a worker role with a PCI passthrough
# needs. Prepared without a GPU to test on, so a site with one should check nvidia-smi
# inside a session first.
if [[ -e /dev/nvidia0 ]] && command -v nvidia-smi >/dev/null 2>&1; then
    case "${1:-}" in
        exec|run|shell) exec /usr/bin/apptainer "$1" --nv "${@:2}" ;;
    esac
fi
exec /usr/bin/apptainer "$@"
ONEOND_WORKER_APPTAINER_GPU_SH_

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
           /usr/local/bin/ood-slurm-elastic.sh /etc/systemd/system/ood-slurm-elastic.service; do
    [[ -e "$req" ]] || die "${req} is missing: the cleanup took away something that had to stay"
done
command -v apptainer >/dev/null || die "apptainer has disappeared from the image"
command -v cvmfs_config >/dev/null || die "the CernVM-FS client has disappeared from the image"
systemctl is-enabled ood-slurm-elastic.service >/dev/null 2>&1 \
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
#   ONEAPP_NFS_HOST          private IP of the storage VM (required)
#   ONEAPP_HOME_NFS_ENABLED  YES to mount an NFS server the site already runs instead
#   ONEAPP_HOME_NFS_SERVER   address of that server (required when the switch is on)
#   ONEAPP_HOME_NFS_EXPORT   path of the home export (/export/home)
#   ONEAPP_LDAP_HOST         private IP of the portal, where the LDAP and the Slurm
#                            controller listen (required)
#   ONEAPP_AUTH_LOCAL_USERS  the first user of the list checks that sssd resolves the
#                            portal users
#   ONEAPP_CVMFS_PROXY       URL of the Squid on the storage VM (required)
#   ONEAPP_SOFTWARE_PROXY_ENABLED  YES to use a CernVM-FS proxy the site already runs instead
#   ONEAPP_SOFTWARE_PROXY_URL      URL of that proxy (required when the switch is on)
#   ONEAPP_POOL_DOMAIN       domain the portal uses to name the pool VMs (ood.local)
#   ONEAPP_POOL_NET_PREFIX   prefix of the private compute network (172.20.)
#   ONEAPP_POOL_PREFIX       prefix of each worker's name (ood-worker-). The name is
#                            completed with the last octet of its private IP, and the
#                            portal uses the same rule.
#   ONEAPP_LDAP_BASE         base of the LDAP tree (dc=ood,dc=local)
#   ONEAPP_WORKER_SELFTEST   if it is "1", it also loads EESSI's JupyterLab inside the SIF
#                            as a deep check. It costs minutes with a cold cache, so by
#                            default it is not done at boot.
#   ONEAPP_SLURM_CONTROLLER_PORT  port of slurmctld on the portal (6817)
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
if is_yes "$ONEAPP_HOME_NFS_ENABLED"; then
    # The operator asked for a server of the site, so its address is not optional.
    NFS_HOST="$ONEAPP_HOME_NFS_SERVER"
    [[ -n "$NFS_HOST" ]] || die "ONEAPP_HOME_NFS_ENABLED is YES, so ONEAPP_HOME_NFS_SERVER is required"
else
    NFS_HOST="${ONEAPP_NFS_HOST:-}"
fi
HOME_EXPORT="$ONEAPP_HOME_NFS_EXPORT"
LDAP_HOST="${ONEAPP_LDAP_HOST:-}"
if is_yes "$ONEAPP_SOFTWARE_PROXY_ENABLED"; then
    CVMFS_PROXY="$ONEAPP_SOFTWARE_PROXY_URL"
    [[ -n "$CVMFS_PROXY" ]] || die "ONEAPP_SOFTWARE_PROXY_ENABLED is YES, so ONEAPP_SOFTWARE_PROXY_URL is required"
else
    CVMFS_PROXY="${ONEAPP_CVMFS_PROXY:-}"
fi
BASE="${ONEAPP_LDAP_BASE:-dc=ood,dc=local}"
POOL_DOMAIN="${ONEAPP_POOL_DOMAIN:-ood.local}"
# The compute network is the one the portal and the storage are on, so their addresses give
# the prefix that names this worker, unless the prefix is given.
NET_PREFIX="${ONEAPP_POOL_NET_PREFIX:-}"
if [[ -z "$NET_PREFIX" ]]; then
    ref="${ONEAPP_LDAP_HOST:-${ONEAPP_NFS_HOST:-}}"
    [[ "$ref" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\. ]] && NET_PREFIX="${BASH_REMATCH[1]}."
fi
POOL_PREFIX="${ONEAPP_POOL_PREFIX:-ood-worker-}"
EESSI_MOUNT="${ONEAPP_EESSI_MOUNT:-/cvmfs/software.eessi.io}"
EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
EESSI_JUPYTER_MODULE="${ONEAPP_EESSI_JUPYTER_MODULE:-JupyterLab/4.4.9-GCCcore-14.3.0}"
SIF_PATH="${ONEAPP_SIF_PATH:-/opt/ood/linuxhost.sif}"
# What the adapter mounts inside the image: the documented value plus the home and EESSI.
# The deep check binds the same paths the old container target did.
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
# The name is the Slurm node name, and it is derived from the address rather than taken from
# the name the VM comes with, because OneFlow names its VMs with the template
# $ROLE_NAME_$VM_NUMBER_(service_$ID), which carries parentheses and is not valid as a host
# name. OpenNebula guarantees that two VMs do not share an address, so the name is unique
# without any coordination. It is resolved in /etc/hosts with the private IP, with the
# domain as well, so hostname -A answers on a VM with no reverse DNS.
msg "making the VM name resolvable"
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
    entry="${NFS_HOST}:${HOME_EXPORT} /home nfs4 _netdev,hard,noatime 0 0"
    install -d -m 755 /home
    sed -i '\#^[^ ]*:[^ ]* /home nfs4 #d' /etc/fstab
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
    msg "pointing CernVM-FS at the proxy ${CVMFS_PROXY}"
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
    first_user="$(cut -d: -f1 <<<"${ONEAPP_AUTH_LOCAL_USERS%% *}")"
    wait_for 90 bash -c "getent passwd ${first_user} >/dev/null 2>&1" \
        || die "sssd does not resolve ${first_user} against ${LDAP_HOST}"
    ok "portal users visible: $(getent passwd "$first_user" | cut -d: -f1,3)"
else
    warn "no ONEAPP_LDAP_HOST: only the local accounts of this VM will exist"
    first_user="root"
fi

# --- Slurm node -------------------------------------------------------------------------------
# The portal runs the controller, so this VM joins it as a dynamic node: it takes the munge
# key the portal published to OneGate, points slurmd at the portal (configless, the
# configuration comes from there) and registers with its cores, its memory and its role as
# a feature, so a form can ask for a worker size with --constraint. The node name is
# published before slurmd starts, because the reconciler on the portal deletes any
# registered node that no VM of the service claims.
if [[ -n "$LDAP_HOST" ]]; then
    msg "joining the Slurm cluster of the portal at ${LDAP_HOST}"
    for req in /usr/sbin/slurmd /usr/sbin/munged; do
        [[ -x "$req" ]] || die "${req} is missing: this VM does not come from an image built with appliance/install.sh"
    done
    sed -i '/# one-ondemand portal$/d' /etc/hosts
    printf '%s ood-portal # one-ondemand portal\n' "$LDAP_HOST" >> /etc/hosts
    # shellcheck source=/dev/null
    . /etc/one-ondemand/onegate-lib.sh
    onegate_ready || die "OneGate does not answer, the munge key of the service cannot be read"
    munge_key() {
        onegate_call service show --json --extended 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for r in d.get("SERVICE", {}).get("roles", []):
    if r.get("name") != "portal":
        continue
    for n in r.get("nodes", []):
        key = ((n.get("vm_info") or {}).get("VM", {}).get("USER_TEMPLATE") or {}).get("SLURM_MUNGE_KEY", "")
        if key:
            print(key)
            sys.exit(0)
sys.exit(1)
'
    }
    key=""
    for _ in $(seq 1 36); do
        key="$(munge_key)" && [[ -n "$key" ]] && break
        sleep 5
    done
    [[ -n "$key" ]] || die "the portal has not published SLURM_MUNGE_KEY after 180s"
    install -d -m 700 -o munge -g munge /etc/munge
    # The portal publishes the key without the base64 padding, see 40-configure-slurm-controller.sh.
    while (( ${#key} % 4 )); do key+="="; done
    base64 -d <<<"$key" > /etc/munge/munge.key.new 2>/dev/null \
        && [[ "$(stat -c %s /etc/munge/munge.key.new)" -ge 32 ]] \
        || die "SLURM_MUNGE_KEY is not a valid base64 key"
    install -m 400 -o munge -g munge /etc/munge/munge.key.new /etc/munge/munge.key
    rm -f /etc/munge/munge.key.new
    systemctl enable munge >/dev/null 2>&1 || true
    # A restart, not a start: the package started munged with a key of its own.
    systemctl restart munge || die "munge does not start"
    munge -n | unmunge >/dev/null 2>&1 || die "munge does not validate a credential with the service key"
    ok "munge key of the service installed"

    role_name="$(onegate_call vm show --json 2>/dev/null | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin)["VM"].get("USER_TEMPLATE") or {}).get("ROLE_NAME", "worker"))
except Exception:
    print("worker")
')"
    # A tenth of the memory stays out of the allocations, for the system and the daemons.
    real_mem=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1024 * 9 / 10 ))
    node_conf="RealMemory=${real_mem} Feature=${role_name}"
    gpus="$(ls /dev/nvidia[0-9]* 2>/dev/null | wc -l)"
    (( gpus > 0 )) && node_conf+=" Gres=gpu:${gpus}"
    printf "# Generated by one-ondemand/worker/configure.sh\nSLURMD_OPTIONS='--conf-server ood-portal:%s -Z --conf \"%s\"'\n" \
        "${ONEAPP_SLURM_CONTROLLER_PORT:-6817}" "$node_conf" > /etc/default/slurmd
    chmod 644 /etc/default/slurmd
    install -d -m 700 -o slurm -g slurm /var/spool/slurmd
    install -d -m 755 -o slurm -g slurm /var/log/slurm
    onegate_call vm update --data "SLURM_NODENAME=${name}" >/dev/null 2>&1 \
        || die "could not publish SLURM_NODENAME"
    systemctl enable slurmd >/dev/null 2>&1 || true
    systemctl restart slurmd || die "slurmd does not start, see journalctl -u slurmd"
    wait_for 60 bash -c "sinfo -h -n '${name}' -o %T 2>/dev/null | grep -q ." \
        || die "slurmd did not register ${name} with the controller at ${LDAP_HOST} in 60s"
    ok "node ${name} registered: $(sinfo -h -n "$name" -o '%T, %c cores, %m MB, feature %f')"
else
    warn "no ONEAPP_LDAP_HOST: no Slurm controller to join, this VM runs no sessions"
fi

# --- elasticity publisher ---------------------------------------------------------------------
# It already comes enabled from the image, so normally systemd started it on its own. It is
# restarted so it reads the node it now has.
systemctl restart ood-slurm-elastic.service || warn "the elasticity publisher does not start"
ok "elasticity publisher running"

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
# the NFS, the LDAP, the Squid, the Slurm controller or the VM's own IP are stays in
# configure.sh, because that data does not exist until OpenNebula instantiates the machine.
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
#   ONEAPP_TURBOVNC_VERSION     TurboVNC version for the Desktop app (pinned, 3.3.1)
#   ONEAPP_TURBOVNC_SHA256      checksum of that Debian package
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
# The same default as scripts/cvmfs-client.sh, for the lazy loader of the desktop terminals.
EESSI_VERSION="${ONEAPP_EESSI_VERSION:-2025.06}"
TURBOVNC_VERSION="${ONEAPP_TURBOVNC_VERSION:-3.3.1}"
TURBOVNC_SHA256="${ONEAPP_TURBOVNC_SHA256:-5d99050312360a07c28aca484b944816aa32e9fe07912e3ed50e6bfda45f80ad}"
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
install -m 755 "${HERE}/apptainer-gpu.sh" /usr/local/bin/apptainer-gpu
ok "apptainer-gpu wrapper installed, it adds --nv on a VM with a GPU"

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

# --- desktop sessions -------------------------------------------------------------------------
# The Desktop app needs three things on the VM that runs the session, and the container sees
# them because /usr, /etc and /opt are bound inside it: a desktop environment, a VNC server and
# websockify. Xfce is the lightest of the desktops Open OnDemand supports and is installed
# without its recommended extras. TurboVNC is the server the vnc template of Open OnDemand is
# written for (it parses the "Desktop ... started on display" line of its vncserver and passes
# -noxstartup), so it comes from its release package, pinned and checked, like code-server.
# websockify bridges the browser to the VNC port and comes from the distribution.
msg "installing the Xfce desktop, TurboVNC and websockify for the Desktop app"
desktop_pkgs=(xfce4-session xfce4-panel xfwm4 xfdesktop4 xfce4-settings xfce4-terminal
    xfce4-appfinder thunar xfconf dbus-x11 x11-xserver-utils xfonts-base xauth websockify
    fonts-dejavu-core adwaita-icon-theme)
if dpkg -s "${desktop_pkgs[@]}" >/dev/null 2>&1; then
    ok "already installed: ${desktop_pkgs[*]}"
else
    wait_apt_lock
    # Without the recommended extras: those pull sound, printing and file system helpers that
    # a session in a browser never uses and that would add hundreds of MB to the image.
    apt-get install -y -qq --no-install-recommends -o Dpkg::Options::=--force-confold \
        "${desktop_pkgs[@]}" >/dev/null || die "installation failed for the desktop packages"
    ok "installed: ${desktop_pkgs[*]}"
fi
if dpkg -s turbovnc >/dev/null 2>&1 && [[ "$(dpkg-query -W -f='${Version}' turbovnc)" == "${TURBOVNC_VERSION}"* ]]; then
    ok "TurboVNC ${TURBOVNC_VERSION} was already installed"
else
    deb="/tmp/turbovnc_${TURBOVNC_VERSION}_amd64.deb"
    url="https://github.com/TurboVNC/turbovnc/releases/download/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb"
    curl -fsSL -o "$deb" "$url" || die "could not download ${url}"
    echo "${TURBOVNC_SHA256}  ${deb}" | sha256sum -c --quiet || die "TurboVNC package checksum mismatch"
    apt-get install -y -qq "$deb" >/dev/null 2>&1 || die "could not install TurboVNC"
    rm -f "$deb"
    # The Java viewer is not used, the browser connects through noVNC on the portal.
    rm -rf /opt/TurboVNC/java
    ok "TurboVNC ${TURBOVNC_VERSION} installed in /opt/TurboVNC"
fi
# The vnc template calls vncserver and vncpasswd by name. Wrappers rather than symlinks:
# the TurboVNC vncserver script looks for Xvnc next to its own path, and through a symlink
# in /usr/local/bin it looks there and finds nothing.
for cmd in vncserver vncpasswd; do
    printf '#!/bin/sh\nexec /opt/TurboVNC/bin/%s "$@"\n' "$cmd" > "/usr/local/bin/${cmd}"
    chmod 755 "/usr/local/bin/${cmd}"
done
# Xvnc refuses to start when /etc/turbovncserver-security.conf is not owned by root or by
# the user, and inside the unprivileged Apptainer container of a session every root-owned
# file appears as nobody. The file only restricts authentication methods, the session uses
# the one-time VNC password the vnc template generates, so the file goes and the defaults
# apply.
rm -f /etc/turbovncserver-security.conf
for cmd in vncserver vncpasswd websockify xfce4-session; do
    command -v "$cmd" >/dev/null 2>&1 || die "${cmd} is missing after the desktop installation"
done
# A terminal opened on the desktop is a login shell. Initialising EESSI for the whole
# desktop would put its compatibility layer in front of the distribution tools in PATH, and
# Ubuntu's .bashrc then evaluates the wrong lesspipe and prints an error in every terminal.
# Instead, module and ml load the catalogue on their first call.
cat > /etc/profile.d/eessi-lazy.sh <<EOF
# Generated by one-ondemand/worker/install.sh
# The EESSI software catalogue is initialised on the first module or ml call.
if [ -n "\${BASH_VERSION:-}" ] && [ -z "\${EESSI_VERSION:-}" ]; then
    __eessi_init() {
        unset -f module ml __eessi_init
        . /cvmfs/software.eessi.io/versions/${EESSI_VERSION}/init/bash >/dev/null 2>&1 \\
            || { echo "EESSI ${EESSI_VERSION} is not available under /cvmfs on this VM" >&2; return 1; }
    }
    module() { __eessi_init && module "\$@"; }
    ml() { __eessi_init && ml "\$@"; }
fi
EOF
chmod 644 /etc/profile.d/eessi-lazy.sh
ok "desktop sessions: xfce4-session, $(/opt/TurboVNC/bin/vncserver -version 2>&1 | head -1), $(websockify --version 2>&1 | head -1)"
ok "code-server responds: $("$CODE_SERVER_BIN" --version 2>/dev/null | head -1)"

# --- shared app library -----------------------------------------------------------------------
# The interactive apps share the same startup, loading EESSI and starting a server under the
# path the portal proxies. The library lives on the VM and not inside each app, so a single
# copy keeps five files from diverging.
msg "installing the shared app library"
install -m 644 "${HERE}/ood-app-lib.sh" /etc/one-ondemand/ood-app-lib.sh
bash -n /etc/one-ondemand/ood-app-lib.sh || die "ood-app-lib.sh is not valid bash"
ok "/etc/one-ondemand/ood-app-lib.sh installed"

# --- Slurm node and the elasticity publisher --------------------------------------------------
# slurmd registers this VM with the controller of the portal at boot (configure.sh), and the
# publisher tells OneGate what the cluster is waiting for, so OneFlow grows the role, and
# drains this worker before OneFlow removes it. The packages come with the common image
# (appliance/install.sh); here the spool directory and the units.
#
# The publisher unit is enabled here but not started, because in the golden image systemd
# starts it when the VM boots. It is deliberately not ordered after one-context.service,
# because a START_SCRIPT runs inside one-context and a unit ordered after it would wait for
# the script that is starting it, leaving contextualization hung. Checked on 8 September 2026.
# The leave unit does nothing at start and, when the VM shuts down, deletes the node from the
# controller while slurmd and the network are still up.
msg "installing the Slurm node pieces and the elasticity publisher"
install -d -m 700 -o slurm -g slurm /var/spool/slurmd
# A configless node fetches its configuration from the portal when it starts. If the portal
# is still booting, as after a host outage, the package unit fails once and stays down, so
# retry until the controller answers. Seen on 17 September 2026 on a worker resumed before
# its portal.
install -d /etc/systemd/system/slurmd.service.d
cat > /etc/systemd/system/slurmd.service.d/one-ondemand.conf <<'UNIT'
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=on-failure
RestartSec=20
UNIT
install -m 644 "${HERE}/onegate-lib.sh" /etc/one-ondemand/onegate-lib.sh
bash -n /etc/one-ondemand/onegate-lib.sh || die "onegate-lib.sh is not valid bash"
install -m 755 "${HERE}/slurm-elastic.sh" /usr/local/bin/ood-slurm-elastic.sh
bash -n /usr/local/bin/ood-slurm-elastic.sh || die "slurm-elastic.sh is not valid bash"
cat > /etc/systemd/system/ood-slurm-elastic.service <<'UNIT'
[Unit]
Description=Publish the Slurm load of the Open OnDemand pool to OneGate
After=network-online.target slurmd.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/ood-slurm-elastic.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/ood-slurm-leave.service <<'UNIT'
[Unit]
Description=Remove this VM from the Slurm controller when it shuts down
After=network-online.target slurmd.service munge.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/bin/ood-slurm-elastic.sh --leave

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable ood-slurm-elastic.service ood-slurm-leave.service >/dev/null 2>&1 \
    || die "could not enable the elasticity publisher"
ok "slurmd $(dpkg-query -W -f='${Version}' slurmd 2>/dev/null) in the image, publisher and leave units enabled at boot"

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
EESSI_VERSION=${EESSI_VERSION}
TURBOVNC_VERSION=${TURBOVNC_VERSION}
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
cat > "${SRC}/worker/slurm-elastic.sh" <<'ONEOND_WORKER_SLURM_ELASTIC_SH_'
#!/usr/bin/env bash
# Publishes the load of the Slurm cluster to OneGate so OneFlow can grow and shrink the pool,
# and drains this worker before OneFlow removes it.
#
# OneFlow evaluates a policy on the AVERAGE of an attribute across the VMs of the role, and
# a value on the portal is invisible to the policies of the worker role, so every worker
# publishes the cluster figures. They are the same on all of them, so the average is the
# figure.
#
# SLURM_PENDING is the number of jobs waiting for resources that this role could give them.
# One pending job adds one worker (policy SLURM_PENDING > 0). A job nobody can run, for a
# GPU on a pool without one, is refused at submit by Slurm, and a job that waits for
# another role's feature is not counted, so the pool never grows for something a new
# worker could not serve.
#
# OLDEST_IDLE retires one worker at a time. OneFlow always removes the oldest VM of the
# role and does not drain it, so the only safe question is whether the oldest worker is
# empty and will stay empty. Each worker publishes IDLE_SECONDS, the time since its last
# job ended. When this worker is the oldest of its role, nothing is pending and it has been
# idle for ONEAPP_WORKER_IDLE_SECONDS, it drains its own node, so Slurm places nothing
# more on it, and publishes OLDEST_IDLE=1 while it is drained and empty. The other workers
# publish the OLDEST_IDLE of the oldest VM, read through OneGate, so the role average is 1
# only when the VM OneFlow is about to remove holds no job and accepts none. The last
# worker of the role never drains, and a drain that OneFlow does not act on within
# ONEAPP_WORKER_DRAIN_SECONDS, or that a pending job makes pointless, is undone.
#
# A node that Slurm has deleted never comes back on its own, so when this worker is missing
# from sinfo while munge and the controller answer, slurmd is restarted and registers again.
#
# With --leave, run by systemd when the VM shuts down, the node is deleted from the
# controller so a terminated VM does not linger as a down node; the reconciler on the portal
# covers a VM that dies without shutting down.
#
# /etc/one-ondemand/onegate-lib.sh resolves the OneGate endpoint and explains why the
# injected one is not trusted, and the boot configuration shares that same library.
set -u

STATE=/run/ood-slurm-elastic
ONEGATE_LIB="${ONEGATE_LIB:-/etc/one-ondemand/onegate-lib.sh}"
# shellcheck source=/dev/null
. "$ONEGATE_LIB" || { echo "${ONEGATE_LIB} is missing" >&2; exit 1; }

log() { logger -t ood-slurm-elastic "$*"; echo "$*" >&2; }
# Every Slurm client call is bounded: with the controller down each one fails after 9 s
# (measured 16 September 2026), and nothing here may hang on it.
slurm() { timeout 20 "$@" 2>/dev/null; }
NODE="$(hostname -s)"

# --leave: this VM is shutting down, so its node leaves the cluster if it holds no job.
if [[ "${1:-}" == "--leave" ]]; then
    grep -q -- '--conf-server' /etc/default/slurmd 2>/dev/null || exit 0
    if [[ -z "$(slurm squeue -h -w "$NODE" -o %i)" ]]; then
        slurm scontrol delete NodeName="$NODE" && log "node ${NODE} deleted from the controller, the VM is shutting down"
    else
        log "node ${NODE} keeps its jobs, the reconciler on the portal removes it later"
    fi
    exit 0
fi

install -d -m 755 "$STATE"

if ! onegate_ready; then
    log "no OneGate endpoint answers, tried '${ONEGATE_ENDPOINT:-none}' and the default gateway"
    exit 1
fi
printf '%s\n' "$ONEGATE_ENDPOINT" > "${STATE}/endpoint"
log "publishing to ${ONEGATE_ENDPOINT}"

# onegate_ready loaded the context environment, where the advanced attributes arrive.
IDLE_THRESHOLD="${ONEAPP_WORKER_IDLE_SECONDS:-600}"
[[ "$IDLE_THRESHOLD" =~ ^[0-9]+$ ]] || IDLE_THRESHOLD=600
DRAIN_TIMEOUT="${ONEAPP_WORKER_DRAIN_SECONDS:-600}"
[[ "$DRAIN_TIMEOUT" =~ ^[0-9]+$ ]] || DRAIN_TIMEOUT=600
DRAIN_REASON="one-ondemand scale-down"
log "the oldest worker drains after ${IDLE_THRESHOLD}s without a job and resumes after ${DRAIN_TIMEOUT}s if it is not removed"

# The role this VM plays in the service, "worker" or a "worker_<size>" role, which OneFlow
# records in the user template of the VM. Outside a service it defaults to worker.
ROLE_NAME="$(onegate_call vm show --json 2>/dev/null | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin)["VM"].get("USER_TEMPLATE") or {}).get("ROLE_NAME", "worker"))
except Exception:
    print("worker")
')"
log "role ${ROLE_NAME}, node ${NODE}"

# role_view: five values from the service document, "oldest|count|oldest_idle|min|state":
# the VM id of the oldest worker of this role, how many VMs the role has, the OLDEST_IDLE
# that oldest VM published (0 when absent), the min_vms of the role and the numeric state of
# the service (2 is RUNNING). Empty outside a service.
role_view() {
    onegate_call service show --json --extended 2>/dev/null | python3 -c '
import json, sys
role = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
svc = d.get("SERVICE", {})
oldest, count, minimum = None, 0, 1
for r in svc.get("roles", []):
    if r.get("name") != role:
        continue
    minimum = int(r.get("min_vms") or 1)
    for n in r.get("nodes", []):
        vm = (n.get("vm_info") or {}).get("VM", {})
        try:
            vid = int(vm.get("ID"))
        except (TypeError, ValueError):
            continue
        count += 1
        if oldest is None or vid < oldest[0]:
            oldest = (vid, vm.get("USER_TEMPLATE") or {})
if oldest is None:
    sys.exit(0)
print("%d|%d|%s|%d|%s" % (oldest[0], count, oldest[1].get("OLDEST_IDLE", "0"), minimum, svc.get("state", "")))
' "$ROLE_NAME"
}

# portal_addr: the address of the portal on the compute network, from the service document,
# the last NIC of the portal VM (the roles get the management network first and the compute
# network second). Empty outside a service or when OneGate does not answer.
portal_addr() {
    onegate_call service show --json --extended 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("SERVICE", {}).get("roles", []):
    if r.get("name") != "portal":
        continue
    for n in r.get("nodes", []):
        nics = ((n.get("vm_info") or {}).get("VM", {})).get("TEMPLATE", {}).get("NIC", [])
        nics = [nics] if isinstance(nics, dict) else nics
        ips = [nic.get("IP") for nic in nics if nic.get("IP")]
        if ips:
            print(ips[-1])
            sys.exit(0)
'
}

# follow_portal: a portal that OneFlow replaces usually gets another address, and this
# worker pinned the old one at boot in /etc/hosts (ood-portal, which slurmd and the
# controller address use) and in sssd. When the service document names another address,
# both are rewritten and sssd and slurmd restarted, so the node registers with the new
# controller and the users keep resolving. Nothing changes when OneGate is silent.
follow_portal() {
    local current new
    current="$(awk '/# one-ondemand portal$/ {print $1}' /etc/hosts | head -1)"
    new="$(portal_addr)"
    [[ -n "$new" && -n "$current" && "$new" != "$current" ]] || return 0
    log "the portal moved from ${current} to ${new}, following it"
    sed -i "s/^${current} ood-portal # one-ondemand portal$/${new} ood-portal # one-ondemand portal/" /etc/hosts
    sed -i "s#^ldap_uri = ldap://${current}\$#ldap_uri = ldap://${new}#" /etc/sssd/sssd.conf 2>/dev/null
    systemctl restart sssd 2>/dev/null
    systemctl restart slurmd
}

# pending_jobs: jobs waiting for resources this role could provide. The reason filter keeps
# the jobs that wait for a free node, including the ones that wait because every node is
# drained or down (ReqNodeNotAvail, which squeue follows with the node list), and leaves out
# jobs held by a limit or a dependency; the feature filter leaves out jobs that ask for
# another worker role.
pending_jobs() {
    slurm squeue -h -t PD -o '%r|%f' | awk -F'|' -v role="$ROLE_NAME" '
        $1 ~ /^(Resources|Priority|None|ReqNodeNotAvail)/ && ($2 == "" || $2 == "(null)" || $2 == role) { n++ }
        END { print n + 0 }'
}

# node_state: the state of this node as sinfo prints it, empty when the controller does
# not list it or does not answer. node_reason: why it is drained, when it is.
node_state() { slurm sinfo -h -n "$NODE" -o '%T' | head -1; }
node_reason() { slurm sinfo -h -n "$NODE" -o '%E' | head -1; }

# healthy: 1 when what a session needs is in place, the home over NFS when the worker was
# given one, the EESSI catalogue when it was configured, munge and slurmd. The controller
# is not part of it, because a controller outage must not read as every worker broken.
healthy() {
    local failed=""
    if grep -q " /home nfs4 " /etc/fstab 2>/dev/null; then
        findmnt -n -t nfs4 /home >/dev/null 2>&1 || failed="${failed} nfs"
    fi
    if [[ -f /etc/cvmfs/default.local ]]; then
        [[ -d /cvmfs/software.eessi.io/versions ]] || failed="${failed} cvmfs"
    fi
    if grep -q -- '--conf-server' /etc/default/slurmd 2>/dev/null; then
        munge -n 2>/dev/null | unmunge >/dev/null 2>&1 || failed="${failed} munge"
        systemctl is-active --quiet slurmd || failed="${failed} slurmd"
    fi
    # The state goes in a file because this runs in a command substitution, so a variable
    # would not survive the call and every cycle would log the same thing.
    local last; last="$(cat "${STATE}/unhealthy" 2>/dev/null || true)"
    if [[ -n "$failed" ]]; then
        [[ "$failed" == "$last" ]] || log "unhealthy:${failed}"
        printf '%s' "$failed" > "${STATE}/unhealthy"
        printf '0'
    else
        [[ -z "$last" ]] || log "healthy again"
        rm -f "${STATE}/unhealthy"
        printf '1'
    fi
}

# publish KEY=VALUE...: every attribute is tried, and the call fails at the end if one was
# refused, so a bad value never keeps the ones the policies read from reaching OneGate. A
# value must carry no comma and no "=", which the OneGate client and server split on.
publish() {
    local kv rc=0
    for kv in "$@"; do
        onegate_call vm update --data "$kv" >/dev/null 2>&1 || { rc=1; log "OneGate refused ${kv%%=*}"; }
    done
    return $rc
}

# A worker without a cluster, the standalone VM the marketplace harness boots, publishes
# its health and nothing else. The package ships /etc/default/slurmd with the option
# commented out, so the mark of a configured node is the controller address in it.
if ! grep -q -- '--conf-server' /etc/default/slurmd 2>/dev/null; then
    log "no Slurm node configured on this VM, publishing HEALTHY only"
    while true; do
        publish "HEALTHY=$(healthy)" || log "publish failed against ${ONEGATE_ENDPOINT}"
        sleep 30
    done
fi

# Initial value as soon as it starts, so a new VM is not missing from the average OneFlow
# evaluates before it has published anything. A worker that has never had a job counts its
# idle time from here.
last_busy=$(date +%s)
last_restart=0
drain_since=0
resume_at=0
# OneFlow reads OLDEST_IDLE every 60 s and acts two readings later, so a drain that this
# worker undoes stays in place this long after it stops publishing 1, or OneFlow could
# remove the VM right after a session landed on it.
RESUME_GRACE=150
publish "SLURM_PENDING=0" "OLDEST_IDLE=0" "IDLE_SECONDS=0" "ACTIVE_SESSIONS=0" "HEALTHY=$(healthy)" \
    && log "initial values published"

while true; do
    now=$(date +%s)
    follow_portal
    state="$(node_state)"
    # Missing from the controller while munge works (the node was deleted, or slurmd lost
    # it), or slurmd itself is down: only a restart registers the node again. Once per five
    # minutes at most.
    if { [[ -z "$state" ]] || ! systemctl is-active --quiet slurmd; } \
            && munge -n 2>/dev/null | unmunge >/dev/null 2>&1 \
            && slurm sinfo -h >/dev/null && (( now - last_restart > 300 )); then
        log "node ${NODE} is not registered or slurmd is down, restarting slurmd"
        systemctl restart slurmd && last_restart=$now
        sleep 5
        state="$(node_state)"
    fi

    jobs="$(slurm squeue -h -w "$NODE" -t R -o %i | grep -c .)"
    (( jobs > 0 )) && last_busy=$now
    idle_secs=$(( now - last_busy ))
    pending="$(pending_jobs)"
    users="$(slurm squeue -h -w "$NODE" -t R -o '%u:%S' | paste -sd';' -)"
    idle_nodes="$(slurm sinfo -h -t idle -o %D | head -1)"
    alloc_nodes="$(slurm sinfo -h -t alloc,mixed -o %D | head -1)"

    # --- the drain of the oldest worker ------------------------------------------------
    oldest_idle=0
    IFS='|' read -r oldest count their_oldest_idle min_vms svc_state < <(role_view)
    if [[ "$state" == drain* ]] && [[ "$(node_reason)" == "$DRAIN_REASON" ]]; then
        # This worker drained itself. Putting it back needs only Slurm, so it happens even
        # when the service document is unavailable, and it happens in two steps: first
        # OLDEST_IDLE stops being 1, then after RESUME_GRACE the node takes jobs again, so
        # a removal OneFlow already decided lands on a node that is still empty.
        if (( jobs == 0 )); then
            if (( resume_at > 0 )); then
                if (( now >= resume_at )); then
                    slurm scontrol update NodeName="$NODE" State=IDLE \
                        && log "node ${NODE} back in service"
                    resume_at=0; drain_since=0; last_busy=$now
                fi
            elif (( pending > 0 )) || (( now - drain_since > DRAIN_TIMEOUT )); then
                resume_at=$(( now + RESUME_GRACE ))
                log "node ${NODE} leaves the drain in ${RESUME_GRACE}s, $( (( pending > 0 )) && echo "${pending} jobs pending" || echo "not removed after ${DRAIN_TIMEOUT}s")"
            else
                [[ "${oldest:-}" == "${VMID:-none}" ]] && oldest_idle=1
            fi
        fi
    elif [[ "${oldest:-}" == "${VMID:-none}" ]]; then
        # This worker is the one OneFlow removes next. It drains only from a working state,
        # so a node an operator drained or that is down is left alone, only while OneFlow
        # would act (the service RUNNING and the role above its minimum) and only when
        # nothing waits for a node.
        if [[ "$state" == idle* || "$state" == mixed* ]] && [[ "${svc_state:-}" == "2" ]] \
                && (( count > ${min_vms:-1} && jobs == 0 && pending == 0 && idle_secs > IDLE_THRESHOLD )); then
            if slurm scontrol update NodeName="$NODE" State=DRAIN Reason="$DRAIN_REASON"; then
                drain_since=$now; resume_at=0
                log "node ${NODE} drained, idle for ${idle_secs}s and the oldest of ${count} workers of ${ROLE_NAME}"
            fi
        fi
    else
        [[ "${their_oldest_idle:-0}" == "1" ]] && oldest_idle=1
    fi

    if publish "SLURM_PENDING=${pending}" "OLDEST_IDLE=${oldest_idle}" "HEALTHY=$(healthy)" \
               "IDLE_SECONDS=${idle_secs}" "ACTIVE_SESSIONS=${jobs}" "SLURM_IDLE_NODES=${idle_nodes:-0}" \
               "SLURM_ALLOC_NODES=${alloc_nodes:-0}" "SESSION_USERS=${users:--}"; then
        log "SLURM_PENDING=${pending} SLURM_IDLE_NODES=${idle_nodes:-0} SLURM_ALLOC_NODES=${alloc_nodes:-0} ACTIVE_SESSIONS=${jobs} IDLE_SECONDS=${idle_secs} OLDEST_IDLE=${oldest_idle} state=${state:-unregistered}"
    else
        log "publish failed against ${ONEGATE_ENDPOINT}"
    fi
    sleep 30
done
ONEOND_WORKER_SLURM_ELASTIC_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/slurm-task-epilog.sh" <<'ONEOND_WORKER_SLURM_TASK_EPILOG_SH_'
#!/usr/bin/env bash
# Task epilog of the Slurm cluster, run as the user on the worker after each task. It removes
# the runtime directory the task prolog created.
rm -rf "${TMPDIR:-/tmp}/ood-runtime-${SLURM_JOB_ID:-none}"
ONEOND_WORKER_SLURM_TASK_EPILOG_SH_

install -d -m 755 "${SRC}/worker"
cat > "${SRC}/worker/slurm-task-prolog.sh" <<'ONEOND_WORKER_SLURM_TASK_PROLOG_SH_'
#!/usr/bin/env bash
# Task prolog of the Slurm cluster, run as the user on the worker before each task. Its
# standard output sets the environment of the task.
#
# A batch job submitted with --export=NONE, which is what Open OnDemand does, gets the login
# environment of the user, which slurmd builds with `su -` on the worker. That su opens a
# logind session, pam_systemd starts the user manager with its D-Bus user bus, and the
# session closes at once, so logind stops that manager ten seconds later and kills the bus.
# A desktop that connected to it dies with it. The task therefore gets a runtime directory
# of its own, and no bus address, so D-Bus starts a private bus that lives as long as the
# job. The task epilog removes the directory.
dir="${TMPDIR:-/tmp}/ood-runtime-${SLURM_JOB_ID:-$$}"
mkdir -p -m 700 "$dir"
echo "export XDG_RUNTIME_DIR=${dir}"
echo "unset DBUS_SESSION_BUS_ADDRESS"
ONEOND_WORKER_SLURM_TASK_PROLOG_SH_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/form.yml.erb" <<'ONEOND_APPS_CODE_SERVER_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a session no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every session is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the session. No other session shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the session. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the session, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the session."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops when this time expires."
ONEOND_APPS_CODE_SERVER_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/info.html.erb" <<'ONEOND_APPS_CODE_SERVER_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_CODE_SERVER_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/manifest.yml" <<'ONEOND_APPS_CODE_SERVER_MANIFEST_YML_'
---
name: VS Code
category: Interactive Apps
subcategory: Development
role: batch_connect
description: |
  Launches Visual Studio Code in the browser on a worker of the service. The editor opens
  your home directory, shared over NFS with the file browser and with every other
  session, and its terminal runs on the worker that hosts the session.
ONEOND_APPS_CODE_SERVER_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/code-server"
cat > "${SRC}/apps/code-server/submit.yml.erb" <<'ONEOND_APPS_CODE_SERVER_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the session script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
batch_connect:
  template: "basic"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the session, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
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
# Sourced by the Slurm job on the worker, before the session script.
#
# set_host (clusters.d/slurm.yml) has already set host to the private IP of the VM, the
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
# Visual Studio Code in the browser, as a Slurm job on a worker.
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
cat > "${SRC}/apps/cpp-notebook/form.yml.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a session no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every session is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the session. No other session shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the session. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the session, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the session."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops on its own when this time expires."
ONEOND_APPS_CPP_NOTEBOOK_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/info.html.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_CPP_NOTEBOOK_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/manifest.yml" <<'ONEOND_APPS_CPP_NOTEBOOK_MANIFEST_YML_'
---
name: C++ Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Runs a Jupyter notebook with the Cling C++ kernel on a worker of the service. You
  write and run C++ cell by cell without a compile step, which suits teaching and suits
  trying numerical code before it goes into a batch job.
ONEOND_APPS_CPP_NOTEBOOK_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/cpp-notebook"
cat > "${SRC}/apps/cpp-notebook/submit.yml.erb" <<'ONEOND_APPS_CPP_NOTEBOOK_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the session script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
batch_connect:
  template: "basic"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the session, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
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
# Sourced by the Slurm job on the worker, before the session script.
#
# set_host (clusters.d/slurm.yml) already set host to the private IP of the VM, the
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

install -d -m 755 "${SRC}/apps/desktop"
cat > "${SRC}/apps/desktop/form.yml.erb" <<'ONEOND_APPS_DESKTOP_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a desktop no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every desktop is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  # Seconds without a viewer after which the desktop ends, 0 meaning never; the vnc
  # template of Open OnDemand reads it. No resolution field: noVNC resizes the desktop to
  # the browser window.
  bc_vnc_idle: 0
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the desktop. No other desktop shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the desktop. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the desktop, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the desktop."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The desktop ends automatically when this time expires."
ONEOND_APPS_DESKTOP_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/desktop"
cat > "${SRC}/apps/desktop/info.html.erb" <<'ONEOND_APPS_DESKTOP_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_DESKTOP_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/desktop"
cat > "${SRC}/apps/desktop/manifest.yml" <<'ONEOND_APPS_DESKTOP_MANIFEST_YML_'
---
name: Xfce Desktop
category: Interactive Apps
subcategory: Desktops
role: batch_connect
icon: fa://desktop
description: |
  Launches a Linux desktop (Xfce) on a worker of the service and shows it in the browser
  through noVNC. A terminal on the desktop has the EESSI software catalogue available
  with module load, and the desktop opens the same home directory as the notebooks.
ONEOND_APPS_DESKTOP_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/desktop"
cat > "${SRC}/apps/desktop/submit.yml.erb" <<'ONEOND_APPS_DESKTOP_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the desktop script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
# The vnc template of Open OnDemand starts a VNC server (TurboVNC on the worker), runs the
# session script under its display and bridges the display to the browser with websockify.
# The portal serves noVNC itself and proxies the websocket through /rnode.
batch_connect:
  template: "vnc"
  websockify_cmd: "/usr/bin/websockify"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the desktop, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
<%- end -%>
ONEOND_APPS_DESKTOP_SUBMIT_YML_ERB_

install -d -m 755 "${SRC}/apps/desktop/template"
cat > "${SRC}/apps/desktop/template/script.sh.erb" <<'ONEOND_APPS_DESKTOP_TEMPLATE_SCRIPT_SH_ERB_'
#!/usr/bin/env bash
# Desktop session for the slurm target. The vnc template of Open OnDemand runs this script
# with DISPLAY pointing at the TurboVNC server it started, as a Slurm job on a worker.
# Xfce comes from the worker packages. The Xfce setup lines follow the desktops/xfce.sh of the stock
# bc_desktop application of Open OnDemand. The EESSI catalogue is not initialised here:
# the terminals are login shells, and /etc/profile.d/eessi-lazy.sh on the VM loads it on
# the first module call, which keeps the distribution tools first in PATH.
cd "${HOME}"

# The user's login shell, for the terminals opened on the desktop.
export SHELL="$(getent passwd "$USER" | cut -d: -f7)"

# Remove any preconfigured monitors
if [[ -f "${HOME}/.config/monitors.xml" ]]; then
    mv "${HOME}/.config/monitors.xml" "${HOME}/.config/monitors.xml.bak"
fi

# Copy over the default panel if it does not exist, otherwise Xfce prompts the user
PANEL_CONFIG="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
if [[ ! -e "${PANEL_CONFIG}" ]]; then
    mkdir -p "$(dirname "${PANEL_CONFIG}")"
    cp "/etc/xdg/xfce4/panel/default.xml" "${PANEL_CONFIG}"
fi

# Disable startup services that make no sense in a VNC session
xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false
xfconf-query -c xfce4-session -p /startup/gpg-agent/enabled -n -t bool -s false

# Disable useless services on autostart
AUTOSTART="${HOME}/.config/autostart"
rm -fr "${AUTOSTART}"
mkdir -p "${AUTOSTART}"
for service in "pulseaudio" "rhsm-icon" "spice-vdagent" "tracker-extract" "tracker-miner-apps" "tracker-miner-user-guides" "xfce4-power-manager" "xfce-polkit"; do
    echo -e "[Desktop Entry]\nHidden=true" > "${AUTOSTART}/${service}.desktop"
done

# Run the Xfce terminal as a login shell, which sets a proper TERM and reads the profile
TERM_CONFIG="${HOME}/.config/xfce4/terminal/terminalrc"
if [[ ! -e "${TERM_CONFIG}" ]]; then
    mkdir -p "$(dirname "${TERM_CONFIG}")"
    sed 's/^ \{4\}//' > "${TERM_CONFIG}" << EOL
    [Configuration]
    CommandLoginShell=TRUE
EOL
else
    sed -i \
        '/^CommandLoginShell=/{h;s/=.*/=TRUE/};${x;/^$/{s//CommandLoginShell=TRUE/;H};x}' \
        "${TERM_CONFIG}"
fi

# Start the desktop, and block until the user logs out of it
echo "Launching the Xfce desktop..."
xfce4-session
echo "The desktop ended with status $?"
ONEOND_APPS_DESKTOP_TEMPLATE_SCRIPT_SH_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/form.yml.erb" <<'ONEOND_APPS_JUPYTER_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a session no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every session is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the session. No other session shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the session. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the session, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the session."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session ends automatically when this time expires."
ONEOND_APPS_JUPYTER_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/info.html.erb" <<'ONEOND_APPS_JUPYTER_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_JUPYTER_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/manifest.yml" <<'ONEOND_APPS_JUPYTER_MANIFEST_YML_'
---
name: Jupyter Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Launches a JupyterLab notebook on a worker of the service, with the Python from the EESSI
  software catalogue. The notebook runs on a worker rather than on the portal,
  and it opens the home directory the portal file browser shows.
ONEOND_APPS_JUPYTER_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/jupyter"
cat > "${SRC}/apps/jupyter/submit.yml.erb" <<'ONEOND_APPS_JUPYTER_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the session script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
batch_connect:
  template: "basic"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the session, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
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
# Sourced by the Slurm job on the worker, before the session script.
#
# set_host (clusters.d/slurm.yml) already set host to the private IP of the VM, the
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
# Session script for the slurm target. It runs as a Slurm job on a worker, fenced to the
# cores and the memory the form asked for. Jupyter comes from the EESSI
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
cat > "${SRC}/apps/octave/form.yml.erb" <<'ONEOND_APPS_OCTAVE_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a session no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every session is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the session. No other session shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the session. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the session, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the session."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session ends automatically when this time expires."
ONEOND_APPS_OCTAVE_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/info.html.erb" <<'ONEOND_APPS_OCTAVE_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_OCTAVE_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/manifest.yml" <<'ONEOND_APPS_OCTAVE_MANIFEST_YML_'
---
name: Octave Notebook
category: Interactive Apps
subcategory: Notebooks
role: batch_connect
description: |
  Launches a Jupyter notebook with the Octave kernel on a worker of the service. Octave is a
  free alternative to MATLAB and comes from the EESSI software catalogue. The notebook
  runs on a worker and opens the home directory the portal file browser shows.
ONEOND_APPS_OCTAVE_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/octave"
cat > "${SRC}/apps/octave/submit.yml.erb" <<'ONEOND_APPS_OCTAVE_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the session script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
batch_connect:
  template: "basic"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the session, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
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
# Sourced by the Slurm job on the worker, before the session script.
#
# set_host (clusters.d/slurm.yml) already set host to the private IP of the VM, the
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
cat > "${SRC}/apps/rstudio/form.yml.erb" <<'ONEOND_APPS_RSTUDIO_FORM_YML_ERB_'
---
<%-
  # What the forms may ask for comes from the cluster itself. The reconciler on the portal
  # writes the largest registered node (cores, memory, GPUs) and the worker roles of the
  # service, so the form cannot ask for a session no node could run, the GPU field appears
  # only when a node has one, and the size field only when the service has more than one
  # worker role.
  require 'json'
  shape = (JSON.parse(File.read('/var/lib/ood-slurm/shape')) rescue {})
  max_cores  = [shape['cpus'].to_i, 1].max
  max_mem_gb = [shape['mem_mb'].to_i / 1024, 1].max
  max_gpus   = shape['gpus'].to_i
  roles  = (File.readlines('/var/lib/ood-slurm/roles').map(&:strip).reject(&:empty?) rescue [])
  labels = { "worker" => "Standard" }
  size_options = roles.sort.map { |r| [labels.fetch(r) { r.sub(/^worker_?/, "").capitalize }, r] }
-%>
# Every session is a job of the Slurm cluster of the service, so it gets the cores and the
# memory it asks for and nothing else shares them.
cluster:
  - "slurm"
form:
  - num_cores
  - mem_gb
<%- if max_gpus > 0 -%>
  - num_gpus
<%- end -%>
  - num_hours
<%- if size_options.size > 1 -%>
  - worker_size
<%- end -%>
attributes:
  num_cores:
    widget: number_field
    label: "Cores"
    value: 1
    min: 1
    max: <%= max_cores %>
    step: 1
    help: "Cores reserved for the session. No other session shares them."
  mem_gb:
    widget: number_field
    label: "Memory (GB)"
    value: <%= [2, max_mem_gb].min %>
    min: 1
    max: <%= max_mem_gb %>
    step: 1
    help: "Memory reserved for the session. A process that grows past it is stopped."
<%- if max_gpus > 0 -%>
  num_gpus:
    widget: number_field
    label: "GPUs"
    value: 0
    min: 0
    max: <%= max_gpus %>
    step: 1
    help: "GPUs reserved for the session, on a worker that has them."
<%- end -%>
<%- if size_options.size > 1 -%>
  worker_size:
    widget: select
    label: "Worker size"
    help: "Which kind of worker runs the session."
    options:
<%- size_options.each do |label, role| -%>
      - ["<%= label %>", "<%= role %>"]
<%- end -%>
<%- end -%>
  num_hours:
    widget: number_field
    label: "Session hours"
    value: 1
    min: 1
    max: 12
    step: 1
    help: "The session stops when this time expires."
ONEOND_APPS_RSTUDIO_FORM_YML_ERB_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/info.html.erb" <<'ONEOND_APPS_RSTUDIO_INFO_HTML_ERB_'
<%#- Shown on the session card, from submission until the session ends. The card title
    carries the Slurm job id, so this panel prints the target and, once the job runs, the
    node. The file is evaluated against the session, so cluster_id, job_id and info are its
    attributes, while view.html.erb is evaluated against the connection information. The
    target title comes from its definition in clusters.d. -%>
<%-
  target_cluster = (OodAppkit.clusters[cluster_id.to_s.to_sym] rescue nil)
  target = target_cluster ? target_cluster.metadata.title.to_s : cluster_id.to_s
  node = (info.allocated_nodes.map(&:name).reject { |n| n.to_s.empty? }.join(", ") rescue "")
-%>
<p class="mb-2"><strong>Runs on:</strong> <%= target %>, job <%= job_id %><%= node.empty? ? "" : " on #{node}" %></p>
ONEOND_APPS_RSTUDIO_INFO_HTML_ERB_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/manifest.yml" <<'ONEOND_APPS_RSTUDIO_MANIFEST_YML_'
---
name: RStudio Server
category: Interactive Apps
subcategory: Development
role: batch_connect
description: |
  Launches RStudio Server on a worker of the service, with R from the EESSI software
  catalogue. Your home directory is the same one the file browser shows, shared over
  NFS with every other session.
ONEOND_APPS_RSTUDIO_MANIFEST_YML_

install -d -m 755 "${SRC}/apps/rstudio"
cat > "${SRC}/apps/rstudio/submit.yml.erb" <<'ONEOND_APPS_RSTUDIO_SUBMIT_YML_ERB_'
---
# The slurm adapter submits the session script with sbatch, and Slurm starts it on a worker
# with the cores and the memory the form asked for, fenced by cgroups, for the session time.
# The script is the one generated by template/before.sh.erb, script.sh.erb and after.sh.erb.
batch_connect:
  template: "basic"
script:
  # to_f, not to_i, so a fraction of an hour does not truncate to zero.
  wall_time: "<%= (num_hours.to_f * 3600).round %>"
  native:
    - "--nodes=1"
    - "--ntasks=1"
    - "--cpus-per-task=<%= num_cores.to_i %>"
    - "--mem=<%= mem_gb.to_i %>G"
    # The browser connection points at the node that started the session, so it is never
    # requeued elsewhere.
    - "--no-requeue"
<%- if defined?(num_gpus) && num_gpus.to_i > 0 -%>
    - "--gres=gpu:<%= num_gpus.to_i %>"
<%- end -%>
<%- if defined?(worker_size) && !worker_size.to_s.empty? -%>
    - "--constraint=<%= worker_size %>"
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
# Sourced by the Slurm job on the worker, before the session script.
#
# set_host (clusters.d/slurm.yml) has already set host to the private IP of the VM, the
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
# RStudio Server as a Slurm job on a worker, with R from EESSI.
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
