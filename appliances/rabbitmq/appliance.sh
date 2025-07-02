#!/usr/bin/env bash

# This script contains an example implementation logic for your appliances.
# For this example the goal will be to have a "database as a service" appliance

### RabbitMQ ##########################################################

# For organization purposes is good to define here variables that will be used by your bash logic
RABBITMQ_CONFIG_DIR=/etc/rabbitmq/
RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq.conf
RABBITMQ_ADVANCED_CONFIG_FILE=/etc/rabbitmq/advanced.config
PASSWORD_LENGTH=16
ONE_SERVICE_SETUP_DIR="/opt/one-appliance" ### Install location. Required by bash helpers

### CONTEXT SECTION ##########################################################

# List of contextualization parameters
# This is how you interact with the appliance using OpenNebula.
# These variables are defined in the CONTEXT section of the VM Template as custom variables
# https://docs.opennebula.io/6.8/management_and_operations/references/template.html#context-section
ONE_SERVICE_PARAMS=(
    'ONEAPP_RABBITMQ_PORT'             'configure' 'Port on which RabbitMQ listens for connections'             'O|text'
    'ONEAPP_RABBITMQ_LOOPBACK_USER'    'configure' 'Allow user to connect remotely'                             'O|boolean'
    'ONEAPP_RABBITMQ_USER'             'configure' 'User for RabbitMQ service'                                  'O|text'
    'ONEAPP_RABBITMQ_PASS'             'configure' 'Password for RabbitMQ service'                              'O|password'
    'ONEAPP_RABBITMQ_LOG_LEVEL'        'configure' 'Controls the granularity of logging'                        'O|text'
    'ONEAPP_RABBITMQ_TLS_ENABLED'      'configure' 'Enable TLS configuration'                                   'O|boolean'
    'ONEAPP_RABBITMQ_PORT_TLS'         'configure' 'Port on which RabbitMQ listens for SSL connections.'        'O|text'
    'ONEAPP_RABBITMQ_TLS_CERT'         'configure' 'Server certificate (.pem)'                                  'O|text64'
    'ONEAPP_RABBITMQ_TLS_KEY'          'configure' 'Server certficate key (.key)'                               'O|text64'
    'ONEAPP_RABBITMQ_TLS_PASS'         'configure' 'Server certificate password'                                'O|passsword'
    'ONEAPP_RABBITMQ_TLS_CA'           'configure' 'CA certificate chain'                                       'O|text64'
)
# Default values for when the variable doesn't exist on the VM Template
ONEAPP_RABBITMQ_PORT="${ONEAPP_RABBITMQ_PORT:-5672}"
ONEAPP_RABBITMQ_LOOPBACK_USER="${ONEAPP_RABBITMQ_LOOPBACK_USER:-NO}"
ONEAPP_RABBITMQ_USER="${ONEAPP_RABBITMQ_USER:-rabbitadmin}"
ONEAPP_RABBITMQ_PASS="${ONEAPP_RABBITMQ_PASS:-$(gen_password ${PASSWORD_LENGTH})}"
ONEAPP_RABBITMQ_LOG_LEVEL="${ONEAPP_RABBITMQ_LOG_LEVEL:-info}"
ONEAPP_RABBITMQ_TLS_ENABLED="${ONEAPP_RABBITMQ_TLS_ENABLED:-NO}"
ONEAPP_RABBITMQ_PORT_TLS="${ONEAPP_RABBITMQ_PORT_TLS:-5671}"

### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Service RabbitMQ - KVM'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with preinstalled RabbitMQ for KVM hosts'
ONE_SERVICE_RECONFIGURABLE=true


# You can make this parameters a required step of the VM instantiation wizard by using the USER_INPUTS feature
# https://docs.opennebula.io/6.8/management_and_operations/vm_management/vm_templates.html?#user-inputs

###############################################################################
###############################################################################
###############################################################################

# The following functions will be called by the appliance service manager at
# the  different stages of the appliance life cycles. They must exist
# https://github.com/OpenNebula/one-apps/wiki/apps_intro#appliance-life-cycle

#
# Mandatory Functions
#

