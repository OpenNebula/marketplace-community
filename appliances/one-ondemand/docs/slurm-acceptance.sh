#!/usr/bin/env bash
# Acceptance checks of the Slurm cluster inside a running Open OnDemand service.
#
# Runs on the OpenNebula front-end as a user that can run oneflow and onevm and can open
# an SSH session as root on the VMs of the service (the VM template injects the SSH key of
# the OpenNebula user through SSH_PUBLIC_KEY, so oneadmin can). It submits real jobs as the
# first initial user of the portal and prints one PASS or FAIL line per check, and it ends
# with a non-zero status when any check failed.
#
# Checks: the controller units and the state mount on the portal, the accounting cluster,
# every worker of the service registered as a node with its role as feature, the
# attributes the workers publish to OneGate, a job that runs and is accounted, cores that
# are not shared, a GPU request refused on a pool without GPUs, and, with --scale, a worker
# added with oneflow scale that registers on its own and a worker removed whose node
# disappears from the cluster.
#
# Usage:  tests/slurm-acceptance.sh <service id> [--scale]

set -u
SERVICE="${1:?service id}"; SCALE="${2:-}"
SSH="sudo -u oneadmin ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o LogLevel=ERROR"
failed=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failed=1; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }

doc() { oneflow show "$SERVICE" --json; }
role_vms() { doc | python3 -c '
import sys, json
b = json.load(sys.stdin)["DOCUMENT"]["TEMPLATE"]["BODY"]
for r in b["roles"]:
    if r["name"] == sys.argv[1] or (sys.argv[1] == "worker*" and r["name"].startswith("worker")):
        for n in r.get("nodes", []):
            print(n["vm_info"]["VM"]["ID"])' "$1"; }
vm_ip() { onevm show "$1" --json | python3 -c '
import sys, json
n = json.load(sys.stdin)["VM"]["TEMPLATE"]["NIC"]; n = n if isinstance(n, list) else [n]
print(n[0]["IP"])'; }
vsh() { local vm="$1"; shift; $SSH "root@$(vm_ip "$vm")" "$@"; }
attr() { onevm show "$1" | sed -n "s/^${2}=\"\(.*\)\"$/\1/p" | head -1; }
# The checks that need a pipe run in a child shell, which needs the helpers too.
export SSH; export -f vm_ip vsh attr

portal="$(role_vms portal | head -1)"; storage="$(role_vms storage | head -1)"
mapfile -t workers < <(role_vms 'worker*')
[[ -n "$portal" && -n "$storage" && ${#workers[@]} -ge 1 ]] || { echo "service ${SERVICE} has no portal, storage or worker"; exit 1; }
user="$(vsh "$portal" 'sed -n "s/^export ONEAPP_AUTH_LOCAL_USERS=\"\([^ :]*\).*/\1/p" /var/run/one-context/one_env' 2>/dev/null)"
user="${user:-demo1}"
echo "service ${SERVICE}: portal ${portal}, storage ${storage}, workers ${workers[*]}, user ${user}"

# --- controller ------------------------------------------------------------------------------
check "munge, mariadb, slurmdbd and slurmctld active on the portal" \
    vsh "$portal" 'systemctl is-active --quiet munge mariadb slurmdbd slurmctld'
check "reconcile and backup timers active on the portal" \
    vsh "$portal" 'systemctl is-active --quiet ood-slurm-reconcile.timer ood-slurm-backup.timer'
check "controller state mounted from the storage VM" \
    vsh "$portal" 'findmnt -n -t nfs4 /var/lib/one-ondemand/slurm >/dev/null && test -s /var/lib/one-ondemand/slurm/state/clustername'
check "munge key kept on the storage export, root only" \
    vsh "$storage" 'test "$(stat -c %a%U /export/slurm/etc/munge.key)" = 600root'
check "cluster ood registered in the accounting" \
    vsh "$portal" 'sacctmgr -n list cluster | grep -q "^ *ood "'
check "SLURM_MUNGE_KEY published by the portal" bash -c "[[ -n \"$(attr "$portal" SLURM_MUNGE_KEY)\" ]]"
check "no ERROR attribute on any VM" bash -c "for v in $portal $storage ${workers[*]}; do [[ -z \"\$(onevm show \$v | grep '^ERROR=')\" ]] || exit 1; done"

# --- nodes -----------------------------------------------------------------------------------
nodes="$(vsh "$portal" 'sinfo -h -N -o "%N %T %c %m %f"')"
n_nodes="$(grep -c . <<<"$nodes")"
check "every worker registered as a node (${n_nodes} of ${#workers[@]})" test "$n_nodes" -eq "${#workers[@]}"
check "every node idle or mixed with cores, memory and its role as feature" \
    bash -c "! grep -vE '^ood-worker-[0-9]+ (idle|mixed|allocated) [1-9][0-9]* [1-9][0-9]* worker' <<<'$nodes' | grep -q ."
for w in "${workers[@]}"; do
    check "worker ${w} publishes SLURM_NODENAME, SLURM_PENDING, OLDEST_IDLE and HEALTHY=1" \
        bash -c "[[ -n \"$(attr "$w" SLURM_NODENAME)\" && -n \"$(attr "$w" SLURM_PENDING)\" && -n \"$(attr "$w" OLDEST_IDLE)\" && \"$(attr "$w" HEALTHY)\" == 1 ]]"
done
check "reconciler wrote the roles and the shape for the forms" \
    vsh "$portal" 'grep -qx worker /var/lib/ood-slurm/roles && python3 -c "import json; d=json.load(open(\"/var/lib/ood-slurm/shape\")); assert d[\"cpus\"] > 0 and d[\"mem_mb\"] > 0"'

# --- jobs ------------------------------------------------------------------------------------
vsh "$portal" "/opt/one-ondemand/bin/pun_prehook --user ${user}" >/dev/null 2>&1
job="$(vsh "$portal" "su - ${user} -c 'sbatch --parsable -c 1 --mem=256M -t 5 --wrap \"hostname; sleep 15\"'" 2>/dev/null)"
if [[ "$job" =~ ^[0-9]+$ ]]; then
    for _ in $(seq 1 30); do st="$(vsh "$portal" "sacct -n -X -j $job -o State" 2>/dev/null | awk '{print $1}')"; [[ "$st" == COMPLETED ]] && break; sleep 3; done
    check "a job of ${user} runs on a worker and is accounted (job ${job}: ${st:-none})" test "${st:-}" = COMPLETED
    check "the job output lands in the home of ${user}" vsh "$portal" "grep -q '^ood-worker-' /home/${user}/slurm-${job}.out"
else
    fail "sbatch as ${user} (${job})"
fi
cores="$(awk 'NR==1 {print $3}' <<<"$nodes")"
j1="$(vsh "$portal" "su - ${user} -c 'sbatch --parsable -c ${cores} --mem=256M -t 5 -w $(awk 'NR==1 {print $1}' <<<"$nodes") --wrap \"sleep 60\"'" 2>/dev/null)"
j2="$(vsh "$portal" "su - ${user} -c 'sbatch --parsable -c ${cores} --mem=256M -t 5 -w $(awk 'NR==1 {print $1}' <<<"$nodes") --wrap \"sleep 60\"'" 2>/dev/null)"
sleep 6
check "two jobs of ${cores} cores on one node do not share it (second PENDING Resources)" \
    bash -c "[[ \"$(vsh "$portal" "squeue -h -j $j2 -o %T,%r" 2>/dev/null)\" == PENDING,Resources ]]"
vsh "$portal" "scancel $j1 $j2" >/dev/null 2>&1
check "a GPU request is refused at submit on a pool without GPUs" \
    bash -c "vsh $portal \"su - ${user} -c 'sbatch --parsable --gres=gpu:1 --wrap true'\" 2>&1 | grep -q 'Requested node configuration is not available'"
for _ in $(seq 1 10); do [[ -z "$(vsh "$portal" 'squeue -h' 2>/dev/null)" ]] && break; sleep 3; done
check "queue empty afterwards" bash -c "[[ -z \"\$(vsh $portal 'squeue -h' 2>/dev/null)\" ]]"

# --- the shared software directory -------------------------------------------------------------
# The operator builds GNU Hello from the recipe the image ships, and a job on a worker loads
# the module and runs it. The build takes a few minutes on a fresh directory.
check "shared software directory mounted on the portal and the workers" \
    bash -c "vsh $portal 'findmnt -n /opt/eessi' >/dev/null && vsh $(role_vms 'worker*' | head -1) 'findmnt -n /opt/eessi' >/dev/null"
check "ood-site-install builds hello from the shipped recipe" \
    bash -c "vsh $portal 'ood-site-install /opt/one-ondemand/config/easybuild/hello-2.12.1-GCCcore-14.3.0.eb' >/dev/null 2>&1"
check "a job on a worker loads the hello module built by the operator" \
    bash -c "vsh $portal \"su - ${user} -c 'srun -N1 -c1 --mem=256M -t 3 bash -lc \\\"module load hello && hello\\\"'\" 2>/dev/null | grep -q 'Hello, world'"

# --- elasticity by hand ----------------------------------------------------------------------
if [[ "$SCALE" == "--scale" ]]; then
    before=${#workers[@]}
    oneflow scale "$SERVICE" worker $(( before + 1 )) >/dev/null 2>&1
    for _ in $(seq 1 60); do [[ "$(oneflow show "$SERVICE" | awk '/SERVICE STATE/{print $4}')" == RUNNING ]] && [[ "$(role_vms 'worker*' | wc -l)" -eq $(( before + 1 )) ]] && break; sleep 10; done
    for _ in $(seq 1 30); do n="$(vsh "$portal" 'sinfo -h -N -t idle,mixed,allocated -o %N' 2>/dev/null | grep -c .)"; [[ "$n" -eq $(( before + 1 )) ]] && break; sleep 5; done
    check "a worker added with oneflow scale registers on its own (${n:-0} nodes)" test "${n:-0}" -eq $(( before + 1 ))
    newest="$(role_vms 'worker*' | sort -n | tail -1)"
    oneflow scale "$SERVICE" worker "$before" >/dev/null 2>&1
    for _ in $(seq 1 60); do [[ "$(oneflow show "$SERVICE" | awk '/SERVICE STATE/{print $4}')" == RUNNING ]] && [[ "$(role_vms 'worker*' | wc -l)" -eq "$before" ]] && break; sleep 10; done
    gone_node="$(comm -13 <(role_vms 'worker*' | sort) <(printf '%s\n' "${workers[@]}" "$newest" | sort) | head -1)"
    gone_name="$(attr "$gone_node" SLURM_NODENAME 2>/dev/null)"
    for _ in $(seq 1 30); do vsh "$portal" "sinfo -h -N -n ${gone_name:-none} -o %N" 2>/dev/null | grep -q . || break; sleep 5; done
    check "the removed worker (${gone_node}, ${gone_name:-?}) left the cluster" \
        bash -c "! vsh $portal 'sinfo -h -N -n ${gone_name:-none} -o %N' 2>/dev/null | grep -q ."
fi

(( failed == 0 )) && echo "all checks passed" || echo "some checks failed"
exit "$failed"
