# Changelog

All notable changes to the OpenNebula Front-end appliance are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0] - 2026-06-18

### Added

- Initial release: a single-VM OpenNebula front-end built with the upstream
  miniONE installer on Ubuntu 24.04 LTS. miniONE pulls the latest OpenNebula
  release by default (pinnable via `ONEAPP_ONE_VERSION`).
- `Front-end + KVM node` mode (default): front-end (oned, FireEdge, OneGate,
  OneFlow) plus a co-located local KVM/QEMU node, a default lab virtual network
  and a sample marketplace template.
- `Front-end only` mode: front-end only, for managing external KVM hosts.
- Automatic KVM/QEMU detection through miniONE, with graceful fallback to
  software emulation when the host has no nested virtualization.
- OneForm (`opennebula-form`) installed by default so the front-end can
  provision more KVM nodes and clusters via `oneprovision` (Terraform plus
  Ansible/OneDeploy). Toggle with `ONEAPP_ONE_FORM`.
- Contextualization parameters: `ONEAPP_ONEADMIN_PASSWORD`, `ONEAPP_ONE_MODE`,
  `ONEAPP_ONE_VERSION`, `ONEAPP_ONE_FORM`, `ONEAPP_ONE_VNET_ADDRESS`,
  `ONEAPP_ONE_SSHKEY`.
- Random `oneadmin` password generation (persisted `0600`, reused across
  reboots) when none is supplied, surfaced in the VM report.
- Firewall (ufw) opening the front-end ports (2616, 2633, 2474, 5030, 29876, 80,
  22), `one-status` helper and a login MOTD with the FireEdge URL and credentials.
