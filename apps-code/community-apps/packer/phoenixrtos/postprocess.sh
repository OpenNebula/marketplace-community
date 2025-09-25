#!/usr/bin/env bash
set -ex

# Custom postprocess script for Phoenix RTOS appliance
# This version preserves the root password instead of disabling it

timeout 5m virt-sysprep \
    --add ${OUTPUT_DIR}/${APPLIANCE_NAME} \
    --selinux-relabel \
    --hostname localhost.localdomain \
    --run-command 'truncate -s0 -c /etc/machine-id' \
    --delete /etc/resolv.conf

# Note: Removed --root-password disabled to preserve the password set in appliance.sh

# virt-sparsify hang badly sometimes, when this happends
# kill + start again
timeout -s9 5m virt-sparsify --in-place ${OUTPUT_DIR}/${APPLIANCE_NAME}
