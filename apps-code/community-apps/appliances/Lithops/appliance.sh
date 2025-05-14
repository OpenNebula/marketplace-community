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
    'ONEAPP_LITHOPS_BACKEND'            'configure'  'Lithops compute backend'                                          'O|text'
    'ONEAPP_LITHOPS_STORAGE'            'configure'  'Lithops storage backend'                                          'O|text'
    'ONEAPP_LITHOPS_STANDALONE'         'configure'  'Wether the appliance runs as standalone or as a service'          'O|boolean'
    'ONEAPP_MINIO_ENDPOINT'             'configure'  'Lithops storage backend MinIO endpoint URL'                       'O|text'
    'ONEAPP_MINIO_ACCESS_KEY_ID'        'configure'  'Lithops storage backend MinIO account user access key'            'O|text'
    'ONEAPP_MINIO_SECRET_ACCESS_KEY'    'configure'  'Lithops storage backend MinIO account user secret access key'     'O|text'
    'ONEAPP_MINIO_BUCKET'               'configure'  'Lithops storage backend MinIO existing bucket'                    'O|text'
    'ONEAPP_MINIO_ENDPOINT_CERT'        'configure'  'Lithops storage backend MinIO endpoint certificate'               'O|text64'
    'ONEAPP_ONEBE_DOCKER_USER'          'configure'  'Username from dockerhub'                                          'O|text'
    'ONEAPP_ONEBE_DOCKER_PASSWORD'      'configure'  'Password for dockerhub'                                           'O|password'
    'ONEAPP_ONEBE_RUNTIME_CPU'          'configure'  'Number of vCPU per ONEBE'                                         'O|text'
    'ONEAPP_ONEBE_RUNTIME_MEMORY'       'configure'  'Amount of memory per ONEBE'                                       'O|text'
    'ONEAPP_ONEBE_KUBECFG_PATH'         'configure'  'Path where kubeconfig file will be stored'                        'O|text'
    'ONEAPP_ONEBE_AUTOSCALE'            'configure'  'k8s backend autoscale option'                                     'O|text'
    'FALLBACK_GW'                       'configure'  'Appliance GW for Service mode'                                    'O|text'
    'FALLBACK_DNS'                      'configure'  'Appliance DNS for Service mode'                                   'O|text'
    'ONEAPP_AMQP_USER'                  'configure'  'AMQP broker username'                                             'O|text'
    'ONEAPP_AMQP_PASS'                  'configure'  'AMQP broker password'                                             'O|password'
    'ONEAPP_AMQP_HOST'                  'configure'  'AMQP broker host'                                                 'O|text'
    'ONEAPP_AMQP_PORT'                  'configure'  'AMQP broker port'                                                 'O|text'
    'ONEAPP_ONEBE_WORKER_PROCESSES'     'configure'  'Number of worker processes for ONEBE'                             'O|text'
    'ONEAPP_ONEBE_RUNTIME_TIMEOUT'      'configure'  'Runtime timeout in seconds'                                       'O|text'
    'ONEAPP_ONEBE_MAX_WORKERS'          'configure'  'Maximum number of ONEBE workers'                                  'O|text'
    'ONEAPP_ONEBE_MIN_WORKERS'          'configure'  'Minimum number of ONEBE workers'                                  'O|text'
)



### Appliance metadata ###############################################

# Appliance metadata
ONE_SERVICE_NAME='Lithops'
ONE_SERVICE_VERSION='3.4.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with preinstalled Lithops for KVM hosts'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled Lithops v3.4.0.

By default, it uses localhost both for Compute and Storage Backend.

- Compute options: localhost, one, amqp
- Storage options: localhost, minio

To configure MinIO as Storage Backend use the parameter ONEAPP_LITHOPS_STORAGE=minio
with ONEAPP_MINIO_ENDPOINT, ONEAPP_MINIO_ACCESS_KEY_ID and ONEAPP_MINIO_SECRET_ACCESS_KEY.
These parameters values have to point to a valid and reachable MinIO server endpoint.

The parameter ONEAPP_MINIO_BUCKET and ONEAPP_MINIO_ENDPOINT_CERT are optional.
- ONEAPP_MINIO_BUCKET points to an existing bucket in the MinIO server. If the bucket does not exist or if the
parameter is empty, the MinIO server will generate a bucket automatically.
- ONEAPP_MINIO_ENDPOINT_CERT is necessary when using self-signed certificates on the MinIO server. This is the
certificate for the CA on the MinIO server. If the CA certificate exists, script will skip it,
if one would want to update the CA certificate from context, first delete previous ca.crt file.
EOF
)
ONE_SERVICE_RECONFIGURABLE=true

