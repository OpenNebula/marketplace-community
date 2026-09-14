# Open OnDemand

[Open OnDemand](https://openondemand.org/) gives HPC users a browser interface to a
cluster: a file browser, a shell, job submission and interactive applications. This
appliance runs it on OpenNebula as a OneFlow service with an elastic pool of compute VMs
behind the portal. A user signs in, presses a button and gets a JupyterLab notebook,
RStudio, Octave, a C++ notebook or VS Code running on a compute VM, with the scientific
software served from the [EESSI](https://www.eessi.io/) catalogue and a home directory
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

5. Open the portal. Its address is the one you gave as `ONEAPP_OOD_SERVERNAME`, or the
   management address of the portal VM if you left it empty:

   ```shell
   $ onevm list -f NAME~portal -l ID,NAME,IP
   ```

   Then go to `https://<ONEAPP_OOD_SERVERNAME>/` and sign in with one of the users given in
   `ONEAPP_LDAP_USERS`, by default `demo1` with password `demo1pass`. The home directory
   is created on first login.

## Service inputs

| Parameter | Service Default | Description |
|---|---|---|
| `ONEAPP_OOD_SERVERNAME` | empty | Public host name of the portal. It has to resolve to the management address of the portal VM. Empty makes the portal answer on that address. |
| `ONEAPP_OOD_SSL_MODE` | `selfsigned` | `selfsigned`, `letsencrypt` or `custom`. Let's Encrypt needs the host name to be public and port 80 reachable. `custom` installs the certificate given in the next two inputs. |
| `ONEAPP_OOD_SSL_CERT` | empty | PEM certificate chain for the `custom` mode. Paste the file, the form encodes it. |
| `ONEAPP_OOD_SSL_KEY` | empty | PEM private key for the `custom` mode. The service template passes it to the portal VM only. |
| `ONEAPP_LDAP_USERS` | `demo1:demo1pass:10001` | Initial users, as `user:password:uid` separated by spaces. |
| `ONEAPP_WORKER_IDLE_SECONDS` | `600` | How long the oldest worker stays empty before the pool loses a VM. |
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
OneGate, OneFlow adds a VM when the average passes one session per worker, and removes one
when the oldest worker has been empty for `ONEAPP_WORKER_IDLE_SECONDS`, ten minutes by
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

## Where to look when something is wrong

Each role logs what it did at boot in `/var/log/ood-appliance-configure.log`, and
`/etc/one-ondemand/build.env` records what the image was built from. A role that failed to
configure shows it in its `motd` and in `/etc/one-appliance/status`, and OneFlow keeps the
service out of `RUNNING` until every role has declared itself ready.

## Limitations and operating mode

* Sessions run on VMs without a scheduler. A worker holds every session that lands on it,
  and a session uses the whole VM, shared with the other sessions on the same VM.
* There is no GPU support in this release.
* The scientific software comes from EESSI over CernVM-FS. The first load of a module on a
  fresh deployment downloads it through the site cache on the storage role.

## Versions and licence

Open OnDemand 4.2 on Ubuntu 24.04, EESSI 2025.06, Apptainer 1.5. Open OnDemand is
[MIT licensed](https://github.com/OSC/ondemand/blob/master/LICENSE.txt) and the appliance
code is Apache 2.0, like the rest of this repository. There is no fee for the appliance, and
it runs on your own OpenNebula, so it costs what the VMs it creates cost.

## Release notes

See the [changelog](CHANGELOG.md).
