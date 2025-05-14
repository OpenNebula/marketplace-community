# ---------------------------------------------------------------------------- #
# Copyright 2024, OpenNebula Project, OpenNebula Systems                  #
#                                                                              #
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
    'ONEAPP_AMQP_URL'                  'configure'  'AMQP URL for message broker'                                      'O|text'
)


### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Lithops - Worker'
ONE_SERVICE_VERSION='3.4.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with preinstalled Lithops Worker for Lithops compute backend'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled Lithops Worker for Lithops Service.

This service connects to a RabbitMQ broker and listens for execution requests
sent by the Lithops client. Upon receiving a request, it will deserialize and
run the specified function, then return the result through the messaging system.

The connection to the message broker is configured via the AMQP_URL that will be constructed based on 
user imput parameter, becoming an AMQP URI (e.g. amqp://user:pass@host:5672/).

This worker appliance must be co-deployed with a compatible Lithops client and RabbitMQ
service in the same network.

Logs are written to /var/log/lithops.log.
EOF
)
ONE_SERVICE_RECONFIGURABLE=true

### Contextualization defaults #######################################
ONEAPP_AMQP_USER="${ONEAPP_AMQP_USER:-}"
ONEAPP_AMQP_PASS="${ONEAPP_AMQP_PASS:-}"
ONEAPP_AMQP_HOST="${ONEAPP_AMQP_HOST:-127.0.0.1}"
ONEAPP_AMQP_PORT="${ONEAPP_AMQP_PORT:-5672}"

### Globals ##########################################################

LITHOPS_REPO="https://github.com/OpenNebula/lithops.git"
LITHOPS_BRANCH="f-569"

###############################################################################
###############################################################################
###############################################################################

#
# service implementation
#

service_cleanup()
{
    :
}

service_install()
{

    install_system_dependencies
    clone_lithops_repository
    create_virtualenv
    install_python_dependencies

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    setup_service
    mount_onegate
    return 0
}

service_bootstrap()
{
    return 0
}

###############################################################################
###############################################################################
###############################################################################

#
# functions
#

install_system_dependencies() {
    echo "=== Updating apt repositories and installing system dependencies ==="
    apt-get update && apt-get install -y \
        build-essential \
        python3-dev \
        python3-pip \
        python3-venv \
        git \
        zip && \
    rm -rf /var/lib/apt/lists/*
}

mount_onegate() {
    mkdir /mnt/context
    mount /dev/cdrom /mnt/context
}

clone_lithops_repository() {
    echo "=== Cloning the Lithops repository into /lithops ==="
    git clone --single-branch --branch ${LITHOPS_BRANCH} ${LITHOPS_REPO} /lithops
}

create_virtualenv() {
    echo "=== Creating a Python virtual environment in /lithops-venv ==="
    python3 -m venv /lithops-venv
}

install_python_dependencies() {
    echo "=== Upgrading pip, setuptools, and six; Installing Python dependencies ==="
    source /lithops-venv/bin/activate
    pip install --upgrade setuptools six pip
    pip install --no-cache-dir \
        boto3 \
        pika \
        flask \
        gevent \
        redis \
        requests \
        PyYAML \
        numpy \
        cloudpickle \
        ps-mem \
        tblib \
        psutil
}

setup_service() {
    echo "=== Copying entry_point.py to / ==="
    cp /lithops/lithops/serverless/backends/one/entry_point.py /entry_point.py

    if [[ -n "$ONEAPP_AMQP_USER" && -n "$ONEAPP_AMQP_PASS" ]]; then
        ONEAPP_AMQP_URL="amqp://${ONEAPP_AMQP_USER}:${ONEAPP_AMQP_PASS}@${ONEAPP_AMQP_HOST}:${ONEAPP_AMQP_PORT}/"
    else
        ONEAPP_AMQP_URL="amqp://${ONEAPP_AMQP_HOST}:${ONEAPP_AMQP_PORT}/"
    fi

    echo "=== Creating systemd service file ==="
    cat <<EOF > /etc/systemd/system/lithops.service
[Unit]
Description=Lithops Entry Point
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/
ExecStart=/lithops-venv/bin/python /entry_point.py ${ONEAPP_AMQP_URL}
Restart=always
RestartSec=5
StandardOutput=append:/var/log/lithops.log
StandardError=append:/var/log/lithops.log

[Install]
WantedBy=multi-user.target
EOF

    echo "=== Reloading systemd, enabling, and starting the service ==="
    systemctl daemon-reload
    systemctl enable lithops
    systemctl start lithops
}