service_install()
{

    echo "Updating package list"
    sudo apt-get update -y || { echo "Failed to update package list"; exit 1; }

    echo "Installing dependencies"
    sudo apt-get install -y curl gnupg apt-transport-https || { echo "Failed to install dependencies"; exit 1; }

    echo "Adding RabbitMQ and Erlang signing keys"
    curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null
    curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key | sudo gpg --dearmor | sudo tee /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg > /dev/null
    curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key | sudo gpg --dearmor | sudo tee /usr/share/keyrings/rabbitmq.9F4587F226208342.gpg > /dev/null

    echo "Adding RabbitMQ and Erlang repositories"
    sudo tee /etc/apt/sources.list.d/rabbitmq.list <<EOF
## Provides modern Erlang/OTP releases
##
deb [arch=amd64 signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main

# another mirror for redundancy
deb [arch=amd64 signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main

## Provides RabbitMQ
##
deb [arch=amd64 signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main

# another mirror for redundancy
deb [arch=amd64 signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main
EOF

    echo "Updating package list again"
    sudo apt-get update -y || { echo "Failed to update package list after adding repositories"; exit 1; }


    echo "Installing Erlang packages"
    sudo apt-get install -y erlang-base \
                        erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
                        erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
                        erlang-runtime-tools erlang-snmp erlang-ssl \
                        erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

    echo "Installing RabbitMQ server"
    sudo apt-get install rabbitmq-server -y --fix-missing || { echo "Failed to install RabbitMQ server"; exit 1; }

    # cleanup
    postinstall_cleanup

    echo "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    msg info "Stopping services"
    systemctl stop rabbitmq-server

    setup_rabbitmq_basic
    setup_rabbitmq_certs

    msg info "Credentials and config values are saved in: ${ONE_SERVICE_REPORT}"

    cat > "$ONE_SERVICE_REPORT" <<EOF
[RabbitMQ user credentials]
username = ${ONEAPP_RABBITMQ_USER}
password = ${ONEAPP_RABBITMQ_PASS}
EOF

    chmod 600 "$ONE_SERVICE_REPORT"

    msg info "Starting services"
    systemctl enable rabbitmq-server
    systemctl start rabbitmq-server
    if ! rabbitmqctl list_users | awk '{print $1}' | grep -q "^${ONEAPP_RABBITMQ_USER}$"; then
        rabbitmqctl add_user "${ONEAPP_RABBITMQ_USER}" "${ONEAPP_RABBITMQ_PASS}"
    else
        echo "User ${ONEAPP_RABBITMQ_USER} already exists, skipping creation."
    fi    
    rabbitmqctl set_permissions -p / ${ONEAPP_RABBITMQ_USER} ".*" ".*" ".*"
    rabbitmqctl change_password ${ONEAPP_RABBITMQ_USER} ${ONEAPP_RABBITMQ_PASS}
    rabbitmqctl set_user_tags ${ONEAPP_RABBITMQ_USER} administrator
    rabbitmqctl delete_user guest

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "BOOTSTRAP FINISHED"

    return 0
}


# This one is not really mandatory, however it is a handled function
service_cleanup()
{
    :
}


###############################################################################
###############################################################################
###############################################################################

# Then for modularity purposes you can define your own functions as long as their name
# doesn't clash with the previous functions

#
# functions
#

setup_rabbitmq_basic()
{

sudo tee /etc/rabbitmq/rabbitmq-env.conf > /dev/null <<EOL

## Set log file locations
RABBITMQ_CONFIG_FILE="$RABBITMQ_CONFIG_FILE"
RABBITMQ_ADVANCED_CONFIG_FILE="$RABBITMQ_ADVANCED_CONFIG_FILE"
RABBITMQ_LOGS=/var/log/rabbitmq/rabbitmq.log
RABBITMQ_SASL_LOGS=/var/log/rabbitmq/rabbitmq-sasl.log

EOL

sudo tee "$RABBITMQ_CONFIG_FILE" > /dev/null <<EOL

## Networking
listeners.tcp.default = $ONEAPP_RABBITMQ_PORT

## Users & Security
default_user = $ONEAPP_RABBITMQ_USER
default_pass = $ONEAPP_RABBITMQ_PASS
loopback_users.$ONEAPP_RABBITMQ_USER = $( [[ "${ONEAPP_RABBITMQ_LOOPBACK_USER,,}" == "yes" ]] && echo "true" || echo "false" )

## Log level for file logging
log.file.level = $ONEAPP_RABBITMQ_LOG_LEVEL

EOL


}


setup_rabbitmq_certs()
{

    ## TLS Certificates
    #  If TLS certificate and key are provided from contextualization.
    #  Based on https://www.rabbitmq.com/docs/ssl#enabling-tls
    local_rabbitmq_certs_path="/opt/rabbitmq/certs"

    if [[ ${ONEAPP_RABBITMQ_TLS_ENABLED} =~ ^(yes|YES)$ ]]; then
        msg info "Configuring TLS Certificates..."
        if [[ -f "${local_rabbitmq_certs_path}/server.pem" ]] || [[ -f "${local_rabbitmq_certs_path}/server.key" ]]; then
            msg info "Certificates already exist. Skipping."
        else
            msg info "Create folder for TLS certificates: ${local_rabbitmq_certs_path}"
            mkdir -p ${local_rabbitmq_certs_path}

            if [[ -z "${ONEAPP_RABBITMQ_TLS_CERT}" ]] || [[ -z "${ONEAPP_RABBITMQ_TLS_KEY}" ]]; then
                msg info "No Certs provided, autogenerating TLS certificates..."
                generate_tls_certs
            else
                msg info "Configuring provided TLS certificates..."
                echo ${ONEAPP_RABBITMQ_TLS_CA} | base64 --decode >> /opt/rabbitmq/certs/ca.pem
                echo ${ONEAPP_RABBITMQ_TLS_CERT} | base64 --decode >> /opt/rabbitmq/certs/server.pem
                echo ${ONEAPP_RABBITMQ_TLS_KEY} | base64 --decode >> /opt/rabbitmq/certs/server.key
            fi

            sudo tee -a "$RABBITMQ_CONFIG_FILE" > /dev/null <<EOL

## TLS Configuration
listeners.ssl.default = $ONEAPP_RABBITMQ_PORT_TLS
ssl_options.cacertfile = /opt/rabbitmq/certs/ca.pem
ssl_options.certfile   = /opt/rabbitmq/certs/server.pem
ssl_options.keyfile    = /opt/rabbitmq/certs/server.key
ssl_options.verify     = verify_peer
ssl_options.fail_if_no_peer_cert = false
EOL

            # Append ssl_options.password only if ONEAPP_RABBITMQ_TLS_PASS and ONEAPP_RABBITMQ_TLS_KEY are set
            if [[ -n "$ONEAPP_RABBITMQ_TLS_PASS" && -n "$ONEAPP_RABBITMQ_TLS_KEY" ]]; then
                echo "ssl_options.password = $ONEAPP_RABBITMQ_TLS_PASS" | sudo tee -a "$RABBITMQ_CONFIG_FILE" > /dev/null
            fi
            msg info "Give ownership of /opt/rabbitmq to rabbitmq user"
            chown -R rabbitmq:rabbitmq /opt/rabbitmq
        fi
    fi



}


generate_tls_certs()
{
    local_rabbitmq_certs_path="/opt/rabbitmq/certs"

    # Generate a CA certificate first
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout ${local_rabbitmq_certs_path}/ca.key \
        -out ${local_rabbitmq_certs_path}/ca.pem \
        -subj "/C=US/ST=California/L=San Francisco/O=Example Company/CN=$(hostname -f)" > /dev/null 2>&1

    # Generate a server private key
    openssl genpkey -algorithm RSA -out ${local_rabbitmq_certs_path}/server.key > /dev/null 2>&1

    # Generate the server CSR
    openssl req -new -key ${local_rabbitmq_certs_path}/server.key -out ${local_rabbitmq_certs_path}/server.csr \
        -subj "/C=US/ST=California/L=San Francisco/O=Example Company/CN=$(hostname -f)" > /dev/null 2>&1

    # Sign the server CSR with the CA certificate and key
    openssl x509 -req -in ${local_rabbitmq_certs_path}/server.csr -CA ${local_rabbitmq_certs_path}/ca.pem \
        -CAkey ${local_rabbitmq_certs_path}/ca.key -CAcreateserial -out ${local_rabbitmq_certs_path}/server.pem -days 365 > /dev/null 2>&1

    # Clean up the CSR (optional)
    rm ${local_rabbitmq_certs_path}/server.csr

}

is_rabbitmq_up()
{
    if systemctl is-active --quiet rabbitmq-server; then
        return 0
    else
        return 1
    fi
}



postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
