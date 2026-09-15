# Open OnDemand

[Open OnDemand](https://openondemand.org/) gives HPC users a browser interface to a
cluster: a file browser, a shell, job submission and interactive applications. This
appliance runs it on OpenNebula as a OneFlow service with an elastic pool of compute VMs
behind the portal. A user signs in, presses a button and gets a JupyterLab notebook,
RStudio, Octave, a C++ notebook, VS Code or an Xfce desktop running on a compute VM, with the
scientific software served from the [EESSI](https://www.eessi.io/) catalogue and a home directory
that follows them from session to session.

The service has three roles, all of them running from the same image. `ONEAPP_ROLE`
decides at boot which one a VM plays, and the OneFlow template sets it per role.

| Role | What it runs | Cardinality |
|---|---|---|
| `storage` | NFS server for the shared home, site cache for the software catalogue | 1 |
| `portal` | Open OnDemand, its own LDAP directory and Dex authentication | 1 |
| `worker` | User sessions, inside Apptainer containers | 1 to 6, elastic |

## Requirements

* OpenNebula version: >= 6.10
* [OneFlow](https://docs.opennebula.io/7.4/product/operation_references/opennebula_services_configuration/oneflow/)
  and [OneGate](https://docs.opennebula.io/7.4/product/virtual_machines_operation/multi-vm_workflows/onegate_usage/),
  with OneGate reachable from the service networks.
* Two virtual networks. A management network with internet access, where the portal
  publishes its web interface, and a compute network **reserved for the service**, where
  the three roles talk to each other. The portal treats every live address in the range
  that network assigns as a worker, apart from its own and the storage role's, so nothing
  else may live there.
* Outbound access to the EESSI CernVM-FS servers from the storage role, the only role that
  needs it.

If a firewall sits between the networks, these are the flows the service needs:

| From | To | Port | What for |
|---|---|---|---|
| users | portal, management network | 443, and 80 with `letsencrypt` | the web interface |
| portal | workers | 22 | starting and stopping sessions |
| workers | portal | 389 | resolving users against the directory |
| portal and workers | storage | 2049 | the shared home over NFSv4 |
| portal and workers | storage | 3128 | the software catalogue through the site cache |
| every role | OneGate endpoint | 5030 by default | reporting readiness and session counts |
| Prometheus | portal, management network | 9101 | the service metrics, only if you scrape them |
| storage | internet | 80 and 8000 | the EESSI CernVM-FS servers, plain HTTP |

The compute network carries the directory lookups in the clear, so it has to stay reserved
for the service, as the first requirement says.

Marketplace defaults per VM: 2 vCPU and 4 GB of memory, 8 GB for the portal role. A worker
runs every session that lands on it inside one VM, so give the worker role the CPU and
memory your sessions need.

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

3. Instantiate the service. It asks for the two networks and for the inputs listed in the
   next section:

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

   It is `https://` and the name you gave as `ONEAPP_OOD_SERVERNAME`, or the management
   address of the portal VM if you left it empty.

   Then go to `https://<ONEAPP_OOD_SERVERNAME>/` and sign in with one of the users given in
   `ONEAPP_LDAP_USERS`, by default `demo1` with password `demo1pass`. The home directory
   is created on first login.

## Service inputs

| Parameter | Service Default | Description |
|---|---|---|
| `ONEAPP_OOD_SERVERNAME` | empty | Public host name of the portal. It has to resolve to the management address of the portal VM. Empty makes the portal answer on that address. |
| `ONEAPP_OOD_SSL_MODE` | `selfsigned` | `selfsigned`, `letsencrypt` or `custom`. Let's Encrypt needs the host name to be public and port 80 reachable. `custom` installs the certificate given in the next two inputs. |
| `ONEAPP_OOD_SSL_CERT` | empty | PEM certificate chain for the `custom` mode. Paste the file, the form encodes it. |
| `ONEAPP_OOD_SSL_KEY` | empty | PEM private key for the `custom` mode. OneFlow puts every service input in the context of every VM of the service, where root can read it. |
| `ONEAPP_LDAP_USERS` | `demo1:demo1pass:10001` | Initial users, as `user:password:uid` separated by spaces. |
| `ONEAPP_WORKER_IDLE_SECONDS` | `600` | How long the oldest worker stays empty before the pool loses a VM. |
| `ONEAPP_WORKER_MAX_SESSIONS` | `4` | Sessions a worker takes. The portal sends new sessions elsewhere at that count, and a pool whose workers are all at it grows. |
| `ONEAPP_SLURM_CONTROLLER` | empty | Compute address of a Slurm controller that shares the users and the home. See [Batch jobs with Slurm](#batch-jobs-with-slurm). |
| `ONEAPP_OIDC_ISSUER`, `ONEAPP_OIDC_CLIENT_ID`, `ONEAPP_OIDC_CLIENT_SECRET`, `ONEAPP_OIDC_NAME` | empty | An OpenID Connect provider on the login page. See [An external identity provider](#an-external-identity-provider). |
| `ONEAPP_POOL_RANGE` | `172.20.0.50-172.20.0.249` | The address range the compute network assigns to VMs, `first-last`. |
| `ONEAPP_NFS_SERVER` | empty | Address of an NFS server of your own for the home. Empty uses the storage role. |
| `ONEAPP_NFS_EXPORT` | `/export/home` | Path of the home export, on the storage role or on that server. |

`ONEAPP_POOL_RANGE` has to match the address range of the network you select as `Compute`
when instantiating. The roles find each other without fixed addresses. OneFlow hands the
storage address to the portal and the workers, and the storage role asks OneGate which VM
plays the portal and grants root on the home export to that address alone, so the workers
keep `root_squash`.

## Scaling the worker pool

The pool grows and shrinks on its own. Every worker reports its open session count to
OneGate, OneFlow adds a VM when the average passes one session per worker or when every
worker holds `ONEAPP_WORKER_MAX_SESSIONS` sessions, and removes one when the oldest worker has been empty for `ONEAPP_WORKER_IDLE_SECONDS`, ten minutes by
default. It shrinks one VM at a time, so a single long session keeps one worker, not six.
The portal sends each new session to the least loaded worker and, among equals, to the
youngest, so a VM added by the autoscaler receives work as soon as it is ready, which takes
under a minute, and the oldest one drains as its sessions end. OneFlow always removes the
oldest VM of the role, so a long session on the oldest worker holds the pool at its size
until it ends.

To change the pool by hand:

```shell
$ oneflow scale <service_id> worker <cardinality>
```

The role accepts from 1 to 6 workers. Raise `max_vms` in the service template for a larger
pool.

## Worker sizes

Every role whose name starts with `worker` is a pool of session VMs, and the portal offers
the sizes that exist as a "Worker size" field in each application form, with `worker` as
`Standard`. To add a larger size, copy the `worker` role in the service template under a
new name, `worker_large` for instance, and give it the CPU and memory you want:

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
VM, because OneFlow scales a role from its metrics and a role with no VM has none. A session
asked for a size with no live worker falls back to the whole pool.

## The desktop

The Xfce Desktop application opens a Linux desktop on a worker VM inside the browser. The
session starts a TurboVNC server on the VM, runs Xfce under its display and bridges the
display with websockify; the portal serves noVNC and proxies the websocket through its
`/rnode` route, so the user needs nothing beyond port 443 of the portal. The desktop uses
the same worker pool, the same home and the same EESSI catalogue as the notebooks: a terminal
opened on it has `module load`. The form asks for the resolution and the session hours, and
for the worker size when the service has more than one. The desktop packages live on the
worker VM and reach the container through the bind of `/usr` and `/etc`.

## GPU workers, prepared

A worker role with a GPU is a `worker_gpu` role in the service template, [as any other
size](#worker-sizes), whose `vm_template_contents` also carries the PCI device of the host,
as the [NVIDIA GPU passthrough](https://docs.opennebula.io/7.4/product/cluster_configuration/pci_passthrough_sriov/nvidia_gpu_passthrough/)
page describes:

```text
PCI = [ VENDOR = "10de", DEVICE = "<device id>", CLASS = "0302" ]
```

The session containers run through `/usr/local/bin/apptainer-gpu`, which adds `--nv` when
the VM has an NVIDIA device and its driver, so a session on such a worker sees the GPU. The
image ships no NVIDIA driver, so the site installs it on the GPU role, with a customised
image or at boot. This was prepared without a GPU to test on, and a site with one should
run `nvidia-smi` inside a session before offering the size to users.

## Batch jobs with Slurm

The VM pool has no scheduler. For a queue, a walltime and node accounting, attach the
official OneSlurm service from the marketplace and the portal offers it as a second cluster
in the Job Composer and in Active Jobs, while the interactive applications keep running on
the pool. The Slurm cluster shares the users and the home with the portal, so nothing is
copied and a job writes its output into the same home the notebooks use.

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

3. Once OneSlurm is `RUNNING`, give the portal the address of the controller. The portal
   reconfigures itself in under a minute and the cluster appears:

   ```shell
   $ onevm updateconf <portal vm id> --append <<EOF
   CONTEXT = [ ONEAPP_SLURM_CONTROLLER = "<controller compute address>" ]
   EOF
   ```

`ONEAPP_SLURM_CONTROLLER` is also a service input, for a controller that exists before the
service does. The portal installs no Slurm client: `sbatch`, `squeue`, `scancel`, `sinfo`,
`sacct` and `scontrol` run on the controller over SSH as the user, with the key the portal
keeps in each user's home, the same mechanism the AWS and Azure integrations use.
Accounting history in `sacct` depends on OneSlurm running `slurmdbd`, which its default
deployment does not. `docs/slurmdbd-setup.sh` next to this README adds it to the
controller (MariaDB, `slurmdbd`, the accounting lines in `slurm.conf` and the cluster
registration); with it, `sacct` from the portal lists the finished jobs of the user.

## An external identity provider

With `ONEAPP_OIDC_ISSUER`, `ONEAPP_OIDC_CLIENT_ID` and `ONEAPP_OIDC_CLIENT_SECRET` set, the
login page offers the provider beside the local directory, through the OpenID Connect
connector of Dex, with `https://<ONEAPP_OOD_SERVERNAME>/dex/callback` as the redirect URI to
register at the provider. A user who signs in that way still needs an account in the
directory under the same name, the `preferred_username` claim or the part of the email
before the at sign, because a session runs as a Unix user with a home. Verified against a
Dex provider that sends no `preferred_username`: the email fallback mapped the user.

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

**An NFS server you already run.** Set `ONEAPP_NFS_SERVER` and `ONEAPP_NFS_EXPORT` and the
portal and the workers mount that export instead of the storage role. The server has to
export it with `no_root_squash` for the portal address, the role that creates each home on
first login, and can keep `root_squash` for the workers. The storage role still runs the
software cache, so it stays in the service.

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
`ood_worker_active_sessions`, `ood_worker_idle`, `ood_worker_idle_seconds` and
`ood_worker_healthy`, read from what the workers publish to OneGate, plus
`ood_role_cardinality` per role and `ood_portal_puns`, the per user web servers running on
the portal. The same values are in the user template of each worker VM:

```shell
$ onevm show <worker id> | grep -E 'ACTIVE_SESSIONS|IDLE|HEALTHY|SESSION_USERS'
```

`SESSION_USERS` lists who has a session on the worker and since when, as `user:epoch`
entries, so the VM accounting of OpenNebula can be attributed to users.

A worker checks its home mount, the software catalogue and sshd before every report and
publishes `HEALTHY=0` when one of them is missing. The portal sends no new session to a
worker in that state, and the log of the check is on the worker, `journalctl -t ood-publish-load`.

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
2. On the portal, `cat /var/lib/ood-pool/workers.json` lists the workers the portal will use.
   `"source":"onegate"` means the list comes from the service; `"rango"` means OneGate did
   not answer and the portal probed the address range instead. A worker missing from the
   list is either not answering on port 22 or publishing `HEALTHY=0`.
3. The session directory under the user's home has `connection.yml`, with the worker the
   session ran on, and `output.log`, with what failed there. `module load` errors point at the software catalogue, `Permission denied`
   on the home points at the export, and a refused SSH connection at the `from=` restriction on
   the user's key, which only admits connections from the compute network.
4. On the worker, `journalctl -t ood-publish-load` shows what the health check found, and
   `runuser -u <user> -- ls /cvmfs/software.eessi.io/versions` whether the catalogue is
   reachable as that user.

## Upgrading

A new version of the appliance is a new image and new templates, and the running service
keeps the old ones. Download the new version from the marketplace, which imports them
beside the old ones, and instantiate a new service from the new service template. The home
survives the change when it lives on a persistent disk or on an NFS server of your own, as
[Keeping the home](#keeping-the-home) describes: delete the old service, attach the same
disk to the new one or point it at the same export, and the users find their files. With
the home on the storage VM's root disk, copy it out with `onevm disk-saveas` before
deleting the old service. Users, the LDAP directory, are recreated from `ONEAPP_LDAP_USERS`,
so pass the same value or add the users again once the new portal is up.

## Limitations and operating mode

* Interactive sessions run on VMs without a scheduler. A worker holds every session that
  lands on it, and a session uses the whole VM, shared with the other sessions on the same
  VM. Batch jobs can go to a Slurm cluster instead, see above.
* GPU workers are prepared but untested, see above.
* The scientific software comes from EESSI over CernVM-FS. The first load of a module on a
  fresh deployment downloads it through the site cache on the storage role.

## Versions and licence

Open OnDemand 4.2 on Ubuntu 24.04, EESSI 2025.06, Apptainer 1.5, TurboVNC 3.3.1 and Xfce
4.18 for the desktop. Open OnDemand is
[MIT licensed](https://github.com/OSC/ondemand/blob/master/LICENSE.txt) and the appliance
code is Apache 2.0, like the rest of this repository. There is no fee for the appliance, and
it runs on your own OpenNebula, so it costs what the VMs it creates cost.

## Release notes

See the [changelog](CHANGELOG.md).
