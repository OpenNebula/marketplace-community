# Open OnDemand

[Open OnDemand](https://openondemand.org/) gives HPC users a browser interface to a
cluster: a file browser, a shell, job submission and interactive applications. This
appliance runs it on OpenNebula, with an elastic pool of compute VMs behind it.

## One image, three roles

The three roles of the service run from the same image. `ONEAPP_ROLE` decides at boot which
role a VM plays, and the OneFlow template sets it per role.

| Role | What it runs | Cardinality |
|---|---|---|
| `storage` | NFS server for the shared home, site cache for the software catalogue | 1 |
| `portal` | Open OnDemand, its LDAP directory and Dex authentication | 1 |
| `worker` | User sessions, inside Apptainer containers | 1 to N, elastic |

One image instead of three because it is one thing to build, publish and document, and
because the OneKS appliance is packaged the same way, with one image for the control plane
and for the nodes.

## What a session runs

Scientific software comes from [EESSI](https://www.eessi.io/) over CernVM-FS, cached by the
storage role. A notebook opened here loads the same modules a user would find at a EuroHPC
centre, so nothing has to be installed per site. The catalogue is read only and shared, and
the container is only there to isolate the processes of one session from another.

The applications shipped are JupyterLab, Octave, a C++ notebook, RStudio and VS Code.

## How the pool grows

Every worker reports its open session count to OneGate. OneFlow adds a VM when the average
passes the threshold and removes one after a quiet period. Resizing the role is only half of
the work, because the portal also has to send new sessions to the new VM and the
`linux_host` adapter sends everything to a single fixed host by default. So the portal keeps
a roster of live workers and sends each new session to the least loaded one, and without
that an added worker would sit idle.

A worker created from this image is ready in well under a minute, because everything that
only depends on the internet is already inside the image and only the addresses of the
deployment are applied at boot.

## Requirements

- [OneFlow](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/overview.html)
  and [OneGate](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/onegate_usage.html).
- OneGate reachable from the service network. In a deployment without a virtual router the
  appliance uses the gateway of the VM instead, but the requirement stands.
- A compute network **reserved for the service**. The portal treats every live address in
  the declared range as a worker, so nothing else may live there.
- Outbound access to the EESSI CernVM-FS servers from the storage role, which is the only
  role that needs it.

## Parameters

Common to every role:

| Parameter | Meaning |
|---|---|
| `ONEAPP_ROLE` | `portal`, `storage` or `worker` |

Role `storage`:

| Parameter | Meaning |
|---|---|
| `ONEAPP_NFS_ADMIN_IPS` | addresses allowed to act as root on the shared home, that is the portal |
| `ONEAPP_NFS_NET` | network allowed to mount the shared home |
| `ONEAPP_SQUID_NETS` | networks allowed to use the site cache |

Role `portal`:

| Parameter | Meaning |
|---|---|
| `ONEAPP_NFS_HOST` | address of the storage role |
| `ONEAPP_CVMFS_PROXY` | URL of the site cache |
| `ONEAPP_POOL_RANGE` | address range reserved for the compute pool, `first-last` |
| `ONEAPP_OOD_SERVERNAME` | public hostname of the portal |
| `ONEAPP_OOD_SSL_MODE` | `letsencrypt` or `selfsigned` |
| `ONEAPP_LDAP_USERS` | initial users, `user:password:uid` separated by spaces |

Role `worker`:

| Parameter | Meaning |
|---|---|
| `ONEAPP_NFS_HOST` | address of the storage role |
| `ONEAPP_LDAP_HOST` | address of the portal role |
| `ONEAPP_CVMFS_PROXY` | URL of the site cache |

## After deployment

The portal answers on `https://<ONEAPP_OOD_SERVERNAME>/`. Sign in with one of the users
given in `ONEAPP_LDAP_USERS`, and the home directory is created on first login. Adding a user
later is one entry in the directory on the portal role, and their home and their sessions
follow from that entry.

Each role logs what it did at boot in `/var/log/ood-appliance-configure.log`, and
`/etc/one-ondemand/build.env` records what the image was built from.
