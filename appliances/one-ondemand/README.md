# Open OnDemand

[Open OnDemand](https://openondemand.org/) gives HPC users a browser interface to a
cluster, with a file browser, a shell, job submission and interactive applications. This
appliance runs it on OpenNebula as a OneFlow service with its own Slurm cluster on an
elastic pool of compute VMs behind the portal. A user signs in, presses a button and gets a
JupyterLab notebook, RStudio, Octave, a C++ notebook, VS Code or an Xfce desktop running as
a Slurm job on a compute VM, with the cores and the memory it asked for, the scientific
software served from the [EESSI](https://www.eessi.io/) catalogue and a home directory that
follows them from session to session.

The service has three roles, all of them running from the same image. `ONEAPP_ROLE`
decides at boot which one a VM plays, and the OneFlow template sets it per role.

| Role | What it runs | Cardinality |
|---|---|---|
| `storage` | NFS server for the shared home and for the Slurm controller state, site cache for the software catalogue | 1 |
| `portal` | Open OnDemand, its own LDAP directory and Dex authentication, the Slurm controller and its accounting | 1 |
| `worker` | A Slurm node, where the user sessions and the batch jobs run | 1 to 6, elastic |

## Requirements

* OpenNebula version: >= 6.10
* [OneFlow](https://docs.opennebula.io/7.4/product/operation_references/opennebula_services_configuration/oneflow/)
  and [OneGate](https://docs.opennebula.io/7.4/product/virtual_machines_operation/multi-vm_workflows/onegate_usage/),
  with OneGate reachable from the service networks.
* Two virtual networks. A management network with internet access, where the portal
  publishes its web interface, and a compute network **reserved for the service**, where
  the three roles talk to each other. The portal takes the whole /24 around its compute
  address as the worker range, which bounds the number of nodes of the cluster, and the
  directory lookups travel that network in the clear, so nothing else may live there.
* Outbound access to the EESSI CernVM-FS servers from the storage role, the only role that
  needs it.

If a firewall sits between the networks, these are the flows the service needs:

| From | To | Port | What for |
|---|---|---|---|
| users | portal, management network | 443, and 80 with Let's Encrypt | the web interface |
| workers | portal | 6817 | the Slurm controller, where a worker registers, fetches its configuration and reports its jobs |
| portal | workers | 6818 | `slurmd`, starting and stopping the jobs |
| workers | portal | 389 | resolving users against the directory |
| portal and workers | storage | 2049 | the shared home over NFSv4, and the controller state for the portal |
| portal and workers | storage | 3128 | the software catalogue through the site cache |
| every role | OneGate endpoint | 5030 by default | reporting readiness, the queue of the cluster and the health of the workers |
| Prometheus | portal, management network | 9101 | the service metrics, only if you scrape them |
| storage | internet | 80 and 8000 | the EESSI CernVM-FS servers, plain HTTP |
| portal | a Slurm controller of the site | 22 | batch jobs on an external cluster, only when one is declared |

The compute network carries the directory lookups in the clear, so it has to stay reserved
for the service, as the first requirement says.

The marketplace defaults are 2 vCPU and 4 GB of memory per VM, 8 GB for the portal role. A
session reserves the cores and the memory it asks for on one worker, and a tenth of each
worker's memory stays out of the allocations for the system, so give the worker role the
CPU and memory of the largest session you want to offer.

## Downloading and deploying the service

The Community Marketplace has to be registered in your OpenNebula first, once, as
[the marketplace instructions](https://github.com/OpenNebula/marketplace-community/wiki/marketplace_start)
describe for Sunstone and for the CLI.

1. Download the `Open OnDemand Service` appliance from the OpenNebula Community
   Marketplace. This imports the service template, the VM template and the image that the
   three roles share:

   ```shell
   $ onemarketapp export 'Open OnDemand Service' 'Open OnDemand Service' --datastore default
   ```

2. Adjust the templates if you need to. The worker cardinality, its CPU and its memory are
   the settings most deployments change, and they are in the `worker` role of the service
   template:

   ```shell
   $ oneflow-template update 'Open OnDemand Service'
   ```

3. Instantiate the service. It asks for the two networks, and every input listed in the
   next section is optional, so a first start changes none of them:

   ```shell
   $ oneflow-template instantiate 'Open OnDemand Service'
   ```

4. Wait for the service to reach `RUNNING`. The roles start in order, storage first and the
   workers last, and each one declares itself ready only when it is actually serving:

   ```shell
   $ oneflow list
   $ oneflow show <service_id>
   ```

   The whole service is running about four minutes after instantiation.

5. Open the portal. The portal VM publishes its address as `OOD_URL`, visible in the
   attributes of the VM in Sunstone and from the command line:

   ```shell
   $ onevm show <portal vm id> | grep OOD_URL
   ```

   It is `https://` and the name you gave as `ONEAPP_PORTAL_HOST_NAME`, or the management
   address of the portal VM if you left it empty.

   Then go to that address and sign in with one of the users given in
   `ONEAPP_AUTH_LOCAL_USERS`, by default `demo1` with password `demo1pass`. The home
   directory is created on first login.

## Service inputs

Every input is optional, so a first start needs nothing beyond the two networks. The
instantiate wizard shows them on three tabs, and each optional feature sits behind a switch
that reveals the inputs of its section only when it is on.

**Portal**, the public name and the TLS certificate of the web portal.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_PORTAL_HOST_NAME` | empty | Public host name of the portal. It has to resolve to the management address of the portal VM. Empty makes the portal answer on that address. |
| `ONEAPP_PORTAL_LETSENCRYPT_ENABLED` | `NO` | Request a Let's Encrypt certificate for the host name. The name has to resolve to the portal and ports 80 and 443 have to be reachable from the Internet when the portal boots. When the request fails the portal continues with a self-signed certificate and says so in its log. |
| `ONEAPP_PORTAL_CERTIFICATE_ENABLED` | `NO` | Use a certificate of your own, given in the next two inputs. It replaces the self-signed one, and with both switches on it is the one installed. |
| `ONEAPP_PORTAL_CERTIFICATE_CHAIN` | empty | PEM certificate chain. Paste the file, the form encodes it. Required when the switch is on. |
| `ONEAPP_PORTAL_CERTIFICATE_KEY` | empty | PEM private key. Required when the switch is on. OneFlow puts every service input in the context of every VM of the service, where root can read it. |

**Users and login**, who can sign in to the portal.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_AUTH_LOCAL_USERS` | `demo1:demo1pass` | Initial users, as `user:password` separated by spaces, created in the directory of the portal at first boot. A uid may follow, `user:password:uid`, to match accounts that exist elsewhere; the others get the next free number from 10001. |
| `ONEAPP_AUTH_OIDC_ENABLED` | `NO` | Sign in through an OpenID Connect provider as well. See [An external identity provider](#an-external-identity-provider). |
| `ONEAPP_AUTH_OIDC_ISSUER` | empty | Issuer URL of the provider. Required when the switch is on. |
| `ONEAPP_AUTH_OIDC_CLIENT_ID` | empty | Client id registered at the provider. Required when the switch is on. |
| `ONEAPP_AUTH_OIDC_CLIENT_SECRET` | empty | Client secret registered at the provider. Empty only for a provider that allows public clients. |
| `ONEAPP_AUTH_OIDC_NAME` | `Institutional login` | Name of the provider on the login page. |

**Home directories**, where the files of the users live.

| Input | Default | Description |
|---|---|---|
| `ONEAPP_HOME_NFS_ENABLED` | `NO` | Use an NFS server of your own instead of the storage role. See [Keeping the home](#keeping-the-home). |
| `ONEAPP_HOME_NFS_SERVER` | empty | Address of that server. Required when the switch is on. |
| `ONEAPP_HOME_NFS_EXPORT` | `/export/home` | Path of the home export, on the storage role or on that server. |

The roles find each other without fixed addresses. OneFlow hands the storage address to the
portal and the workers, and the storage role asks OneGate which VM plays the portal and
grants root on the home export and on the Slurm state export to that address alone, so the
workers keep `root_squash`. The workers register themselves with the Slurm controller on
the portal when they boot, with the munge key the portal publishes to OneGate, so the portal
keeps no list of workers and the /24 around its compute address only bounds how many nodes
the cluster can hold.

### Advanced attributes

These are not in the wizard. Set them in the `vm_template_contents` of a role in the
service template, with `oneflow-template update`, or in the `CONTEXT` of a standalone VM.
A value set in a role reaches that role only.

| Attribute | Default | Meaning |
|---|---|---|
| `ONEAPP_WORKER_IDLE_SECONDS` | `600` | Seconds the oldest worker stays without a job before it drains its node and the pool shrinks. The worker role reads it. |
| `ONEAPP_WORKER_DRAIN_SECONDS` | `600` | Seconds a drained worker waits for OneFlow to remove it before it takes jobs again. The worker role reads it. |
| `ONEAPP_POOL_RANGE` | derived | Worker address range, `first-last`, for a portal outside a OneFlow service or on a compute network larger than a /24. Its size bounds the nodes of the cluster (`MaxNodeCount`) and its prefix tells a session which of its addresses to publish. The portal role reads it. |
| `ONEAPP_SLURM_STATE_EXPORT` | `/export/slurm` | Export of the storage role that keeps the controller state, the munge key and the accounting dumps. The storage role exports it and the portal role mounts it, so set it in both. |
| `ONEAPP_SLURM_DEF_MEM_PER_CPU` | `1024` | Memory in MB a job gets per core when it asks for none, for a job submitted without `--mem` from the Job Composer or a shell. The portal role reads it. |
| `ONEAPP_SLURM_CONTROLLER_ENABLED` | `NO` | Offer a Slurm cluster of the site as a second target for batch jobs. See [An external Slurm cluster](#an-external-slurm-cluster). The portal role reads it. |
| `ONEAPP_SLURM_CONTROLLER_HOST` | empty | Address or host name of that controller. Required when the switch is on. |
| `ONEAPP_SLURM_TITLE` | `External Slurm` | Name of that cluster in the portal. |

## Scaling the worker pool

The pool grows and shrinks on its own, and Slurm is the source of both signals. Every
worker publishes to OneGate every 30 seconds `SLURM_PENDING`, the jobs waiting for a worker
of its role, and OneFlow adds one VM at a time, on `SLURM_PENDING > 0` over two
periods of 30 seconds and then a cooldown of 300 seconds that covers the boot of the new
VM. The new worker registers with the controller on its own and Slurm starts the waiting
job on it, and on the testbed the VM was added 161 seconds after the submit with the job
running on it at 210. A job no worker could serve never grows the pool, because a GPU
request on a pool without GPUs is refused at submit and a job that asks for more cores than
any node has waits with reason `PartitionConfig` and is not counted.

The pool shrinks one VM at a time, and only a drained one. OneFlow always removes the oldest
VM of the role and does not drain it, so the oldest worker, once it has had no job for
`ONEAPP_WORKER_IDLE_SECONDS` (ten minutes by default) and nothing is pending, drains its
own Slurm node, so nothing more lands on it, and every worker publishes `OLDEST_IDLE=1`
while that node is drained and empty. OneFlow removes it on `OLDEST_IDLE > 0.99` over two
periods of 60 seconds, and the sessions on the other workers are untouched. The last worker
never drains, and a drain that a pending job makes pointless, or that OneFlow does not act
on within `ONEAPP_WORKER_DRAIN_SECONDS`, is undone. A long session on the oldest worker
holds the pool at its size until it ends, and `sinfo` on the portal shows a draining node
with the reason `one-ondemand scale-down`.

To change the pool by hand:

```shell
$ oneflow scale <service_id> worker <cardinality>
```

The role accepts from 1 to 6 workers. Raise `max_vms` in the service template for a larger
pool.

## Worker sizes

Every role whose name starts with `worker` is a pool of session VMs. Each worker registers
its role as a Slurm feature, and the portal offers the sizes that exist as a "Worker size"
field in each application form, with `worker` as `Standard`, so a session asks Slurm for
that feature with `--constraint`. To add a larger size, copy the `worker` role in the
service template under a new name, `worker_large` for instance, and give it the CPU and
memory you want:

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

Each size grows and shrinks on its own, with the same rules, and starts with at least one
VM, because OneFlow scales a role from what its VMs publish and a role with no VM publishes
nothing. A session that asks for a size waits until a worker of that size is free, and that
role grows for it, because the workers of a role count only the jobs that ask for their
feature or for none.

## The desktop

The Xfce Desktop application opens a Linux desktop on a worker VM inside the browser. The
session starts a TurboVNC server on the VM as a Slurm job, runs Xfce under its display and
bridges the display with websockify; the portal serves noVNC and proxies the websocket
through its `/rnode` route, so the user needs nothing beyond port 443 of the portal. The
desktop uses the same worker pool, the same home and the same EESSI catalogue as the
notebooks, and a terminal opened on it has `module load`. The form asks for cores, memory
and the session hours, for GPUs when a node has one, and for the worker size when the
service has more than one. The
desktop packages live on the worker VM, and a task prolog gives each job a runtime directory
and a D-Bus of its own, so the desktop outlives the login session that builds its
environment.

## GPU workers, prepared

A worker role with a GPU is a `worker_gpu` role in the service template, [as any other
size](#worker-sizes), whose `vm_template_contents` also carries the PCI device of the host,
as the [NVIDIA GPU passthrough](https://docs.opennebula.io/7.4/product/cluster_configuration/pci_passthrough_sriov/nvidia_gpu_passthrough/)
page describes:

```text
PCI = [ VENDOR = "10de", DEVICE = "<device id>", CLASS = "0302" ]
```

At boot the worker counts its `/dev/nvidia*` devices and registers them with Slurm as
`Gres=gpu:<n>`, the application forms then show a GPUs field, and a session asks for
`--gres=gpu:<n>`, which Slurm serves on a node that has one. The image ships no NVIDIA
driver, so the site installs it on the GPU role, with a customised image or at boot. This
was prepared without a GPU to test on, and the verified side is the other one, a GPU request
on a pool without one is refused at submit. A site with a GPU should run `nvidia-smi` inside
a session before offering the size to users.

## Batch jobs with Slurm

The cluster of the service is a Slurm 23.11 cluster named `ood`, shown as `Slurm` in the
portal, with one partition, `main`, that holds every worker, a default time of one hour and
a limit of twelve, the same as the longest session the forms offer. The Job Composer submits
to it and Active Jobs lists its jobs beside the interactive sessions, which are jobs of the
same cluster. A job asks for cores with `-c` and memory with `--mem`, and a job without
`--mem` gets `ONEAPP_SLURM_DEF_MEM_PER_CPU` MB per core, 1024 by default, so it never takes
a whole node by accident. The output lands in the same home the notebooks use, and `sacct`
on the portal lists the finished jobs of a user, because the portal runs `slurmdbd` on
MariaDB. A job that waits for a node makes the pool grow, as [Scaling the worker
pool](#scaling-the-worker-pool) describes.

### An external Slurm cluster

A Slurm cluster of the site that shares the users and the home with the portal can be a
second target for batch jobs, while the sessions keep running on the cluster of the
service. The official OneSlurm service from the marketplace is one such cluster.

1. With the Open OnDemand service running, note the compute addresses of its portal and
   storage VMs:

   ```shell
   $ onevm list -f NAME~service_<service_id> -l ID,NAME,IP
   ```

2. Instantiate `OneSlurm` on the same compute network, with the local LDAP disabled and
   these inputs, where `<portal>` and `<storage>` are those addresses:

   ```text
   ONEAPP_LDAP_ENABLE      NO
   ONEAPP_LDAP_DOMAIN      ood.local
   ONEAPP_LDAP_URL         ldap://<portal>
   ONEAPP_SLURM_NFS_HOME   <storage>:/export/home
   ```

3. Once OneSlurm is `RUNNING`, give the portal the address of the controller, as advanced
   attributes. The portal reconfigures itself in under a minute and the cluster appears in
   the Job Composer and in Active Jobs under the name in `ONEAPP_SLURM_TITLE`, `External
   Slurm` by default:

   ```shell
   $ onevm updateconf <portal vm id> --append <<EOF
   CONTEXT = [
     ONEAPP_SLURM_CONTROLLER_ENABLED = "YES",
     ONEAPP_SLURM_CONTROLLER_HOST = "<controller compute address>" ]
   EOF
   ```

The same attributes in the `vm_template_contents` of the portal role declare a controller
that exists before the service does. The commands of that cluster, `sbatch`, `squeue`,
`scancel`, `sinfo`, `sacct` and `scontrol`, run on its controller over SSH as the user, with
the key the portal keeps in each user's home, the same mechanism the AWS and Azure
integrations use. Accounting history in `sacct` depends on that controller running
`slurmdbd`, which the default OneSlurm deployment does not. `docs/slurmdbd-setup.sh` in the
one-ondemand repository adds it to the controller (MariaDB, `slurmdbd`, the accounting
lines in `slurm.conf` and the cluster registration); with it, `sacct` from the portal lists
the finished jobs of the user.

## An external identity provider

With `ONEAPP_AUTH_OIDC_ENABLED` set to `YES` and the provider given in
`ONEAPP_AUTH_OIDC_ISSUER`, `ONEAPP_AUTH_OIDC_CLIENT_ID` and `ONEAPP_AUTH_OIDC_CLIENT_SECRET`,
the login page offers the provider beside the local directory, through the OpenID Connect
connector of Dex, with `https://<ONEAPP_PORTAL_HOST_NAME>/dex/callback` as the redirect URI
to register at the provider. `ONEAPP_AUTH_OIDC_NAME` is the name the login page shows for
it. A user who signs in that way still needs an account in the directory under the same
name, the `preferred_username` claim or the part of the email before the at sign, because a
session runs as a Unix user with a home. Verified against a Dex provider that sends no
`preferred_username`, where the email fallback mapped the user.

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
sign in right away, and their home is created on first login.

## Keeping the home

By default the shared home lives on the root disk of the storage VM and goes with the
service when the service is deleted. Two ways keep it.

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

The storage role formats a blank second disk at first boot, labels it `ood-home` and keeps
the homes on it. A disk that already carries the label is mounted as it is, so deleting the
service and instantiating it again with the same image brings every home back. A disk with
any other filesystem is left alone, and the role stops with an error that says so. Back the homes up with
`onevm disk-saveas` or a disk snapshot of the storage VM, whichever your datastore supports.

**An NFS server you already run.** Set `ONEAPP_HOME_NFS_ENABLED` to `YES` and give its
address in `ONEAPP_HOME_NFS_SERVER` and the path in `ONEAPP_HOME_NFS_EXPORT`, and the
portal and the workers mount that export instead of the storage role. The server has to
export it with `no_root_squash` for the portal address, the role that creates each home on
first login, and can keep `root_squash` for the workers. The storage role still runs the
software cache and keeps the Slurm state export, so it stays in the service.

## Removing the service

```shell
$ oneflow delete <service_id>
```

This terminates the three VMs and the non persistent disks. A persistent home disk is
released and keeps its content, an external export is untouched. The imported image, VM
template and service template stay in your OpenNebula until you delete them.

## Metrics and where to look when something is wrong

The portal serves Prometheus metrics for the whole service on port 9101,
`http://<portal management address>:9101/metrics`. Per worker it exposes
`ood_worker_active_sessions`, the jobs running on it, `ood_worker_idle_seconds`,
`ood_worker_oldest_idle`, `ood_worker_healthy`, `ood_slurm_pending`,
`ood_slurm_idle_nodes` and `ood_slurm_alloc_nodes`, read from what the workers publish to
OneGate, plus `ood_role_cardinality` per role, `ood_service_state`, `ood_portal_puns`, the
per user web servers running on the portal, and `ood_exporter_scrape_ok`. The same values
are in the user template of each worker VM:

```shell
$ onevm show <worker id> | grep -E 'SLURM_|ACTIVE_SESSIONS|IDLE|HEALTHY|SESSION_USERS'
```

`SESSION_USERS` lists who has a job on the worker and since when, as `user:start` entries
with the start time as `squeue` prints it, so the VM accounting of OpenNebula can be
attributed to users. `SLURM_NODENAME` is the name of the worker in `sinfo`.

A worker checks its home mount, the software catalogue, munge and `slurmd` before every
report and publishes `HEALTHY=0` when one of them is missing, and the log of the check is
on the worker, `journalctl -t ood-slurm-elastic`. The controller is not part of the check,
so a controller outage never reads as every worker broken.

On the portal, `sinfo` lists the nodes with their state and, for a drained one, the reason,
`squeue` lists the jobs and why they wait, and `sacct` the finished ones. The controller
logs are under `/var/log/slurm/`, the reconciler that keeps the nodes in step with the
service logs as `journalctl -t ood-slurm-reconcile`, and the accounting dumps land on the
storage VM under `/export/slurm/backup/` every 30 minutes.

Each role logs what it did at boot in `/var/log/ood-appliance-configure.log`, and
`/etc/one-ondemand/build.env` records what the image was built from. A role that failed to
configure shows it in its `motd` and in `/etc/one-appliance/status`, and OneFlow keeps the
service out of `RUNNING` until every role has declared itself ready.

On the portal, Open OnDemand writes the per user web server logs under
`/var/log/ondemand-nginx/<user>/` and Apache under `/var/log/apache2/`. A session that does
not start leaves its output in the session directory under the user's home,
`~/ondemand/data/sys/dashboard/batch_connect/sys/<app>/output/<session id>/output.log`, which
the shared home makes readable from the portal and from every worker.

## When a session does not start

1. `oneflow show <service_id>` says whether every role is `RUNNING`. A worker in a
   different state has not declared itself ready, and its `/var/log/ood-appliance-configure.log`
   says at which step it stopped.
2. On the portal, `sinfo -N -l` lists the workers Slurm knows, with their state. A worker
   missing from the list has not registered, and its `journalctl -u slurmd` says why. A node
   `drained` with reason `one-ondemand scale-down` is about to be removed and takes no job,
   and `down` means the controller lost it. `journalctl -t ood-slurm-reconcile` shows what
   the reconciler did with it.
3. `squeue -u <user>` shows the job of the session and, while it waits, the reason.
   `Resources` and `Priority` mean every worker is full and the pool grows for it, and
   `PartitionConfig` means it asked for more than any node has.
4. The session directory under the user's home has `connection.yml`, with the worker the
   session ran on, and `output.log`, with what failed there. `module load` errors point at
   the software catalogue, and `Permission denied` on the home points at the export.
5. On the worker, `journalctl -t ood-slurm-elastic` shows what the health check found and
   what the publisher sent, `journalctl -u slurmd` what the node did with the job, and
   `runuser -u <user> -- ls /cvmfs/software.eessi.io/versions` whether the catalogue is
   reachable as that user.

## Upgrading

A new version of the appliance is a new image and new templates, and the running service
keeps the old ones. Download the new version from the marketplace, which imports them
beside the old ones, and instantiate a new service from the new service template. The home
survives the change when it lives on a persistent disk or on an NFS server of your own, as
[Keeping the home](#keeping-the-home) describes. Delete the old service, attach the same
disk to the new one or point it at the same export, and the users find their files. With
the home on the storage VM's root disk, copy it out with `onevm disk-saveas` before
deleting the old service. Users, the LDAP directory, are recreated from
`ONEAPP_AUTH_LOCAL_USERS`, so pass the same value or add the users again once the new portal
is up. A new service starts with an empty Slurm queue and an empty accounting history,
because the state export lives on the root disk of the storage VM.

## Limitations and operating mode

* Every session is a Slurm job with the cores and the memory it asked for, and nothing
  else shares them. A session cannot ask for more than the largest worker has, and a
  session that finds every worker full waits in the queue until the pool grows.
* A portal replaced by OneFlow was not exercised. The workers follow the new portal
  address and the key, the queue and the accounting dumps come back from the storage
  export, but neither was run on the testbed, and up to 30 minutes of accounting history,
  the interval of the dumps, are lost in the replacement.
* The pool shrinks only when the oldest worker has been empty for the idle threshold, so a
  long session on the oldest worker holds the pool at its size.
* GPU workers are prepared but untested, see above.
* The scientific software comes from EESSI over CernVM-FS. The first load of a module on a
  fresh deployment downloads it through the site cache on the storage role.

## Versions and licence

Open OnDemand 4.2 on Ubuntu 24.04, Slurm 23.11.4 and munge 0.5.15 from the Ubuntu packages,
MariaDB 10.11 for the accounting, EESSI 2025.06, Apptainer 1.5, TurboVNC 3.3.1 and Xfce
4.18 for the desktop. Open OnDemand is
[MIT licensed](https://github.com/OSC/ondemand/blob/master/LICENSE.txt) and the appliance
code is Apache 2.0, like the rest of this repository. There is no fee for the appliance, and
it runs on your own OpenNebula, so it costs what the VMs it creates cost.

## Release notes

See the [changelog](CHANGELOG.md).
