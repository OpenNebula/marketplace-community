# OpenNebula Front-end appliance

Deploy a complete [OpenNebula](https://opennebula.io) lab **inside** your own
OpenNebula cloud ("OpenNebula over OpenNebula"). A single Ubuntu 24.04 LTS VM
becomes a self-contained OpenNebula front-end using the upstream
[miniONE](https://github.com/OpenNebula/minione) installer, which pulls the
**latest OpenNebula release**.

## What you get

On first boot the appliance runs miniONE, which installs:

- The **OpenNebula front-end**: `oned`, the **FireEdge** web UI, **OneGate** and **OneFlow**.
- A co-located **local KVM/QEMU node** (in `Front-end + KVM node` mode), registered as a host so you can launch VMs immediately.
- A default **lab virtual network** with NAT so lab VMs get outbound connectivity.
- A sample marketplace image and VM template to try right away.

Hardware virtualization is detected automatically. If the underlying host
exposes nested virtualization, the lab uses **KVM**; otherwise it falls back to
**QEMU** software emulation (works everywhere, just slower).

> This is an evaluation, training and demo lab, not a production deployment.

## Quick start

1. Instantiate the appliance. Optionally set a `oneadmin` password and pick the
   deployment mode in the wizard (see the table below). If you leave the
   password empty, a random one is generated and written to the VM report.
2. Wait for first-boot provisioning to finish (a few minutes; longer under QEMU
   emulation). The VM reports ready through OneGate once miniONE completes.
3. Open the FireEdge web UI at `http://<vm-ip>:2616/fireedge` and log in as
   `oneadmin`.
4. SSH in as `root` and run `one-status` for a summary, or check
   `/var/log/one-appliance/minione.log` for the provisioning log.

## What to deploy (`ONEAPP_ONE_MODE`)

| Value | What it deploys |
|-------|-----------------|
| `Front-end + KVM node` (default) | Front-end **plus** a local KVM/QEMU node, lab vnet and a sample template. A complete single-VM lab that launches VMs locally. |
| `Front-end only` | Front-end **only**. Attach your own external KVM hosts. Lighter, no nested virtualization needed. |

## Adding more nodes (OneForm)

The single local node is enough to launch VMs, but to grow the lab into a
multi-node cloud the appliance ships [OneForm](https://docs.opennebula.io/7.2/product/cluster_provisioning/overview/),
OpenNebula's native infrastructure-provisioning engine (installed by default;
set `ONEAPP_ONE_FORM=NO` to skip it). OneForm provisions whole clusters of KVM
nodes (on-prem, bare-metal or cloud) using Terraform plus Ansible (OneDeploy),
and registers them with this front-end automatically. As `oneadmin` on the VM:

- `oneprovider` defines a Provider (where to provision).
- `oneprovision` deploys and scales a Provision (a cluster of nodes).
- `oneform` syncs the provider drivers from the OneForm registry.

This is the easy, OpenNebula-native alternative to manually installing
`opennebula-node-kvm` and running `onehost create` on each new host.

## Nested virtualization

To actually run guest VMs at usable speed, deploy the appliance on a host that
exposes nested virtualization:

- Host CPU passed through to the VM (`CPU_MODEL = host-passthrough`, already set
  in the appliance template).
- Nested KVM enabled on the host kernel (`kvm_intel nested=1` or `kvm_amd
  nested=1`).

Without nested virtualization the lab still works but inner VMs run under QEMU
emulation and are slow. The control plane (FireEdge, templates, images,
networks, OneFlow, OneGate) works regardless.

## Contextualization parameters

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ONEAPP_ONEADMIN_PASSWORD` | password | _(random)_ | Password for `oneadmin` and FireEdge. Auto-generated and reported if empty. |
| `ONEAPP_ONE_MODE` | list | `Front-end + KVM node` | `Front-end + KVM node` (full single-VM lab) or `Front-end only` (control plane for external hosts). |
| `ONEAPP_ONE_VERSION` | text | _(empty)_ | OpenNebula release to install. Empty installs the latest; set e.g. `7.2` to pin. |
| `ONEAPP_ONE_FORM` | boolean | `YES` | Install OneForm so the front-end can provision more KVM nodes and clusters. |
| `ONEAPP_ONE_VNET_ADDRESS` | text | `172.16.100.0` | Base address of the lab virtual network (`Front-end + KVM node` mode). |
| `ONEAPP_ONE_SSHKEY` | text64 | _(empty)_ | Extra SSH public key authorized for `root` (one-context already injects `$USER[SSH_PUBLIC_KEY]`). |

## Ports

| Port | Service |
|------|---------|
| 2616 | FireEdge web UI |
| 2633 | `oned` XML-RPC API |
| 2474 | OneFlow |
| 5030 | OneGate |
| 29876 | noVNC proxy |
| 80 | Sunstone proxy (if enabled by miniONE) |
| 22 | SSH |

## Requirements

- Internet access on first boot (miniONE pulls the latest OpenNebula packages and
  a sample marketplace image).
- Recommended sizing: 4 vCPU, 8 GiB RAM (more if you run several nested VMs).

## Credits

- [OpenNebula](https://opennebula.io) and [miniONE](https://github.com/OpenNebula/minione), Apache License 2.0.