### Contextualization defaults #######################################

ONEAPP_LITHOPS_BACKEND="${ONEAPP_LITHOPS_BACKEND:-localhost}"
ONEAPP_LITHOPS_STORAGE="${ONEAPP_LITHOPS_STORAGE:-localhost}"
ONEAPP_LITHOPS_STANDALONE="${ONEAPP_LITHOPS_STANDALONE:-YES}"
ONEAPP_ONEBE_RUNTIME_CPU="${ONEAPP_ONEBE_RUNTIME_CPU:-1}"
ONEAPP_ONEBE_RUNTIME_MEMORY="${ONEAPP_ONEBE_RUNTIME_MEMORY:-512}"
ONEAPP_ONEBE_KUBECFG_PATH="${ONEAPP_ONEBE_KUBECFG_PATH:-\/tmp\/kubeconfig}"
ONEAPP_ONEBE_AUTOSCALE="${ONEAPP_ONEBE_AUTOSCALE:-all}"
ONEAPP_AMQP_USER="${ONEAPP_AMQP_USER:-}"
ONEAPP_AMQP_PASS="${ONEAPP_AMQP_PASS:-}"
ONEAPP_AMQP_HOST="${ONEAPP_AMQP_HOST:-127.0.0.1}"
ONEAPP_AMQP_PORT="${ONEAPP_AMQP_PORT:-5672}"
ONEAPP_ONEBE_WORKER_PROCESSES="${ONEAPP_ONEBE_WORKER_PROCESSES:-2}"
ONEAPP_ONEBE_RUNTIME_TIMEOUT="${ONEAPP_ONEBE_RUNTIME_TIMEOUT:-600}"
ONEAPP_ONEBE_MAX_WORKERS="${ONEAPP_ONEBE_MAX_WORKERS:-3}"
ONEAPP_ONEBE_MIN_WORKERS="${ONEAPP_ONEBE_MIN_WORKERS:-1}"

### Globals ##########################################################

DEP_PKGS="python3-pip"
DEP_PIP="boto3 requests"
LITHOPS_VERSION="3.4.0"
LITHOPS_REPO="https://github.com/OpenNebula/lithops.git"
LITHOPS_BRANCH="f-569"
DOCKER_VERSION="5:26.1.3-1~ubuntu.22.04~jammy"

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
    # ensuring that the setup directory exists
    #TODO: move to service
    mkdir -p "$ONE_SERVICE_SETUP_DIR"
    export DEBIAN_FRONTEND=noninteractive

    # packages
    install_deps ${DEP_PKGS} ${DEP_PIP}

    # docker
    install_docker

    # Lithops
    install_lithops_git

    # create Lithops config file in /etc/lithops
    create_lithops_config

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    # If the appliance is configured to deploy in a service, configure networking
    if [[ ${ONEAPP_LITHOPS_STANDALONE} =~ ^(no|NO)$ ]]; then
        msg info "Configure appliance as part of a service"
        # Configure GW & DNS
        if [[ ! -z ${FALLBACK_GW} ]] && [[ ! -z ${FALLBACK_DNS} ]]; then
            msg info "Change default route to VNF IP"
            ip route replace default via ${FALLBACK_GW} dev eth0
            msg info "Change DNS server to VNF IP"
            cat > /etc/resolv.conf <<EOF
nameserver ${FALLBACK_DNS}
EOF
        else
            msg error "No fallback GW or DNS defined, error configuring appliance"
            exit 1
        fi
        # Get k8s worker CPU & memory
        msg info "Get k8s worker CPU & memory"
        ONEAPP_ONEBE_RUNTIME_CPU=($(onegate service show -j --extended | jq -r '.SERVICE.roles[] | select(.name=="worker").nodes[0].vm_info.VM.TEMPLATE.CPU'))
        ONEAPP_ONEBE_RUNTIME_MEMORY=($(onegate service show -j --extended | jq -r '.SERVICE.roles[] | select(.name=="worker").nodes[0].vm_info.VM.TEMPLATE.MEMORY'))
        msg info "runtime_memory: ${ONEAPP_ONEBE_RUNTIME_MEMORY}; runtime_cpu: ${ONEAPP_ONEBE_RUNTIME_CPU}"
    fi
    # update Lithops config file if non-default options are set
    update_lithops_config

    local_ca_folder="/usr/local/share/ca-certificates/minio"
    if [[ ! -z "${ONEAPP_MINIO_ENDPOINT_CERT}" ]] && [[ ! -f "${local_ca_folder}/ca.crt" ]]; then
        msg info "Adding trust CA for MinIO endpoint"

        if [[ ! -d "${local_ca_folder}" ]]; then
            msg info "Create folder ${local_ca_folder}"
            mkdir "${local_ca_folder}"
        fi

        msg info "Create CA file and update certificates"
        echo ${ONEAPP_MINIO_ENDPOINT_CERT} | base64 --decode >> ${local_ca_folder}/ca.crt
        update-ca-certificates
    fi

    return 0
}

