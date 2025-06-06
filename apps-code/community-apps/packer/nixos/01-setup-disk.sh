#!/usr/bin/env bash

exec 1>&2
set -eux -o pipefail

sfdisk /dev/vda <<< ';'

mkfs.ext4 -L nixos /dev/vda1

mount LABEL=nixos /mnt/

sync
