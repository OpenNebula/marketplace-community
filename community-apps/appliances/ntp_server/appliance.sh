# ---------------------------------------------------------------------------- #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #
set -o errexit -o pipefail


# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_NTP_SERVERS'            'configure'  'List of NTP Servers to use as Upstream'                                      'O|text'
    'ONEAPP_TZ'                    'configure'  'Timezone defined by IANAA https://ftp.iana.org/tz/tzdb-2020f/zone1970.tab'   'O|text'
)


### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Service NTP SERVER - KVM'
ONE_SERVICE_VERSION='0.0.1'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with a NTP SERVER'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled NTP Server based on Chronyc.

The parameter ONEAPP_NTP_SERVERS and ONEAPP_TZ are mandatory.
- ONEAPP_NTP_SERVERS is the list of NTP servers that you want to use as Upstream servers.
- ONEAPP_TZ is the timezone defined by IANAA.
EOF
)

ONE_SERVICE_RECONFIGURABLE=true

### Contextualization defaults #######################################

ONEAPP_NTP_SERVERS="${ONEAPP_NTP_SERVERS:-time.cloudflare.com}"
ONEAPP_TZ="${ONEAPP_TZ:-Europe/Madrid}"

### Globals ##########################################################

DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"

###############################################################################
###############################################################################
###############################################################################

#
# service implementation
#

service_install()
{
    msg info "Checking internet access..."
    check_internet_access
    # ensuring that the setup directory exists
    #TODO: move to service
    mkdir -p "$ONE_SERVICE_SETUP_DIR"
    export DEBIAN_FRONTEND=noninteractive

    #Upgrade Operating System
    upgrade_ubuntu

    # docker
    install_docker

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    msg info "CONFIGURE FINISHED"
    return 0
}

service_bootstrap()
{
    run_ntp_server
    msg info "BOOTSTRAP FINISHED"
    return 0
}

###############################################################################
###############################################################################
###############################################################################

#
# functions
#
check_internet_access() {
    # Ping Google's public DNS server
    if ping -c 1 8.8.8.8 &> /dev/null; then
        msg info "Internet access OK"
        return 0
    else
        msg error "The VM does not have internet access. Aborting NTP Server deployment..."
        exit 1
    fi
}

upgrade_ubuntu()
{
    apt update -y
    apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" dist-upgrade \
    -q -y --allow-downgrades --allow-remove-essential --allow-change-held-packages
}

install_docker()
{
    msg info "Add Docker official GPG key"
    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    msg info "Add Docker repository to apt sources"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update

    msg info "Install Docker Engine"
    if ! apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-buildx-plugin docker-compose-plugin ; then
        msg error "Docker installation failed"
        exit 1
    fi
}

run_ntp_server()
{
    docker rm -f ntp
    docker pull cturra/ntp
    docker run -tid --name=ntp --restart=always --publish=123:123/udp --env=NTP_SERVERS="$ONEAPP_NTP_SERVERS" --env=TZ="$ONEAPP_NTP_TZ" cturra/ntp
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