service_bootstrap()
{
    update_lithops_config
    return 0
}

###############################################################################
###############################################################################
###############################################################################

#
# functions
#

install_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required packages for Lithops"
    if ! apt-get install -y "${1}" ; then
        msg error "Package(s) installation failed: ${1}"
        exit 1
    fi

    msg info "Install pip dependencies"
    if ! pip install "${2}" ; then
        msg error "Python pip dependencies installation failed"
        exit 1
    fi
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

install_lithops()
{
    msg info "Install Lithops from pip"
    if ! pip install lithops==${LITHOPS_VERSION} ; then
        msg error "Error installing Lithops"
        exit 1
    fi

    msg info "Create /etc/lithops folder"
    mkdir /etc/lithops
}

install_lithops_git()
{
    if ! apt-get -y remove python3-requests python3-urllib3 ; then
        msg error "Error uninstalling pip deps"
        exit 1
    fi

    msg info "Cloning Lithops git repository"
    git clone --single-branch --branch ${LITHOPS_BRANCH} ${LITHOPS_REPO}

    cd lithops
    msg info "Install Lithops from git"
    if ! pip install . ; then
        msg error "Error installing Lithops"
        exit 1
    fi

    cd
    msg info "Create /etc/lithops folder"
    mkdir /etc/lithops
}

create_lithops_config()
{
    msg info "Create default config file"
    cat > /etc/lithops/config <<EOF
lithops:
  backend: localhost
  storage: localhost

# Start Compute Backend configuration
# End Compute Backend configuration

# Start Storage Backend configuration
# End Storage Backend configuration

# Start Monitoring configuration
# End Monitoring configuration
EOF
}

