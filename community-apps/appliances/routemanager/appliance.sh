#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox route-manager-api'
ONE_SERVICE_VERSION='v0.1.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='6G-Sandbox route-manager-api appliance for KVM'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of [route-manager-api](https://github.com/6G-SANDBOX/route-manager-api), a REST API in port 8172/tcp developed with FastAPI for managing network routes on a Linux machine using the ip command.

The image is based on Debian 18 with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.
EOF
)

ONE_SERVICE_RECONFIGURABLE=true


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_ROUTEMANAGER_APITOKEN'       'configure'  'Bearer token to authenticate to the API. If not provided, a new one will be generated at instanciate time with `openssl rand -base64 32`' 'O|password'
)


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="git"


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Mandatory Functions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    # packages
    install_pkg_deps

    # clone
    clone_repo

    # venv
    create_venv

    # service
    routemanager_service

    # enable routing
    msg info "Enable ipv4 forwarding"
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipv4-ip_forward.conf

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

# Runs when VM is first started, and every time 
service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # config
    configure_token

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    export DEBIAN_FRONTEND=noninteractive
    msg info "BOOTSTRAP FINISHED"
    return 0
}

# This one is not really mandatory, however it is a handled function
service_help()
{
    msg info "Example appliance how to use message. If missing it will default to the generic help"

    return 0
}

# This one is not really mandatory, however it is a handled function
service_cleanup()
{
    msg info "CLEANUP logic goes here in case of install failure"
    :
}


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

install_pkg_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required packages for route-manager-api"
    if ! apt-get install -y "${DEP_PKGS}" ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

clone_repo()
{
    msg info "git clone route-manager-api repository"
    if ! git clone https://github.com/6G-SANDBOX/route-manager-api -b develop /opt/route-manager-api ; then
    # if ! git clone https://github.com/6G-SANDBOX/route-manager-api /opt/route-manager-api ; then    TODO: Remember reverting thic change
        msg error "Error cloning route-manager-api repository"
        exit 1
    fi
}

create_venv()
{
    msg info "Install uv"
    if ! (curl -LsSf https://astral.sh/uv/install.sh | sh); then
        msg error "Error installing uv"
        exit 1
    fi

    msg info "Create virtual environment"
    if ! (/root/.local/bin/uv sync --project /opt/route-manager-api/); then
        msg error "Error creating .venv"
        exit 1
    fi
}

routemanager_service()
{
    msg info "Defining route-manager-api systemd service"
    cat > /etc/systemd/system/route-manager-api.service << 'EOF'
[Unit]
Description=A REST API developed with FastAPI for managing network routes on a Linux machine using the ip command. It allows you to query active routes, create new routes, and delete existing routes, with token-based authentication and persistence of scheduled routes to ensure their availability even after service restarts.
After=network.target

[Service]
Type=simple
ExecStart=/root/.local/bin/uv --directory /opt/route-manager-api/ run fastapi run --port 8172
StandardOutput=append:/var/log/route_manager.log
StandardError=append:/var/log/route_manager.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod +x /etc/systemd/system/route-manager-api.service
    
    msg info "Enable route-manager-api systemd service"
    if ! systemctl enable route-manager-api.service ; then
        msg error "Service route-manager-api could not be enabled succesfully"
        exit 1
    fi
}

configure_token()
{
    TEMP="$(onegate vm show --json |jq -r .VM.USER_TEMPLATE.ONEAPP_ROUTEMANAGER_APITOKEN)"

    if [[ -z "${ONEAPP_ROUTEMANAGER_APITOKEN}" && "${TEMP}" == null ]] ; then
        msg info "APITOKEN for route-manager-api not provided. Generating one"
        ONEAPP_ROUTEMANAGER_APITOKEN=$(openssl rand -base64 32)
        onegate vm update --data ONEAPP_ROUTEMANAGER_APITOKEN="${ONEAPP_ROUTEMANAGER_APITOKEN}"

    elif [[ "${TEMP}" != null ]] ; then
        msg info "Using provided or previously generated APITOKEN"
        ONEAPP_ROUTEMANAGER_APITOKEN="${TEMP}"
    fi

    msg info "Update APITOKEN for route-manager-api config file"
    sed -i "s%^APITOKEN = .*%APITOKEN = ${ONEAPP_ROUTEMANAGER_APITOKEN}%" /opt/route-manager-api/.env

    msg info "Restart service route-manager-api"
    if ! systemctl restart route-manager-api.service ; then
        msg error "Error restarting service route-manager-api"
        exit 1
    fi
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
