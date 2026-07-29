# NetworkManager/Netplan Conflict Fix

## Problem

When Ubuntu VMs boot with one-context >= 6.1, NetworkManager can create netplan configuration files (`90-NM-*.yaml`) that override the one-context generated configuration (`50-one-context.yaml`). This causes:

- VMs to have no IP address or wrong IP
- Network connectivity failures
- Context network configuration being ignored

## Root Cause

The `80-install-context.sh` script installs both `netplan.io` and `network-manager`:
```bash
apt-get install -y --no-install-recommends --no-install-suggests netplan.io network-manager
```

NetworkManager then:
1. Auto-detects network connections
2. Generates its own netplan configs with higher priority (90-NM-*.yaml)
3. These override one-context's 50-one-context.yaml

## Solution

The fix has three parts:

1. **Force networkd renderer**: Create `/etc/netplan/00-one-defaults.yaml` that sets `networkd` as the default renderer
2. **Unmanage ethernet in NM**: Create `/etc/NetworkManager/conf.d/99-one-unmanaged.conf` to prevent NM from managing eth*/ens*/enp* interfaces
3. **Early-boot cleanup**: Create `/etc/one-context.d/loc-05-cleanup-nm-netplan` that removes stray NM configs before network configuration

## How to Apply

### Option 1: Replace the context install script (recommended)

Replace the packer script with the fixed version:

```bash
sudo cp wizard/patches/80-install-context.sh.fixed \
    /root/marketplace-community/apps-code/one-apps/packer/ubuntu/80-install-context.sh
```

### Option 2: Add as separate provisioner script

Copy the fix script to your packer build:

```bash
sudo cp wizard/patches/85-fix-netplan-nm-conflict.sh \
    /root/marketplace-community/apps-code/one-apps/packer/ubuntu/
```

Then add it to your packer HCL after the context install:

```hcl
provisioner "shell" {
  scripts = [
    "80-install-context.sh",
    "85-fix-netplan-nm-conflict.sh",  # Add this line
  ]
}
```

### Option 3: Apply to existing running VM

For VMs already deployed, SSH in and run:

```bash
# 1. Create default netplan config
cat > /etc/netplan/00-one-defaults.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
EOF

# 2. Configure NetworkManager to not manage ethernet
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-one-unmanaged.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:eth*;interface-name:ens*;interface-name:enp*
EOF

# 3. Create cleanup script
cat > /etc/one-context.d/loc-05-cleanup-nm-netplan << 'EOF'
#!/bin/bash
rm -f /etc/netplan/90-NM-*.yaml 2>/dev/null
rm -f /etc/NetworkManager/system-connections/netplan-* 2>/dev/null
exit 0
EOF
chmod +x /etc/one-context.d/loc-05-cleanup-nm-netplan

# 4. Clean up existing bad configs and apply
rm -f /etc/netplan/90-NM-*.yaml
netplan generate && netplan apply

# 5. Reboot to verify
reboot
```

## Files in this directory

| File | Description |
|------|-------------|
| `80-install-context.sh.fixed` | Complete replacement for the packer script |
| `85-fix-netplan-nm-conflict.sh` | Standalone fix script to add to packer builds |
| `fix-netplan-nm-conflict.patch` | Unified diff patch (may need manual adjustment) |

## Verification

After applying, verify the fix works:

```bash
# Check netplan configs (should NOT have 90-NM-*.yaml)
ls -la /etc/netplan/

# Check renderer is networkd
cat /etc/netplan/00-one-defaults.yaml

# Check NM unmanaged config
cat /etc/NetworkManager/conf.d/99-one-unmanaged.conf

# Check cleanup script exists
ls -la /etc/one-context.d/loc-05-cleanup-nm-netplan
```

## Affected Distributions

This fix applies to:
- Ubuntu 22.04 (ubuntu2204, ubuntu2204min)
- Ubuntu 24.04 (ubuntu2404, ubuntu2404min)
- Debian 11, 12 (similar fix needed for debian scripts)

## Related Issues

- Wizard Issue #1: Bridge missing gateway IP (fixed separately in appliance-wizard.sh)
- Wizard Issue #2: VM netplan conflicts (this fix)
