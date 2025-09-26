#!/usr/bin/env bash

# Configure OpenNebula context for the appliance

exec 1>&2
set -eux -o pipefail

export DEBIAN_FRONTEND=noninteractive

# Install context packages if not already installed
if ! dpkg -l | grep -q one-context; then
    wget -q -O- https://downloads.opennebula.io/repo/repo2.key | apt-key add -
    echo "deb https://downloads.opennebula.io/repo/6.8/Ubuntu/22.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list
    apt-get update
    apt-get install -y opennebula-context
fi

# Enable context service
systemctl enable one-context.service

sync
