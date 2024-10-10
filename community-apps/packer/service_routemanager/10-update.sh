#!/usr/bin/env ash

# Install required packages and upgrade the distro.

exec 1>&2
set -eux -o pipefail

service haveged stop ||:             # why ?

apk update

apk add bash curl ethtool gawk grep iproute2 jq ruby sed tcpdump    # only ethtool, iproute2 and tcpdump come as not preinstalled

sync