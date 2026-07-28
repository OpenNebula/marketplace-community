# Changelog

All notable changes to the Nextcloud All-in-One (aarch64) appliance will be documented in this file.

## [1.0.0-1] - 2026-06-19

### Added
- Initial aarch64/arm64 release of the Nextcloud All-in-One appliance
- Ubuntu 24.04 LTS (aarch64) base operating system
- Docker container: nextcloud/all-in-one:latest (multi-arch, arm64 native)
- VM template sets `OS = [ ARCH = "aarch64", FIRMWARE = "UEFI" ]`
- ARM64 serial console support (ttyAMA0) for the OpenNebula / virsh console
- VNC desktop access
- SSH key authentication
- OpenNebula context integration
- Configurable container parameters (ports, volumes, environment variables)

### Notes
- aarch64 sibling of the x86_64 `nextcloud-aio` appliance.
- Built natively on an arm64 KVM host (qemu-system-aarch64 + KVM + UEFI/AAVMF).
