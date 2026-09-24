#!/bin/bash
# CernVM-FS client for OneSlurm with the EESSI configuration and the site proxy.
#
# Usage. Encode it with `base64 -w0 oneslurm-start.sh` and put the result as START_SCRIPT_BASE64
# in the CONTEXT of the template_contents of BOTH roles, controller and worker, of a copy of the
# OneSlurm service template. Add a service input CVMFS_HTTP_PROXY with the proxy URL, for example
# http://192.168.100.155:3128. CVMFS_QUOTA_LIMIT (MB) is optional and defaults to 3000.
#
# OneSlurm starts slurmd in the net-90 context stage. This script runs later,
# in net-97, so a new worker is IDLE in Slurm before /cvmfs exists. A Slurm
# Prolog closes that gap. The controller ships the Prolog to every slurmd
# together with the configless config, so the Prolog is on a new worker
# before slurmd registers, and it holds each job until this script creates
# /run/cvmfs-ready on the worker. /run is empty after a reboot, so the check
# runs again on every boot.
set -eo pipefail
exec >>/var/log/cvmfs-start-script.log 2>&1
echo "=== $(date -Is) cvmfs start script"
[ -n "${CVMFS_HTTP_PROXY}" ] || . /run/one-context/one_env
if [ -z "${CVMFS_HTTP_PROXY}" ]; then echo "CVMFS_HTTP_PROXY not set in context, skipping"; exit 0; fi

# ---------------------------------------------------------------- controller
if [ -x /usr/sbin/slurmctld ]; then
  CONF=/etc/slurm/slurm.conf
  changed=no
  tmp=$(mktemp)
  cat > "$tmp" <<'PROLOG'
#!/bin/bash
# Slurm Prolog from the CernVM-FS start script. It holds a job on this node
# until the start script has checked /cvmfs on this boot. After 15 minutes,
# or when the start script failed, it exits 1, so Slurm drains the node and
# requeues the job.
[ -e /run/cvmfs-ready ] && exit 0
ENV_FILE=/run/one-context/one_env
if [ -r "$ENV_FILE" ] && ! grep -q '^export CVMFS_HTTP_PROXY="[^"]' "$ENV_FILE"; then
  exit 0  # this node does not use CernVM-FS
fi
logger -t cvmfs-prolog "job $SLURM_JOB_ID waits for CernVM-FS"
for _ in $(seq 1 450); do
  [ -e /run/cvmfs-failed ] && break
  sleep 2
  if [ -e /run/cvmfs-ready ]; then
    logger -t cvmfs-prolog "job $SLURM_JOB_ID released, CernVM-FS ready"
    exit 0
  fi
done
logger -t cvmfs-prolog "job $SLURM_JOB_ID requeued, CernVM-FS not ready"
exit 1
PROLOG
  if ! cmp -s "$tmp" /etc/slurm/cvmfs-prolog; then
    install -m 0755 "$tmp" /etc/slurm/cvmfs-prolog; changed=yes
  fi
  # OneSlurm rewrites slurm.conf on every boot, so add the block again each time.
  sed '/^# BEGIN cvmfs-start-script$/,/^# END cvmfs-start-script$/d' "$CONF" > "$tmp"
  if grep -qiE '^[[:space:]]*(Prolog|PrologFlags|SchedulerParameters)[[:space:]]*=' "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: $CONF already sets Prolog, PrologFlags or SchedulerParameters, merge by hand"
    exit 1
  fi
  cat >> "$tmp" <<'EOT'
# BEGIN cvmfs-start-script
Prolog=cvmfs-prolog
PrologFlags=Alloc,DeferBatch,ForceRequeueOnFail
SchedulerParameters=nohold_on_prolog_fail
# END cvmfs-start-script
EOT
  if ! cmp -s "$tmp" "$CONF"; then cat "$tmp" > "$CONF"; changed=yes; fi
  rm -f "$tmp"
  if [ "$changed" = yes ]; then
    for i in $(seq 1 10); do scontrol reconfigure && break; [ "$i" -lt 10 ] || exit 1; sleep 3; done
    echo "slurm.conf and Prolog updated, slurmctld reconfigured"
  fi
  echo "=== $(date -Is) done (controller)"
  exit 0
fi

# -------------------------------------------------------------------- worker
REPO=software.eessi.io
NODE=$(hostname -s)
export SLURM_CONF=/run/slurm/conf/slurm.conf
on_exit() {
  rc=$?
  [ "$rc" -eq 0 ] && return
  echo "=== $(date -Is) failed (exit $rc), draining $NODE"
  rm -f /run/cvmfs-ready; touch /run/cvmfs-failed
  timeout 15 scontrol update NodeName="$NODE" State=DRAIN Reason="cvmfs start script failed" || true
}
trap on_exit EXIT
rm -f /run/cvmfs-failed

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
APT="apt-get -o DPkg::Lock::Timeout=600 -y"
if ! dpkg -s cvmfs cvmfs-config-eessi >/dev/null 2>&1; then
  debs=$(mktemp -d); chmod 755 "$debs"
  wget -q -P "$debs" https://cvmrepo.s3.cern.ch/cvmrepo/apt/cvmfs-release-latest_all.deb
  wget -q -P "$debs" https://github.com/EESSI/filesystem-layer/releases/download/latest/cvmfs-config-eessi_latest_all.deb
  $APT install "$debs/cvmfs-release-latest_all.deb"
  $APT update
  $APT install cvmfs "$debs/cvmfs-config-eessi_latest_all.deb"
  rm -rf "$debs"
fi

# The worker disk is 10 GB with about 4.6 GB free, so the cache stays at 3000 MB.
config=$(printf 'CVMFS_CLIENT_PROFILE="single"\nCVMFS_HTTP_PROXY="%s"\nCVMFS_QUOTA_LIMIT=%s' \
  "$CVMFS_HTTP_PROXY" "${CVMFS_QUOTA_LIMIT:-3000}")
if [ "$config" != "$(cat /etc/cvmfs/default.local 2>/dev/null)" ]; then
  printf '%s\n' "$config" > /etc/cvmfs/default.local
  cvmfs_config setup
  if grep -q ' /cvmfs/' /proc/mounts; then cvmfs_config reload; fi
elif ! cvmfs_config chksetup >/dev/null 2>&1; then
  cvmfs_config setup
fi

for i in $(seq 1 30); do
  cvmfs_config probe "$REPO" && break
  [ "$i" -lt 30 ] || exit 1
  sleep 5
done
touch /run/cvmfs-ready
if scontrol show node "$NODE" 2>/dev/null | grep -q 'Reason=cvmfs start script failed'; then
  scontrol update NodeName="$NODE" State=RESUME
fi
echo "=== $(date -Is) done, /cvmfs/$REPO ready"
