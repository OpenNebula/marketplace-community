#!/usr/bin/env bash
set -ex

# Custom postprocess script for Phoenix RTOS appliance
# This version preserves the root password instead of disabling it

timeout 5m virt-sysprep \
    --add ${OUTPUT_DIR}/${APPLIANCE_NAME}.qcow2 \
    --selinux-relabel \
    --hostname localhost.localdomain \
    --run-command 'truncate -s0 -c /etc/machine-id' \
    --delete /etc/resolv.conf

# Note: Removed --root-password disabled to preserve the password set via context

# virt-sparsify hang badly sometimes, when this happends
# kill + start again
timeout -s9 5m virt-sparsify --in-place ${OUTPUT_DIR}/${APPLIANCE_NAME}.qcow2

# Move the final image to the export directory with proper naming
mkdir -p ../one-apps/export/
cp ${OUTPUT_DIR}/${APPLIANCE_NAME}.qcow2 ../one-apps/export/${APPLIANCE_NAME}.qcow2
echo "✅ Final image created: ../one-apps/export/${APPLIANCE_NAME}.qcow2"
