#!/usr/bin/env bash
set -ex
# virt-sparsify hang badly sometimes, when this happends
# kill + start again
timeout -s9 5m virt-sparsify --in-place ${OUTPUT_DIR}/${APPLIANCE_NAME}
