#!/usr/bin/env bash

exec 1>&2
set -eux -o pipefail

nixos-enter -c 'nix-collect-garbage -d'

truncate -s0 -c /mnt/etc/machine-id

rm -f /mnt/etc/resolv.conf

sync
