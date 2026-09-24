# CernVM-FS Proxy

[CernVM-FS](https://cernvm.cern.ch/fs/) delivers software to many machines over HTTP. Every
client keeps a local cache, and the
[CernVM-FS documentation](https://cvmfs.readthedocs.io/en/stable/cpt-squid.html) asks a site
to put an HTTP proxy between its clients and the internet. This appliance is that proxy, one
VM with [Squid](https://www.squid-cache.org/) on port 3128. A file comes from the internet
once, and every later client reads it from the cache of the proxy.

Any CernVM-FS client can use it. It can be a plain VM, the nodes of a Slurm or Kubernetes
cluster, or an Open OnDemand service. The [EESSI](https://www.eessi.io/) software catalogue
works by default, and any other public repository works after you add its domain.

## Requirements

* OpenNebula 6.10 or 7.4.
* A Virtual Network with access to the internet on ports 80 and 8000, where the CernVM-FS
  servers answer in plain HTTP.
* The clients reach the proxy on port 3128. Put a NIC of the proxy on the network of the
  clients, or route between the two networks. Clients behind a router without NAT keep the
  address of their own network, so add that network to `ONEAPP_ACCESS_CLIENTS_NETWORKS`, or
  the proxy answers them with 403.
* [OneGate](https://docs.opennebula.io/7.4/product/virtual_machines_operation/multi-vm_workflows/onegate_usage/)
  is optional. With OneGate, the VM publishes its URL and its state as attributes.

The default VM has 2 vCPU, 2 GB of memory and a 30 GB system disk. The disk holds the default
cache of 20000 MB with room for the system.

## Quick start

1. Export the appliance from the Community Marketplace. You get the image and a VM template.

   ```
   onemarketapp export 'CernVM-FS Proxy' cvmfs-proxy --datastore default
   ```

2. Instantiate the VM template on a network with internet access. The defaults need no
   change for EESSI.

3. Wait for the VM to report `READY=YES`, about one minute after boot. Read the URL of the
   proxy in the `CVMFS_PROXY_URL` attribute of the VM, or in `/etc/one-appliance/config` on
   the VM.

4. On each client, point CernVM-FS at the proxy, as in [Clients](#clients).

## Contextualization

| Parameter | Default | Description |
|---|---|---|
| `ONEAPP_ACCESS_CLIENTS_NETWORKS` | empty | Networks that may use the proxy, in CIDR notation, separated by spaces, for example `10.0.0.0/24 192.168.1.0/24`. Empty allows only the network of the first NIC of the proxy. |
| `ONEAPP_ACCESS_DESTINATIONS_DOMAINS` | `.cern.ch .gridpp.rl.ac.uk .opensciencegrid.org .eessi.science` | Domains of the CernVM-FS servers the proxy may download from. A leading dot also allows every host under the domain. Empty takes the default. |
| `ONEAPP_CACHE_SIZE_DISK` | `20000` | Size of the disk cache in MB. |
| `ONEAPP_CACHE_SIZE_MEMORY` | `1024` | Size of the memory cache (`cache_mem`) in MB. |
| `ONEAPP_CACHE_DISK_ENABLED` | `NO` | Keep the disk cache on a second disk. |
| `ONEAPP_CACHE_DISK_DEVICE` | empty | Device of the second disk. Empty finds it automatically. |

The VM checks every value before it writes `/etc/squid/squid.conf`, and a wrong value stops
the boot. The reason appears in the `ERROR` attribute of the VM and in
`/var/log/one-appliance/configure.log`. The appliance writes `squid.conf` again on every boot,
so change the context and reboot the VM instead of editing the file.

The configuration follows the CernVM-FS documentation for the cache and the EESSI template
for the access rules. The default domains are the ones of the EESSI template plus
`.gridpp.rl.ac.uk`. Every client reads the configuration repository `cvmfs-config.cern.ch`,
and one of its servers lives in that domain. Clients that set `CVMFS_USE_CDN=yes` download
from `openhtc.io` servers instead, so add `.openhtc.io` to the list for them.

* `collapsed_forwarding on`, so many clients that ask for the same file at once cause one
  download.
* `minimum_expiry_time 0`, `maximum_object_size 1024 MB`, `maximum_object_size_in_memory 128 KB`.
* `cache_dir ufs /var/spool/squid` with the size of `ONEAPP_CACHE_SIZE_DISK`.
* The proxy refuses any client outside the client networks, any destination outside the
  domain list, and any `CONNECT` tunnel. Localhost is always allowed.
* The domain list uses `dstdomain -n`, so a URL with an address in place of a host name is
  refused. Squid does not trust the reverse DNS name of that address.

## Cache on a second disk

In the Sunstone wizard, turn on `ONEAPP_CACHE_DISK_ENABLED` in the Cache tab, and add the disk
in the Storage tab of the Advanced options step, for example an empty volatile disk of the size
you want. The proxy looks for the only disk of the VM that is not the system disk, so the disk
works whatever name it gets inside the VM, `/dev/sda` with the default device prefix or
`/dev/vdb` with the `vd` prefix. With more than one extra disk, name the cache disk in
`ONEAPP_CACHE_DISK_DEVICE`.

* A blank disk is formatted as ext4 and mounted at `/var/spool/squid`, with `nosuid`,
  `nodev` and `noexec`.
* A disk that already has an ext4 file system is mounted as it is. A cache on a persistent
  disk survives a new VM.
* Any other disk stops the boot, and the appliance never formats it. The same happens with
  the system disk or a disk already mounted somewhere else.

The disk cache must fit in the disk that holds it, with a tenth of the space left free,
because Squid stops when its disk fills. The memory cache needs half a GB of free memory next
to it.

## Clients

On an Ubuntu client, install CernVM-FS and the configuration of EESSI, as the
[EESSI documentation](https://www.eessi.io/docs/getting_access/native_installation/)
describes.

```
wget https://cvmrepo.s3.cern.ch/cvmrepo/apt/cvmfs-release-latest_all.deb
sudo dpkg -i cvmfs-release-latest_all.deb
sudo apt-get update
sudo apt-get install -y cvmfs
wget https://github.com/EESSI/filesystem-layer/releases/download/latest/cvmfs-config-eessi_latest_all.deb
sudo dpkg -i cvmfs-config-eessi_latest_all.deb
```

Then write the proxy in `/etc/cvmfs/default.local` and apply it.

```
CVMFS_CLIENT_PROFILE="single"
CVMFS_HTTP_PROXY="http://<address of the proxy>:3128"
CVMFS_QUOTA_LIMIT=10000
```

`CVMFS_QUOTA_LIMIT` is the size in MB of the local cache of the client, in `/var/lib/cvmfs`.
Keep it below the free space of the client disk. A OneSlurm worker has a 10 GB disk with about
4.5 GB free, so 3000 fits there.

```
sudo cvmfs_config setup
cvmfs_config probe software.eessi.io
cvmfs_config stat -v software.eessi.io
```

The last command shows `Connection: http://... through proxy http://<address of the proxy>:3128 (online)`.

For the workers of a OneSlurm cluster, `clients/oneslurm-start.sh` in this directory does the
same at boot, and holds each job until `/cvmfs` works on its node. Its header says how to use it.

For two proxies, deploy two VMs and join their URLs with `|`, for example
`CVMFS_HTTP_PROXY="http://10.0.0.5:3128|http://10.0.0.6:3128"`. The clients share the load
between the two proxies and use the other one when one fails. Add `;DIRECT` at the end only
if the clients may go to the internet when every proxy fails.

## Checking the proxy

From a client, fetch the file that the EESSI documentation uses to test a proxy.

```
http_proxy=http://<address of the proxy>:3128 curl --head \
    http://aws-eu-central-s1.eessi.science/cvmfs/software.eessi.io/.cvmfspublished
```

The first line is `HTTP/1.1 200 OK`. A 403 means the client is not in the client networks or
the server is not in the domain list. After an outage of the proxy, the clients mount the
repositories again by themselves within about two minutes. Every request appears in
`/var/log/squid/access.log` on the proxy, where `TCP_HIT` and `TCP_MEM_HIT` are files served
from the cache.

## Limits

* x86_64 only for now.
* One VM is one proxy. For redundancy deploy a second one and list both on the clients.
* The proxy speaks plain HTTP. CernVM-FS signs its repositories, so the clients verify every
  file they receive.