update_lithops_config(){
    msg info "Update compute and storage backend modes"
    sed -i "s/backend: .*/backend: ${ONEAPP_LITHOPS_BACKEND}/g" /etc/lithops/config
    sed -i "s/storage: .*/storage: ${ONEAPP_LITHOPS_STORAGE}/g" /etc/lithops/config

    if [[ ${ONEAPP_LITHOPS_BACKEND} = "localhost" ]]; then
        msg info "Edit config file for localhost Compute Backend"
        sed -i -ne "/# Start Compute/ {p;" -e ":a; n; /# End Compute/ {p; b}; ba}; p" /etc/lithops/config
    elif [[ ${ONEAPP_LITHOPS_BACKEND} = "one" ]]; then
        msg info "Edit config file for ONE Compute Backend"

        if ! check_onebe_attrs; then
            msg info "Check ONE backed attributes"
            msg error "ONE backend configuration failed"
            exit 1
        else
            local_service_attr=""
            msg info "Adding ONE backend configuration to /etc/lithops/config"
                if [[ ! -z "$ONEAPP_ONEBE_SERVICE_ID" ]]; then
                local_service_attr="service_id: ${ONEAPP_ONEBE_SERVICE_ID}"
                elif [[ ! -z "$ONEAPP_ONEBE_SERVICE_TMPL_ID" ]]; then
                local_service_attr="service_template_id: $ONEAPP_ONEBE_SERVICE_TMPL_ID"
                fi
            msg info "runtime_memory: ${ONEAPP_ONEBE_RUNTIME_MEMORY}; runtime_cpu: ${ONEAPP_ONEBE_RUNTIME_CPU}"
            sed -i -ne "/# Start Compute/ {p; ione:\n  docker_user: ${ONEAPP_ONEBE_DOCKER_USER}\n  docker_password: ${ONEAPP_ONEBE_DOCKER_PASSWORD}\n  runtime_cpu: ${ONEAPP_ONEBE_RUNTIME_CPU}\n  runtime_memory: ${ONEAPP_ONEBE_RUNTIME_MEMORY}\n  kubecfg_path: ${ONEAPP_ONEBE_KUBECFG_PATH}\n  auto_scale: ${ONEAPP_ONEBE_AUTOSCALE}" -e ":a; n; /# End Compute/ {p; b}; ba}; p" /etc/lithops/config
        fi
    elif [[ ${ONEAPP_LITHOPS_BACKEND} = "amqp" ]]; then
        msg info "Edit config file for AMQP Compute Backend"
        if ! check_amqpbe_attrs; then
            msg info "Check AMQP backend attributes"
            msg error "AMQP backend configuration failed"
            exit 1
        else
            
            if [[ -n "$ONEAPP_AMQP_USER" && -n "$ONEAPP_AMQP_PASS" ]]; then
                ONEAPP_AMQP_URL="amqp://${ONEAPP_AMQP_USER}:${ONEAPP_AMQP_PASS}@${ONEAPP_AMQP_HOST}:${ONEAPP_AMQP_PORT}/"
            else
                ONEAPP_AMQP_URL="amqp://${ONEAPP_AMQP_HOST}:${ONEAPP_AMQP_PORT}/"
            fi

            msg info "Adding AMQP backend configuration to /etc/lithops/config"
            sed -i '/^lithops:/a\  monitoring: rabbitmq' /etc/lithops/config

            sed -i -ne "/# Start Compute/ {
            p;
            ione:\n  worker_processes: ${ONEAPP_ONEBE_WORKER_PROCESSES}\n  runtime_memory: ${ONEAPP_ONEBE_RUNTIME_MEMORY}\n  runtime_timeout: ${ONEAPP_ONEBE_RUNTIME_TIMEOUT}\n  runtime_cpu: ${ONEAPP_ONEBE_RUNTIME_CPU}\n  amqp_url: ${ONEAPP_AMQP_URL}\n  max_workers: ${ONEAPP_ONEBE_MAX_WORKERS}\n  min_workers: ${ONEAPP_ONEBE_MIN_WORKERS}\n  autoscale: ${ONEAPP_ONEBE_AUTOSCALE}
            }" -e ":a; n; /# End Compute/ {p; b}; ba; p" /etc/lithops/config

            sed -i -ne "/# Start Monitoring/ {
            p;
            irabbitmq:\n  amqp_url: ${ONEAPP_AMQP_URL}
            }" -e ":a; n; /# End Monitoring/ {p; b}; ba; p" /etc/lithops/config
        fi 
    fi

    if [[ ${ONEAPP_LITHOPS_STORAGE} = "localhost" ]]; then
        msg info "Edit config file for localhost Storage Backend"
        sed -i -ne "/# Start Storage/ {p;" -e ":a; n; /# End Storage/ {p; b}; ba}; p" /etc/lithops/config
    elif [[ ${ONEAPP_LITHOPS_STORAGE} = "minio" ]]; then
        msg info "Edit config file for MinIO Storage Backend"
        if ! check_minio_attrs; then
            echo
            msg error "MinIO configuration failed"
            msg info "You have to provide endpoint, access key id and secrec access key to configure MinIO storage backend"
            exit 1
        else
            msg info "Adding MinIO configuration to /etc/lithops/config"
            sed -i -ne "/# Start Storage/ {p; iminio:\n  endpoint: ${ONEAPP_MINIO_ENDPOINT}\n  access_key_id: ${ONEAPP_MINIO_ACCESS_KEY_ID}\n  secret_access_key: ${ONEAPP_MINIO_SECRET_ACCESS_KEY}\n  storage_bucket: ${ONEAPP_MINIO_BUCKET}" -e ":a; n; /# End Storage/ {p; b}; ba}; p" /etc/lithops/config
        fi
    fi
}

check_minio_attrs()
{
    [[ -z "$ONEAPP_MINIO_ENDPOINT" ]] && return 1
    [[ -z "$ONEAPP_MINIO_ACCESS_KEY_ID" ]] && return 1
    [[ -z "$ONEAPP_MINIO_SECRET_ACCESS_KEY" ]] && return 1

    return 0
}

check_onebe_attrs()
{
    [[ -z "$ONEAPP_ONEBE_DOCKER_USER" ]] && return 1
    [[ -z "$ONEAPP_ONEBE_DOCKER_PASSWORD" ]] && return 1
    return 0
}

check_amqpbe_attrs()
{
    [[ -z "$ONEAPP_AMQP_HOST" ]] && return 1
    [[ -z "$ONEAPP_AMQP_PORT" ]] && return 1
    return 0
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}

