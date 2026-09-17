# Open OnDemand

[Open OnDemand](https://openondemand.org/) gives HPC users a browser interface to a
cluster, with a file browser, a shell, job submission and interactive applications. This
appliance runs it on OpenNebula as a OneFlow service, with its own Slurm cluster on an
elastic pool of compute VMs behind the portal. A user signs in, presses a button and gets a
JupyterLab notebook, RStudio, Octave, a C++ notebook, VS Code or an Xfce desktop. It runs
as a Slurm job on a compute VM, with the cores and the memory the user requested. The
scientific software comes from the [EESSI](https://www.eessi.io/) catalogue, and the home
directory follows the user from session to session.

The service has three roles, all running from the same image. `ONEAPP_ROLE` decides at
boot which role a VM plays, and the OneFlow template sets it per role.

| Role | What it runs | Cardinality |
|---|---|---|
| `storage` | NFS server for the shared home and for the Slurm controller state, and site cache for the software catalogue | 1 |
| `portal` | Open OnDemand, its own LDAP directory and Dex authentication, the Slurm controller and its accounting | 1 |
| `worker` | A Slurm node, where the user sessions and the batch jobs run | 1 to 6, elastic |

## Requirements

* OpenNebula version: >= 6.10
* [OneFlow](https://docs.opennebula.io/7.4/product/operation_references/opennebula_services_configuration/oneflow/)
  and [OneGate](https://docs.opennebula.io/7.4/product/virtual_machines_operation/multi-vm_workflows/onegate_usage/),
  with OneGate reachable from the service networks.
* Two Virtual Networks. A management network with internet access, where the portal
  publishes its web interface. A compute network **reserved for the service**, where the
  three roles communicate. The portal uses the whole /24 around its compute address as the
  worker range, which limits the number of nodes in the cluster. The directory lookups
  cross that network unencrypted, so nothing else may live there.
* Outbound access from the storage role to the EESSI CernVM-FS servers. No other role
  needs it.

The flows the service needs through a firewall between the networks:

| From | To | Port | What for |
|---|---|---|---|
| users | portal, management network | 443, and 80 with Let's Encrypt | the web interface |
| workers | portal | 6817 | the Slurm controller, where a worker registers, fetches its configuration and reports its jobs |
| portal | workers | 6818 | `slurmd`, which starts and stops the jobs |
| workers | portal | 389 | user lookups in the directory |
| portal and workers | storage | 2049 | the shared home over NFSv4, and the controller state for the portal |
| portal and workers | storage | 3128 | the software catalogue through the site cache |
| every role | OneGate endpoint | 5030 by default | reporting readiness, the queue of the cluster and the health of the workers |
| Prometheus | portal, management network | 9101 | the service metrics, only if you scrape them |
| storage | internet | 80 and 8000 | the EESSI CernVM-FS servers, plain HTTP |
| portal | a Slurm controller of the site | 22 | batch jobs on an external cluster, only when one is declared |

The Community Marketplace defaults are 2 vCPU and 4 GB of memory per VM, and 8 GB for the
portal role. A session reserves the cores and the memory it requests on one worker. A tenth
of the memory of each worker is kept for the system, not for jobs. So give the worker role
the CPU and memory of the largest session you want to offer.

## Downloading and deploying the service

Register the Community Marketplace in your OpenNebula once, before the first download.
[The marketplace instructions](https://github.com/OpenNebula/marketplace-community/wiki/marketplace_start)
describe it for Sunstone and for the CLI.

1. Download the `Open OnDemand Service` appliance from the OpenNebula Community
   Marketplace. This imports the service template, the VM template and the image that the
   three roles share:

   ```shell
   $ onemarketapp export 'Open OnDemand Service' 'Open OnDemand Service' --datastore default
   ```

2. Adjust the templates if you need to. Most deployments change the worker cardinality,
   its CPU and its memory, in the `worker` role of the service template:

   ```shell
   $ oneflow-template update 'Open OnDemand Service'
   ```

3. Instantiate the service. It requests the two networks. Every input listed in the next
   section is optional, so a first start can leave them all unchanged:

   ```shell
   $ oneflow-template instantiate 'Open OnDemand Service'
   ```

4. Wait for the service to reach `RUNNING`. The roles start in order, storage first and
   the workers last. Each role declares itself ready only when it is serving:

   ```shell
   $ oneflow list
   $ oneflow show <service_id>
   ```

   The whole service is running about four minutes after instantiation.

5. Open the portal. The portal VM publishes its address as `OOD_URL`. It is visible in the
   attributes of the VM in Sunstone and from the command line:

   ```shell
   $ onevm show <portal vm id> | grep OOD_URL
   ```

   It is `https://` and the name you gave as `ONEAPP_PORTAL_HOST_NAME`, or the management
   address of the portal VM if you left it empty.

   Open that address and sign in with one of the users given in
   `ONEAPP_AUTH_LOCAL_USERS`, by default `demo1` with password `demo1pass`. The home
   directory is created on first login.

## Service inputs

Every input is optional, so a first start needs nothing beyond the two networks. The
instantiate wizard shows them on three tabs. Each optional feature has a switch that shows
the inputs of its section only when it is on.

**Portal**, the public name and the TLS certificate of the web portal.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_PORTAL_HOST_NAME` | empty | Public host name of the portal. It has to resolve to the management address of the portal VM. When empty, the portal answers on that address. |
| `ONEAPP_PORTAL_LETSENCRYPT_ENABLED` | `NO` | Request a Let's Encrypt certificate for the host name. The name has to resolve to the portal. Ports 80 and 443 have to be reachable from the Internet when the portal boots. If the request fails, the portal continues with a self-signed certificate and writes that in its log. |
| `ONEAPP_PORTAL_CERTIFICATE_ENABLED` | `NO` | Use a certificate of your own, given in the next two inputs. It replaces the self-signed one. When both switches are on, this certificate is the one installed. |
| `ONEAPP_PORTAL_CERTIFICATE_CHAIN` | empty | PEM certificate chain. Paste the file, and the form encodes it. Required when the switch is on. |
| `ONEAPP_PORTAL_CERTIFICATE_KEY` | empty | PEM private key. Required when the switch is on. OneFlow puts every service input in the context of every VM of the service, where root can read it. |

**Users and login**, who can sign in to the portal.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_AUTH_LOCAL_USERS` | `demo1:demo1pass` | Initial users, as `user:password` entries separated by spaces, created in the directory of the portal at first boot. A uid may follow, as `user:password:uid`, to match accounts that exist elsewhere. The others get the next free number from 10001. |
| `ONEAPP_AUTH_OIDC_ENABLED` | `NO` | Also allow signing in through an OpenID Connect provider. See [An external identity provider](#an-external-identity-provider). |
| `ONEAPP_AUTH_OIDC_ISSUER` | empty | Issuer URL of the provider. Required when the switch is on. |
| `ONEAPP_AUTH_OIDC_CLIENT_ID` | empty | Client id registered at the provider. Required when the switch is on. |
| `ONEAPP_AUTH_OIDC_CLIENT_SECRET` | empty | Client secret registered at the provider. Leave it empty only for a provider that allows public clients. |
| `ONEAPP_AUTH_OIDC_NAME` | `Institutional login` | Name of the provider on the login page. |

**Home directories**, where the files of the users live.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_HOME_NFS_ENABLED` | `NO` | Use an NFS server of your own instead of the storage role. See [Keeping the home](#keeping-the-home). |
| `ONEAPP_HOME_NFS_SERVER` | empty | Address of that server. Required when the switch is on. |
| `ONEAPP_HOME_NFS_EXPORT` | `/export/home` | Path of the home export, on the storage role or on that server. |

The roles find each other without fixed addresses. OneFlow gives the storage address to the
portal and the workers. The storage role asks OneGate which VM plays the portal. It grants
root on the home and Slurm state exports to that address only, so the workers keep
`root_squash`. The workers register with the Slurm controller on the portal when they
boot, with the munge key the portal publishes to OneGate. So the portal keeps no list of
workers, and the /24 around its compute address only limits how many nodes the cluster can
hold.

### Advanced attributes

These are not in the wizard. Set them in the `vm_template_contents` of a role in the
service template, with `oneflow-template update`, or in the `CONTEXT` of a standalone VM.
A value set in a role reaches that role only.

| Attribute | Default | Meaning |
|---|---|---|
| `ONEAPP_WORKER_IDLE_SECONDS` | `600` | Seconds the oldest worker stays without a job before it drains its node and the pool shrinks. The worker role reads it. |
| `ONEAPP_WORKER_DRAIN_SECONDS` | `600` | Seconds a drained worker waits for OneFlow to remove it before it takes jobs again. The worker role reads it. |
| `ONEAPP_POOL_RANGE` | derived | Worker address range, as `first-last`. Use it for a portal outside a OneFlow service, or on a compute network larger than a /24. Its size limits the nodes of the cluster (`MaxNodeCount`). Its prefix tells a session which of its addresses to publish. The portal role reads it. |
| `ONEAPP_SLURM_STATE_EXPORT` | `/export/slurm` | Export of the storage role that keeps the controller state, the munge key and the accounting dumps. The storage role exports it and the portal role mounts it, so set it in both. |
| `ONEAPP_SLURM_DEF_MEM_PER_CPU` | `1024` | Memory in MB that a job gets per core when it requests none. It applies to a job submitted without `--mem` from the Job Composer or a shell. The portal role reads it. |
| `ONEAPP_SLURM_CONTROLLER_ENABLED` | `NO` | Offer a Slurm cluster of the site as a second target for batch jobs. See [An external Slurm cluster](#an-external-slurm-cluster). The portal role reads it. |
| `ONEAPP_SLURM_CONTROLLER_HOST` | empty | Address or host name of that controller. Required when the switch is on. |
| `ONEAPP_SLURM_TITLE` | `External Slurm` | Name of that cluster in the portal. |

## Scaling the worker pool

The pool grows and shrinks automatically, and Slurm gives both signals. Every 30 seconds,
every worker publishes `SLURM_PENDING` to OneGate. That value is the number of jobs waiting
for a worker of its role. OneFlow adds one VM at a time, when `SLURM_PENDING > 0` is true
for two periods of 30 seconds in a row. Then a cooldown of 120 seconds gives the new VM
time to boot. The new worker registers itself with the controller, and Slurm starts the
waiting job on it. OneFlow reads the figures every `autoscaler_interval` seconds, 90 by
default in `/etc/one/oneflow-server.conf` on the Front-end. Set it to 30 and restart
`opennebula-flow` for a faster scale up; it is a setting of the Front-end, made once for
every service, and the appliance cannot set it. With 30, three 2 core jobs submitted to a
1 worker pool on the testbed had their second worker 87 seconds after the submit and the
third 217 seconds after that, and each job ran about 50 seconds after its VM was created. A job that no worker could serve
never grows the pool, for two reasons. A GPU request on a pool without GPUs is refused when
it is submitted. A job that requests more cores than any node has waits with reason
`PartitionConfig` and is not counted.

The pool shrinks one VM at a time, and only a drained one. OneFlow always removes the
oldest VM of the role and does not drain it. So the oldest worker drains its own Slurm
node once it has had no job for `ONEAPP_WORKER_IDLE_SECONDS` (ten minutes by default) and
nothing is pending. After that, Slurm schedules no new job on it. Every worker publishes
`OLDEST_IDLE=1` while that node is drained and empty. OneFlow removes it when
`OLDEST_IDLE > 0.99` is true for two periods of 60 seconds in a row. The sessions on the
other workers are untouched. The last worker never drains. A drain is undone when a pending
job makes it pointless, or when OneFlow does not remove the worker within
`ONEAPP_WORKER_DRAIN_SECONDS`. A long session on the oldest worker holds the pool at its
size until it ends. `sinfo` on the portal shows a draining node with the reason
`one-ondemand scale-down`.

To change the pool manually:

```shell
$ oneflow scale <service_id> worker <cardinality>
```

The role accepts from 1 to 6 workers. Raise `max_vms` in the service template for a larger
pool.

## Worker sizes

Every role whose name starts with `worker` is a pool of Slurm nodes. Each worker registers
its role as a Slurm feature. The portal offers the sizes that exist in a "Worker size"
field in each application form, where `worker` appears as `Standard`. A session asks Slurm
for that feature with `--constraint`. To add a larger size, copy the `worker` role in the
service template under a new name, for example `worker_large`. Give it the CPU and memory
you want:

```shell
$ oneflow-template update 'Open OnDemand Service'
```

```text
- name: worker_large
  parents: [storage, portal]
  cardinality: 1
  min_vms: 1
  max_vms: 4
  vm_template_contents: |
    ... the same lines as the worker role ...
    VCPU = "4"
    MEMORY = "16384"
  elasticity_policies: ... the same as the worker role ...
```

Each size grows and shrinks independently, with the same rules. Each size starts with at
least one VM. OneFlow scales a role from what its VMs publish, and a role with no VM
publishes nothing. A session that requests a size waits until a worker of that size is
free. That role grows for it, because the workers of a role count only the jobs that ask
for their feature or for none.

## The desktop

The Xfce Desktop application opens a Linux desktop on a worker VM inside the browser. The
session starts a TurboVNC server on the VM as a Slurm job. It runs Xfce under that display
and exposes the display through websockify. The portal serves noVNC and proxies the
websocket through its `/rnode` route, so the user needs nothing beyond port 443 of the
portal. The desktop uses the same worker pool, the same home and the same EESSI catalogue
as the notebooks. A terminal opened on it has `module load`. The form requests cores,
memory and the session hours. It also requests GPUs when a node has one, and for the
worker size when the service has more than one. The desktop packages live on the worker
VM. A task prolog gives each job its own runtime directory and its own D-Bus, so the
desktop outlives the login session that builds its environment.

## GPU workers, prepared

A worker role with a GPU is a `worker_gpu` role in the service template, [as any other
size](#worker-sizes). Its `vm_template_contents` also contains the PCI device of the host,
as the [NVIDIA GPU passthrough](https://docs.opennebula.io/7.4/product/cluster_configuration/pci_passthrough_sriov/nvidia_gpu_passthrough/)
page describes:

```text
PCI = [ VENDOR = "10de", DEVICE = "<device id>", CLASS = "0302" ]
```

At boot, the worker counts its `/dev/nvidia*` devices and registers them with Slurm as
`Gres=gpu:<n>`. The application forms then show a GPUs field. A session requests
`--gres=gpu:<n>`, and Slurm serves it on a node that has one. The image includes no NVIDIA
driver, so the site installs it on the GPU role, with a customised image or at boot. This
was prepared without a GPU to test on. Only the opposite case is verified, where a GPU
request on a pool without a GPU is refused when it is submitted. A site with a GPU should
run `nvidia-smi` inside a session before offering the size to users.

## Batch jobs with Slurm

The cluster of the service is a Slurm 23.11 cluster named `ood`, shown as `Slurm` in the
portal. It has one partition, `main`, that holds every worker. The default time of a job
is one hour and the limit is twelve hours, the same as the longest session the forms offer.
The Job Composer submits to this cluster. Active Jobs lists its jobs beside the interactive
sessions, which are jobs of the same cluster. A job requests cores with `-c` and memory
with `--mem`. A job without `--mem` gets `ONEAPP_SLURM_DEF_MEM_PER_CPU` MB per core, 1024
by default, so it never takes a whole node by accident. The output is written to the same
home the notebooks use. `sacct` on the portal lists the finished jobs of a user, because
the portal runs `slurmdbd` on MariaDB. A job that waits for a node makes the pool grow, as
[Scaling the worker pool](#scaling-the-worker-pool) describes.

### MPI jobs on several workers

A batch job can use several workers at once with MPI. The EESSI catalogue provides OpenMPI,
and the image ships the PMIx library that `srun` uses to start the processes. A job script
loads the module and starts the program with `srun --mpi=pmix` or with `mpirun`:

```
#!/bin/bash -l
#SBATCH -N 2 --ntasks-per-node=1 -c 1 --mem=512M -t 10
module load OpenMPI/5.0.8-GCC-14.3.0
srun --mpi=pmix ./hello
```

The VM template passes the CPU of the host through to the VMs (`CPU_MODEL` set to
`host-passthrough`), so EESSI loads the software built for that CPU family and the MPI
library finds the instructions it needs. On the testbed, a two node program compiled with
`mpicc` from EESSI ran on both workers with `srun --mpi=pmix` and with `mpirun`. The
interactive applications use one worker each.

### An external Slurm cluster

A Slurm cluster of the site can be a second target for batch jobs, if it shares the users
and the home with the portal. The sessions keep running on the cluster of the service. The
official OneSlurm service from the Community Marketplace is one such cluster.

1. With the Open OnDemand service running, note the compute addresses of its portal and
   storage VMs:

   ```shell
   $ onevm list -f NAME~service_<service_id> -l ID,NAME,IP
   ```

2. Instantiate `OneSlurm` on the same compute network. Disable its local LDAP and set
   these inputs, where `<portal>` and `<storage>` are those addresses:

   ```text
   ONEAPP_LDAP_ENABLE      NO
   ONEAPP_LDAP_DOMAIN      ood.local
   ONEAPP_LDAP_URL         ldap://<portal>
   ONEAPP_SLURM_NFS_HOME   <storage>:/export/home
   ```

3. Once OneSlurm is `RUNNING`, give the portal the address of the controller as advanced
   attributes. The portal reconfigures itself in less than a minute. The cluster then
   appears in the Job Composer and in Active Jobs under the name in `ONEAPP_SLURM_TITLE`,
   `External Slurm` by default:

   ```shell
   $ onevm updateconf <portal vm id> --append <<EOF
   CONTEXT = [
     ONEAPP_SLURM_CONTROLLER_ENABLED = "YES",
     ONEAPP_SLURM_CONTROLLER_HOST = "<controller compute address>" ]
   EOF
   ```

To declare a controller that exists before the service, set the same attributes in the
`vm_template_contents` of the portal role. The commands of that cluster, `sbatch`,
`squeue`, `scancel`, `sinfo`, `sacct` and `scontrol`, run on its controller over SSH as the
user. They use the key the portal keeps in the home of each user, the same mechanism the
AWS and Azure integrations use. Accounting history in `sacct` needs `slurmdbd` on that
controller, and the default OneSlurm deployment does not run it. `docs/slurmdbd-setup.sh`
in the one-ondemand repository adds it to the controller (MariaDB, `slurmdbd`, the
accounting lines in `slurm.conf` and the cluster registration). With it, `sacct` from the
portal lists the finished jobs of the user.

## An external identity provider

Set `ONEAPP_AUTH_OIDC_ENABLED` to `YES` and give the provider in `ONEAPP_AUTH_OIDC_ISSUER`,
`ONEAPP_AUTH_OIDC_CLIENT_ID` and `ONEAPP_AUTH_OIDC_CLIENT_SECRET`. The login page then
offers the provider beside the local directory, through the OpenID Connect connector of
Dex. Register `https://<ONEAPP_PORTAL_HOST_NAME>/dex/callback` at the provider as the
redirect URI. `ONEAPP_AUTH_OIDC_NAME` is the name the login page shows for it. A session
runs as a Unix user with a home, so a user who signs in that way still needs an account in
the directory. The account has to have the same name, the `preferred_username` claim or
the part of the email before the at sign. This was verified against a Dex provider that
sends no `preferred_username`, where the email fallback mapped the user.

## Users

Users live in the LDAP directory of the portal role, and adding one is one entry in it.
The portal generates the administrator password of the directory when it first configures
itself and keeps it in `/etc/one-ondemand/ldap-admin.pass`, readable by root only. On the
portal VM:

```shell
$ ldapadd -x -D cn=admin,dc=ood,dc=local -y /etc/one-ondemand/ldap-admin.pass <<EOF
dn: cn=alice,ou=Groups,dc=ood,dc=local
objectClass: posixGroup
cn: alice
gidNumber: 10003

dn: uid=alice,ou=People,dc=ood,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: alice
cn: alice
sn: alice
uidNumber: 10003
gidNumber: 10003
homeDirectory: /home/alice
loginShell: /bin/bash
userPassword: {SSHA}...
EOF
```

Generate the password hash with `slappasswd -h '{SSHA}' -s <password>`. The new user can
sign in immediately, and their home is created on first login.

## Keeping the home

By default, the shared home lives on the root disk of the storage VM and is deleted with
the service. There are two ways to keep it.

**A persistent disk on the storage role.** Create a persistent datablock once and attach
it to the storage role of the service template, as a second `DISK` in its
`vm_template_contents`:

```shell
$ oneimage create --name ood-home --type DATABLOCK --size 51200 --persistent --datastore default
$ oneflow-template update 'Open OnDemand Service'
```

```text
DISK = [ IMAGE_ID = "<id of ood-home>" ]
```

At first boot, the storage role formats a blank second disk, labels it `ood-home` and keeps
the homes on it. A disk that already has the label is mounted as it is. So deleting the
service and instantiating it again with the same image restores every home. A disk with any
other filesystem is not touched, and the role stops with an error that says so. Make a
backup of the homes with `onevm disk-saveas` or with a disk snapshot of the storage VM,
whichever your datastore supports.

**An NFS server you already run.** Set `ONEAPP_HOME_NFS_ENABLED` to `YES`, give its
address in `ONEAPP_HOME_NFS_SERVER` and the path in `ONEAPP_HOME_NFS_EXPORT`. The portal
and the workers then mount that export instead of the storage role. The server has to
export it with `no_root_squash` for the portal address, because the portal creates each
home on first login. It can keep `root_squash` for the workers. The storage role still
runs the software cache and keeps the Slurm state export, so it stays in the service.

## Removing the service

```shell
$ oneflow delete <service_id>
```

This terminates the VMs of the three roles and the non persistent disks. A persistent home
disk is released and keeps its content. An external export is not touched. The imported
image, the VM template and the service template stay in your OpenNebula until you delete
them.

## Metrics and where to look when something is wrong

The portal serves Prometheus metrics for the whole service on port 9101,
`http://<portal management address>:9101/metrics`. Per worker, it exposes
`ood_worker_active_sessions` (the jobs running on it), `ood_worker_idle_seconds`,
`ood_worker_oldest_idle`, `ood_worker_healthy`, `ood_slurm_pending`,
`ood_slurm_idle_nodes` and `ood_slurm_alloc_nodes`. They come from what the workers
publish to OneGate. It also exposes `ood_role_cardinality` per role, `ood_service_state`,
`ood_portal_puns` (the per user web servers running on the portal) and
`ood_exporter_scrape_ok`. The same values are in the user template of each worker VM:

```shell
$ onevm show <worker id> | grep -E 'SLURM_|ACTIVE_SESSIONS|IDLE|HEALTHY|SESSION_USERS'
```

`SESSION_USERS` lists who has a job on the worker and since when, as `user:start` entries
with the start time as `squeue` prints it. With it, the VM accounting of OpenNebula can be
attributed to users. `SLURM_NODENAME` is the name of the worker in `sinfo`.

Before every report, a worker checks its home mount, the software catalogue, munge and
`slurmd`. It publishes `HEALTHY=0` when one of them is missing. The log of the check is on
the worker, in `journalctl -t ood-slurm-elastic`. The controller is not part of the check,
so a controller outage is never reported as every worker being broken.

On the portal, `sinfo` lists the nodes with their state, and the reason for a drained one.
`squeue` lists the jobs and why they wait. `sacct` lists the finished jobs. The controller
logs are under `/var/log/slurm/`. The reconciler, which keeps the Slurm nodes consistent
with the service, logs as `journalctl -t ood-slurm-reconcile`. The accounting dumps are
written to the storage VM under `/export/slurm/backup/` every 30 minutes.

Each role logs what it did at boot in `/var/log/ood-appliance-configure.log`.
`/etc/one-ondemand/build.env` records what the image was built from. A role that failed to
configure shows it in its `motd` and in `/etc/one-appliance/status`. OneFlow does not set
the service to `RUNNING` until every role has declared itself ready.

On the portal, Open OnDemand writes the per user web server logs under
`/var/log/ondemand-nginx/<user>/`, and Apache writes under `/var/log/apache2/`. A session
that does not start leaves its output in the session directory under the home of the user,
at `~/ondemand/data/sys/dashboard/batch_connect/sys/<app>/output/<session id>/output.log`.
Because the home is shared, that file is readable from the portal and from every worker.

## When a session does not start

1. `oneflow show <service_id>` says whether every role is `RUNNING`. A worker in a
   different state has not declared itself ready, and its
   `/var/log/ood-appliance-configure.log` says at which step it stopped.
2. On the portal, `sinfo -N -l` lists the workers that Slurm knows, with their state. A
   worker missing from the list has not registered, and its `journalctl -u slurmd` says
   why. A node `drained` with reason `one-ondemand scale-down` is about to be removed and
   takes no job. A node `down` means the controller lost contact with it. `journalctl -t
   ood-slurm-reconcile` shows what the reconciler did with it.
3. `squeue -u <user>` shows the job of the session and, while it waits, the reason.
   `Resources` and `Priority` mean every worker is full and the pool grows for the job.
   `PartitionConfig` means the job requested more than any node has.
4. The session directory under the home of the user has two files. `connection.yml` names
   the worker the session ran on. `output.log` shows what failed there. `module load`
   errors indicate a problem with the software catalogue. `Permission denied` on the home
   indicates a problem with the export.
5. On the worker, `journalctl -t ood-slurm-elastic` shows what the health check found and
   what the publisher sent. `journalctl -u slurmd` shows what the node did with the job.
   `runuser -u <user> -- ls /cvmfs/software.eessi.io/versions` shows whether the catalogue
   is reachable as that user.

## Upgrading

A new version of the appliance is a new image and new templates. The running service keeps
the old ones. Download the new version from the Community Marketplace, which imports them
beside the old ones. Then instantiate a new service from the new service template. The
home survives the change when it lives on a persistent disk or on an NFS server of your
own, as [Keeping the home](#keeping-the-home) describes. Delete the old service. Then
attach the same disk to the new service, or configure the same NFS export. The users find
their files. If the home is on the root disk of the storage VM, save a copy with
`onevm disk-saveas` before deleting the old service. The users in the LDAP directory are
recreated from `ONEAPP_AUTH_LOCAL_USERS`. So pass the same value, or add the users again
once the new portal is running. The state export lives on the root disk of the storage VM.
So a new service starts with an empty Slurm queue and an empty accounting history.

## Limitations and operating mode

* Every session is a Slurm job with the cores and the memory it requested, and nothing
  else shares them. A session cannot request more than the largest worker has. A session
  that finds every worker full waits in the queue until the pool grows.
* A portal replaced by OneFlow was not tested. The workers follow the new portal address.
  The key, the queue and the accounting dumps are restored from the storage export.
  Neither was run on the testbed. Up to 30 minutes of accounting history are lost in the
  replacement, because the dumps run every 30 minutes.
* The pool shrinks only when the oldest worker has been empty for the idle threshold. So a
  long session on the oldest worker holds the pool at its size.
* GPU workers are prepared but untested, see [GPU workers, prepared](#gpu-workers-prepared).
* The scientific software comes from EESSI over CernVM-FS. The first load of a module on a
  fresh deployment downloads it through the site cache on the storage role.

## Versions and licence

The appliance runs Open OnDemand 4.2 on Ubuntu 24.04, with Slurm 23.11.4 and munge 0.5.15
from the Ubuntu packages. It uses MariaDB 10.11 for the accounting, EESSI 2025.06 and
Apptainer 1.5. The desktop uses TurboVNC 3.3.1 and Xfce 4.18. Open OnDemand is
[MIT licensed](https://github.com/OSC/ondemand/blob/master/LICENSE.txt), and the appliance
code is Apache 2.0, like the rest of this repository. There is no fee for the appliance.
It runs on your own OpenNebula, so its only cost is the cost of the VMs it creates.

## Release notes

See the [changelog](CHANGELOG.md).
