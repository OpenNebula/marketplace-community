#!/usr/bin/env bash

exec 1>&2
set -eux -o pipefail

nixos-install

sync
