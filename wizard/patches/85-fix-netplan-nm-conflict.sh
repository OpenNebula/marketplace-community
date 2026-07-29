#!/usr/bin/env bash

# Fix NetworkManager/netplan conflict in Ubuntu VMs
# This script should be run AFTER 80-install-context.sh in packer builds
#
# Problem: NetworkManager creates 90-NM-*.yaml netplan configs that override
#          one-context's 50-one-context.yaml, causing network configuration failures
#
# Solution:
# 1. Force netplan to use networkd renderer via default config
# 2. Configure NetworkManager to not manage ethernet interfaces
# 3. Add early-boot cleanup script to remove stray NM configs
#
# Usage in packer:
#   Copy this script to packer/ubuntu/85-fix-netplan-nm-conflict.sh
#   Add to your packer provisioners after 80-install-context.sh

exec 1>&2
set -eux -o pipefail

echo "Applying NetworkManager/netplan conflict fix..."

# Only apply if NetworkManager and netplan are installed
if ! command -v nmcli &>/dev/null || ! command -v netplan &>/dev/null; then
    echo "NetworkManager or netplan not installed, skipping fix"
    exit 0
fi

# 1. Force netplan to use networkd renderer (prevents NM conflicts)
# This config has lowest priority (00-) so it sets defaults
mkdir -p /etc/netplan
cat > /etc/netplan/00-one-defaults.yaml << 'NETPLAN_DEFAULTS'
# OpenNebula default netplan configuration
# Forces networkd as renderer to prevent NetworkManager conflicts
# one-context will generate 50-one-context.yaml with actual network config
network:
  version: 2
  renderer: networkd
NETPLAN_DEFAULTS
chmod 644 /etc/netplan/00-one-defaults.yaml
echo "Created /etc/netplan/00-one-defaults.yaml"

# 2. Configure NetworkManager to not manage ethernet interfaces
# These interfaces are managed by one-context via netplan/networkd
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-one-unmanaged.conf << 'NM_UNMANAGED'
# OpenNebula: Prevent NetworkManager from managing ethernet interfaces
# Network configuration is handled by one-context via netplan/networkd
[keyfile]
unmanaged-devices=interface-name:eth*;interface-name:ens*;interface-name:enp*
NM_UNMANAGED
chmod 644 /etc/NetworkManager/conf.d/99-one-unmanaged.conf
echo "Created /etc/NetworkManager/conf.d/99-one-unmanaged.conf"

# 3. Create early-boot cleanup script for any stray NM netplan configs
# Runs BEFORE loc-10-network (which does the actual network configuration)
cat > /etc/one-context.d/loc-05-cleanup-nm-netplan << 'CLEANUP_SCRIPT'
#!/bin/bash
# Cleanup conflicting NetworkManager netplan configurations
# Runs before loc-10-network to ensure clean state for one-context

# Remove any NetworkManager-generated netplan files
rm -f /etc/netplan/90-NM-*.yaml 2>/dev/null

# Remove any stale NetworkManager connections from netplan
rm -f /etc/NetworkManager/system-connections/netplan-* 2>/dev/null

exit 0
CLEANUP_SCRIPT
chmod 755 /etc/one-context.d/loc-05-cleanup-nm-netplan
echo "Created /etc/one-context.d/loc-05-cleanup-nm-netplan"

# 4. Ensure systemd-networkd is enabled (it's the actual network manager)
systemctl enable systemd-networkd 2>/dev/null || true
echo "Enabled systemd-networkd"

# 5. Clean up any existing problematic configs from the build
rm -f /etc/netplan/90-NM-*.yaml 2>/dev/null || true
rm -f /etc/NetworkManager/system-connections/netplan-* 2>/dev/null || true

echo "NetworkManager/netplan conflict fix applied successfully"

sync
