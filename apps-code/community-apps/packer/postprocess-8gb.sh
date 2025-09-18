#!/usr/bin/env bash
set -ex

# First resize the image to 8GB
echo "Resizing image to 8GB..."
qemu-img resize ${OUTPUT_DIR}/${APPLIANCE_NAME} 8G

timeout 5m virt-sysprep \
    --add ${OUTPUT_DIR}/${APPLIANCE_NAME} \
    --selinux-relabel \
    --root-password disabled \
    --hostname localhost.localdomain \
    --run-command 'truncate -s0 -c /etc/machine-id' \
    --delete /etc/resolv.conf

# virt-sparsify hang badly sometimes, when this happends
# kill + start again
timeout -s9 5m virt-sparsify --in-place ${OUTPUT_DIR}/${APPLIANCE_NAME}

echo "Final image info:"
qemu-img info ${OUTPUT_DIR}/${APPLIANCE_NAME}
