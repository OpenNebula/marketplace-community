#!/usr/bin/env bash
# --------------------------------------------------------------------------
# Mistral Copilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by llama-server (llama.cpp) + Mistral 7B Instruct,
# packaged as an OpenNebula marketplace appliance. CPU-only inference with
# native TLS, API key auth, and Prometheus metrics. No GPU required.
# --------------------------------------------------------------------------

# shellcheck disable=SC2034  # ONE_SERVICE_* vars used by one-apps framework

ONE_SERVICE_NAME='Service Mistral Copilot - Sovereign AI Coding Assistant'
ONE_SERVICE_VERSION='2.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='CPU-only AI coding copilot (Mistral 7B Instruct via llama.cpp)'
ONE_SERVICE_DESCRIPTION='Sovereign AI coding assistant serving Mistral 7B Instruct
via llama-server (llama.cpp). OpenAI-compatible API for aider and any OpenAI client.
Native TLS, API key auth, and Prometheus metrics. CPU-only inference, no GPU required.
Devstral Small 2 24B, Mistral Small 24B, and Mistral Nemo 12B are available as
opt-in alternatives that download on first boot when selected.'
ONE_SERVICE_RECONFIGURABLE=true

# --------------------------------------------------------------------------
# ONE_SERVICE_PARAMS -- flat array, 4-element stride:
#   'VARNAME' 'lifecycle_step' 'Description' 'default_value'
#
# All variables are bound to the 'configure' step so they are re-read on
# every VM boot / reconfigure cycle.
# --------------------------------------------------------------------------
ONE_SERVICE_PARAMS=(
    'ONEAPP_COPILOT_AI_MODEL'         'configure' 'AI model selection'                          'Mistral 7B Instruct (7B ~4GB built-in)'
    'ONEAPP_COPILOT_CONTEXT_SIZE'  'configure' 'Model context window in tokens'              '8192'
    'ONEAPP_COPILOT_API_PASSWORD'       'configure' 'API key / Bearer token (auto-generated if empty)' ''
    'ONEAPP_COPILOT_TLS_DOMAIN'        'configure' 'FQDN for Let'\''s Encrypt certificate'       ''
    'ONEAPP_COPILOT_CPU_THREADS'       'configure' 'CPU threads for inference (0=auto-detect)'   '0'
    'ONEAPP_COPILOT_LB_ENABLED'        'configure' 'Enable LiteLLM load balancer mode'                     'NO'
    'ONEAPP_COPILOT_LB_BACKENDS'       'configure' 'Remote backends for load balancing'                    ''
    'ONEAPP_COPILOT_REGISTER_URL'            'configure' 'Remote LB URL for auto-registration'                  ''
    'ONEAPP_COPILOT_REGISTER_KEY'     'configure' 'Remote LB master key for auto-registration'           ''
    'ONEAPP_COPILOT_REGISTER_MODEL_NAME' 'configure' 'Model name override for LB registration'           ''
    'ONEAPP_COPILOT_REGISTER_SITE_NAME'  'configure' 'Site name for LB backend ID (e.g. poland0)'        ''
    'ONEAPP_COPILOT_TLS_EMAIL'           'configure' 'Email for Let'\''s Encrypt registration (recommended)' ''
    'ONEAPP_COPILOT_TLS_CA'              'configure' 'Internal CA PEM to verify LB/backends (path or inline)' ''
    'ONEAPP_COPILOT_REGISTER_INSECURE'   'configure' 'Allow auto-registration to an unverified self-signed LB' 'NO'
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_AI_MODEL="${ONEAPP_COPILOT_AI_MODEL:-Mistral 7B Instruct (7B ~4GB built-in)}"
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-8192}"
ONEAPP_COPILOT_API_PASSWORD="${ONEAPP_COPILOT_API_PASSWORD:-}"
ONEAPP_COPILOT_TLS_DOMAIN="${ONEAPP_COPILOT_TLS_DOMAIN:-}"
ONEAPP_COPILOT_CPU_THREADS="${ONEAPP_COPILOT_CPU_THREADS:-0}"
ONEAPP_COPILOT_LB_ENABLED="${ONEAPP_COPILOT_LB_ENABLED:-NO}"
ONEAPP_COPILOT_LB_BACKENDS="${ONEAPP_COPILOT_LB_BACKENDS:-}"
ONEAPP_COPILOT_REGISTER_URL="${ONEAPP_COPILOT_REGISTER_URL:-}"
ONEAPP_COPILOT_REGISTER_KEY="${ONEAPP_COPILOT_REGISTER_KEY:-}"
ONEAPP_COPILOT_REGISTER_MODEL_NAME="${ONEAPP_COPILOT_REGISTER_MODEL_NAME:-}"
ONEAPP_COPILOT_REGISTER_SITE_NAME="${ONEAPP_COPILOT_REGISTER_SITE_NAME:-}"
ONEAPP_COPILOT_TLS_EMAIL="${ONEAPP_COPILOT_TLS_EMAIL:-}"
ONEAPP_COPILOT_TLS_CA="${ONEAPP_COPILOT_TLS_CA:-}"
ONEAPP_COPILOT_REGISTER_INSECURE="${ONEAPP_COPILOT_REGISTER_INSECURE:-NO}"

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
readonly LLAMA_SERVER_VERSION="b8133"
# Full commit the b8133 tag resolves to. Asserted after clone so a moved or
# re-pushed tag cannot silently swap the compiled sources (supply-chain pin).
readonly LLAMA_SERVER_COMMIT="2b6dfe824de8600c061ef91ce5cc5c307f97112c"
readonly LLAMA_PORT=8443
readonly LLAMA_CERT_DIR="/etc/ssl/mistral_copilot"
readonly LLAMA_DATA_DIR="/var/lib/mistral_copilot"
readonly LLAMA_MODEL_DIR="/opt/models"
readonly LLAMA_BIN="/usr/local/bin/llama-server"
readonly LLAMA_SYSTEMD_UNIT="/etc/systemd/system/mistral_copilot.service"
readonly LLAMA_ENV_FILE="/etc/mistral_copilot/env"
readonly COPILOT_LOG="/var/log/one-appliance/mistral_copilot.log"
readonly LITELLM_CONFIG="/etc/mistral_copilot/litellm-config.yaml"
readonly LITELLM_SYSTEMD_UNIT="/etc/systemd/system/mistral_copilot-proxy.service"
readonly LITELLM_PORT=8443
readonly LLAMA_PORT_LOCAL=8444
readonly LB_MODEL_ID_FILE="/etc/mistral_copilot/lb_model_id"
readonly LB_DEREGISTER_SCRIPT="/usr/local/bin/mistral_copilot-lb-deregister"
readonly LB_DEREGISTER_UNIT="/etc/systemd/system/mistral_copilot-lb-deregister.service"
readonly LB_HEALTHCHECK_SCRIPT="/usr/local/bin/mistral_copilot-lb-healthcheck"
readonly LB_HEALTHCHECK_UNIT="/etc/systemd/system/mistral_copilot-lb-healthcheck.service"
readonly LB_HEALTHCHECK_TIMER="/etc/systemd/system/mistral_copilot-lb-healthcheck.timer"

# Per-role secrets. Each role gets a distinct random secret so a leak of one
# (e.g. an inference key harvested off a backend) never yields the LB master
# key, the Web UI login, or the database password.
readonly LB_MASTER_KEY_FILE="${LLAMA_DATA_DIR}/lb_master_key"
readonly UI_PASSWORD_FILE="${LLAMA_DATA_DIR}/ui_password"
readonly DB_PASSWORD_FILE="${LLAMA_DATA_DIR}/db_password"
readonly LB_DEREGISTER_ENV="${LLAMA_DATA_DIR}/lb_deregister.env"
# Optional internal CA bundle for verifying self-signed LB/backend certs.
readonly BACKEND_CA_FILE="${LLAMA_CERT_DIR}/backend-ca.pem"

# Built-in model (baked into image at install time)
readonly BUILTIN_MODEL_GGUF="Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
readonly BUILTIN_MODEL_HF_REPO="bartowski/Mistral-7B-Instruct-v0.3-GGUF"
readonly BUILTIN_MODEL_SHA256="1270d22c0fbb3d092fb725d4d96c457b7b687a5f5a715abe1e818da303e562b6"

# ---------------------------------------------------------------------------
# Model catalog: name -> "model_id|gguf_filename|hf_url|sha256"
# The first entry (Mistral 7B Instruct) is baked into the image at build time
# so the marketplace qcow2 stays compact (~6 GiB) and clones quickly during
# OpenNebula instantiation. Other entries are downloaded on first boot when
# selected — trades a one-time download for a larger model.
# ---------------------------------------------------------------------------
declare -A MODEL_CATALOG=(
    ["Mistral 7B Instruct (7B ~4GB built-in)"]="mistral-7b|${BUILTIN_MODEL_GGUF}||${BUILTIN_MODEL_SHA256}"
    ["Devstral Small 2 (24B ~14GB)"]="devstral-small-2|Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf|https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf|d14ba9edee1bb4c4996a726deb81e49ae81800a3216f0774634238c380aee496"
    ["Mistral Small Instruct (24B ~14GB)"]="mistral-small-24b|Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-Small-24B-Instruct-2501-GGUF/resolve/main/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf|d1a6d049f09730c3f8ba26cf6b0b60c89790b5fdafa9a59c819acdfe93fffd1b"
    ["Mistral Nemo Instruct (12B ~7GB)"]="mistral-nemo-12b|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|7c1a10d202d8788dbe5628dc962254d10654c853cae6aaeca0618f05490d4a46"
)

# ==========================================================================
#  HELPER: verify_sha256  (fail-closed integrity check for downloaded files)
# ==========================================================================
# Returns 0 only if the file's SHA256 matches the expected hex digest. An
# empty expected digest is treated as a hard error (never silently skip).
verify_sha256() {
    local _file="$1" _expected="$2"
    if [ -z "${_expected}" ]; then
        log_copilot error "No expected SHA256 provided for ${_file} -- refusing to accept unverified file"
        return 1
    fi
    local _actual
    _actual=$(sha256sum "${_file}" 2>/dev/null | awk '{print $1}')
    if [ "${_actual}" != "${_expected}" ]; then
        log_copilot error "SHA256 mismatch for ${_file} (expected ${_expected}, got ${_actual:-none})"
        return 1
    fi
    return 0
}

# ==========================================================================
#  LOGGING: dedicated application log helpers
# ==========================================================================

# Ensure log directory and file exist with correct permissions
init_copilot_log() {
    mkdir -p /var/log/one-appliance
    touch "${COPILOT_LOG}"
    chmod 0640 "${COPILOT_LOG}"
}

# Log to both the one-apps framework (via msg) and the dedicated log file
log_copilot() {
    local _level="$1"
    shift
    local _message="$*"
    local _timestamp
    _timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${_timestamp} [${_level^^}] ${_message}" >> "${COPILOT_LOG}"
    msg "${_level}" "${_message}"
}

# ==========================================================================
#  HELPER: is_lb_mode  (true when LiteLLM load balancing is configured)
# ==========================================================================
is_lb_mode() {
    [[ "${ONEAPP_COPILOT_LB_ENABLED:-NO}" =~ ^(YES|yes|true|1)$ ]]
}

# ==========================================================================
#  HELPER: get_public_ip  (resolve internet-reachable IP for endpoint)
# ==========================================================================

# Returns the address remote users should connect to. Prefers OneGate (the
# OpenNebula metadata service, which knows the VM's externally-reachable NIC)
# and falls back to the first local IP. No third-party IP-echo services are
# contacted, so the appliance never leaks its existence to an outside endpoint
# and the reported address is deterministic.
get_public_ip() {
    local _ip=""
    # OneGate: query this VM's first NIC external IP if the service is reachable.
    if [[ -n "${ONEGATE_ENDPOINT:-}" ]] && command -v onegate >/dev/null 2>&1; then
        _ip=$(onegate vm show --json 2>/dev/null \
            | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)["VM"]["TEMPLATE"]
    nic=d.get("NIC")
    nic=nic[0] if isinstance(nic,list) else nic
    print((nic or {}).get("EXTERNAL_IP") or (nic or {}).get("IP") or "")
except Exception:
    print("")' 2>/dev/null | tr -d '[:space:]')
        if [[ "${_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${_ip}"
            return 0
        fi
    fi
    # Fallback: first local (NIC) IP. For a NAT'd VM set ONEAPP_COPILOT_TLS_DOMAIN
    # to publish a stable, externally-resolvable endpoint instead.
    hostname -I 2>/dev/null | awk '{print $1}'
}

# ==========================================================================
#  REPORT: write_report_file  (INI-style report at ONE_SERVICE_REPORT)
# ==========================================================================

# Writes the service report file with connection info, credentials, model
# details, live service status, client configuration, and a curl test command.
# Called at the END of service_bootstrap (after services confirmed running).
write_report_file() {
    local _vm_ip
    _vm_ip=$(get_public_ip)

    # ALWAYS read password from persisted file
    local _password
    _password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'unknown')

    # Determine TLS mode. With a publicly-trusted Let's Encrypt cert the client
    # can verify normally (no -k); with the self-signed default it cannot, so the
    # example uses --cacert against the shipped cert rather than training users
    # to blanket-disable verification with -k.
    local _tls_mode="self-signed"
    local _curl_tls="--cacert ${LLAMA_CERT_DIR}/cert.pem"
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN:-}" ] && \
       [ -f "/etc/letsencrypt/live/${ONEAPP_COPILOT_TLS_DOMAIN}/fullchain.pem" ]; then
        _tls_mode="letsencrypt (${ONEAPP_COPILOT_TLS_DOMAIN})"
        _curl_tls=""
    fi

    # Web UI password is a distinct secret from the inference API key.
    local _ui_password
    _ui_password=$(cat "${UI_PASSWORD_FILE}" 2>/dev/null || echo "${_password}")

    # Credential clients use against :8443. In standalone mode that is the
    # llama-server inference key; in LB mode :8443 is the LiteLLM proxy, which
    # authenticates with its (distinct) master key, so advertise that instead.
    local _client_key="${_password}"
    if is_lb_mode; then
        _client_key=$(cat "${LB_MASTER_KEY_FILE}" 2>/dev/null || echo "${_password}")
    fi

    # Determine endpoint URL (domain if set, IP otherwise)
    local _endpoint="https://${_vm_ip}:${LLAMA_PORT}"
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN:-}" ]; then
        _endpoint="https://${ONEAPP_COPILOT_TLS_DOMAIN}:${LLAMA_PORT}"
    fi

    # Query live service status
    local _llama_status _proxy_status=""
    _llama_status=$(systemctl is-active mistral_copilot 2>/dev/null || echo unknown)
    if is_lb_mode; then
        _proxy_status=$(systemctl is-active mistral_copilot-proxy 2>/dev/null || echo unknown)
    fi

    # Write INI-style report to framework-defined path (defensive fallback)
    local _report="${ONE_SERVICE_REPORT:-/etc/one-appliance/config}"
    mkdir -p "$(dirname "${_report}")"

    cat > "${_report}" <<EOF
[Connection info]
endpoint    = ${_endpoint}
api_key     = ${_client_key}
model       = ${ACTIVE_MODEL_ID}

[Web UI]
Open ${_endpoint} in your browser to access the llama.cpp chat interface.
Use the api_key above as the API Key if prompted.

[Service status]
llama-server = ${_llama_status}$(is_lb_mode && printf '\nlitellm-proxy = %s' "${_proxy_status}")
tls          = ${_tls_mode}

[OpenAI-compatible API]
Base URL  : ${_endpoint}/v1
API Key   : ${_client_key}
Model     : openai/${ACTIVE_MODEL_ID}

[OpenHands / other OpenAI clients]
Model     : openai/${ACTIVE_MODEL_ID}
Base URL  : ${_endpoint}/v1
API Key   : ${_client_key}

[Test with curl]
curl ${_curl_tls} -H "Authorization: Bearer ${_client_key}" ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"${ACTIVE_MODEL_ID}","messages":[{"role":"user","content":"Hello"}]}'
EOF

    # Append LB section if in load balancer mode
    if is_lb_mode; then
        local _n_remotes
        _n_remotes=$(echo "${ONEAPP_COPILOT_LB_BACKENDS}" | tr ',' '\n' | grep -c '[^[:space:]]' || true)
        cat >> "${_report}" <<EOF

[Load Balancer]
mode            = litellm (least-busy routing)
local_backend   = http://127.0.0.1:${LLAMA_PORT_LOCAL}
remote_backends = ${_n_remotes}
config          = ${LITELLM_CONFIG}
litellm_ui      = ${_endpoint}/ui
ui_username     = admin
ui_password     = ${_ui_password}
EOF
    fi

    chmod 600 "${_report}"
    log_copilot info "Report file written to ${_report}"
}

# --------------------------------------------------------------------------
# _lb_register_tls_opt -- curl TLS options for talking to the remote LB.
#   Verified by default (system CA bundle). With an internal CA supplied it
#   pins to that CA; only an explicit ONEAPP_COPILOT_REGISTER_INSECURE=YES
#   disables verification (self-signed LB on a trusted network). This keeps the
#   LB master key and the local API key off an unverified TLS channel.
# --------------------------------------------------------------------------
_lb_register_tls_opt() {
    if [[ -f "${BACKEND_CA_FILE}" ]]; then
        printf -- '--cacert %s' "${BACKEND_CA_FILE}"
    elif [[ "${ONEAPP_COPILOT_REGISTER_INSECURE:-NO}" =~ ^(YES|yes|true|1)$ ]]; then
        printf -- '-k'
    fi
}

# --------------------------------------------------------------------------
# register_with_lb -- phone home to a remote LiteLLM LB on boot
# --------------------------------------------------------------------------
register_with_lb() {
    local _lb_url="${ONEAPP_COPILOT_REGISTER_URL:-}"
    local _lb_key="${ONEAPP_COPILOT_REGISTER_KEY:-}"

    # Skip if not configured
    [[ -z "${_lb_url}" ]] && return 0

    if [[ -z "${_lb_key}" ]]; then
        log_copilot warning "ONEAPP_COPILOT_REGISTER_URL set but ONEAPP_COPILOT_REGISTER_KEY is empty -- skipping LB registration"
        return 0
    fi

    # Enforce TLS: never ship the LB master key / API key over plaintext http.
    _lb_url="${_lb_url%/}"
    if [[ "${_lb_url}" != https://* ]]; then
        log_copilot error "ONEAPP_COPILOT_REGISTER_URL must use https:// -- refusing to send credentials over plaintext; skipping LB registration"
        return 0
    fi

    # Resolve this VM's IP (first non-loopback)
    local _my_ip
    _my_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "${_my_ip}" ]]; then
        log_copilot warning "Could not determine VM IP -- skipping LB registration"
        return 0
    fi

    # Read local API key
    local _api_key
    _api_key=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo '')
    if [[ -z "${_api_key}" ]]; then
        log_copilot warning "No local API key found -- skipping LB registration"
        return 0
    fi

    # Resolve model_id from catalog for model_name (allow override)
    local _model_id="${ONEAPP_COPILOT_REGISTER_MODEL_NAME:-}"
    if [[ -z "${_model_id}" ]]; then
        _load_model_info
        _model_id="${ACTIVE_MODEL_ID:-mistral-7b}"
    fi

    # Build backend ID: prefer site name, fall back to IP
    local _backend_suffix="${ONEAPP_COPILOT_REGISTER_SITE_NAME:-${_my_ip}}"
    local _backend_id="${_model_id}-${_backend_suffix}"

    log_copilot info "Registering with remote LB at ${_lb_url} (model=${_model_id}, id=${_backend_id})"

    # Build the JSON body with jq so model/site names cannot break out of the
    # request body (proper escaping; no string interpolation into JSON).
    local _body_json
    _body_json=$(jq -nc \
        --arg model "${_model_id}" \
        --arg key "${_api_key}" \
        --arg base "https://${_my_ip}:${LLAMA_PORT}/v1" \
        --arg id "${_backend_id}" \
        '{model_name:$model, litellm_params:{model:("openai/"+$model), api_key:$key, api_base:$base}, model_info:{id:$id}}') || {
        log_copilot warning "Could not build registration payload -- skipping LB registration"
        return 0
    }

    local _tls_opt
    _tls_opt=$(_lb_register_tls_opt)

    local _response
    # shellcheck disable=SC2086  # _tls_opt is a controlled flag string, intentional split
    _response=$(curl -s ${_tls_opt} -w '\n%{http_code}' -X POST "${_lb_url}/model/new" \
        -H "Authorization: Bearer ${_lb_key}" \
        -H "Content-Type: application/json" \
        -d "${_body_json}" 2>/dev/null) || true

    local _http_code
    _http_code=$(echo "${_response}" | tail -1)

    if [[ "${_http_code}" == "200" ]] || [[ "${_http_code}" == "201" ]]; then
        # Save the model identifier for deregistration
        echo "${_backend_id}" > "${LB_MODEL_ID_FILE}"
        chmod 600 "${LB_MODEL_ID_FILE}"

        # Write deregister script for shutdown
        _write_deregister_script "${_lb_url}" "${_lb_key}" "${_tls_opt}"

        log_copilot info "Successfully registered with LB (id=${_backend_id})"
    else
        # Do not log the response body: it can echo the submitted api_key back.
        log_copilot warning "LB registration failed (HTTP ${_http_code})"
    fi
}

# --------------------------------------------------------------------------
# _write_deregister_script -- creates the shutdown-time deregister script.
#   The LB URL / master key / TLS options live in a root-only (0600) env file
#   that the script sources, so no secret is baked into an on-disk script.
# --------------------------------------------------------------------------
_write_deregister_script() {
    local _lb_url="$1"
    local _lb_key="$2"
    local _tls_opt="$3"

    ( umask 077; cat > "${LB_DEREGISTER_ENV}" <<ENVEOF
LB_URL=$(printf '%q' "${_lb_url}")
LB_KEY=$(printf '%q' "${_lb_key}")
LB_TLS_OPT=$(printf '%q' "${_tls_opt}")
ENVEOF
    )
    chmod 600 "${LB_DEREGISTER_ENV}"

    cat > "${LB_DEREGISTER_SCRIPT}" <<DEREGEOF
#!/usr/bin/env bash
# Auto-generated by Mistral Copilot -- deregisters this VM from remote LB on shutdown
LB_MODEL_ID_FILE="${LB_MODEL_ID_FILE}"
LB_DEREGISTER_ENV="${LB_DEREGISTER_ENV}"
[[ -f "\${LB_MODEL_ID_FILE}" ]] || exit 0
[[ -f "\${LB_DEREGISTER_ENV}" ]] || exit 0
# shellcheck source=/dev/null
source "\${LB_DEREGISTER_ENV}"
_model_id=\$(cat "\${LB_MODEL_ID_FILE}")
_body=\$(jq -nc --arg id "\${_model_id}" '{id:\$id}')
# shellcheck disable=SC2086
curl -s \${LB_TLS_OPT} -X POST "\${LB_URL}/model/delete" \\
    -H "Authorization: Bearer \${LB_KEY}" \\
    -H "Content-Type: application/json" \\
    -d "\${_body}" >/dev/null 2>&1 || true
rm -f "\${LB_MODEL_ID_FILE}"
DEREGEOF
    chmod 700 "${LB_DEREGISTER_SCRIPT}"

    # Create systemd unit if not present
    if [[ ! -f "${LB_DEREGISTER_UNIT}" ]]; then
        cat > "${LB_DEREGISTER_UNIT}" <<UNITEOF
[Unit]
Description=Mistral Copilot LB Deregistration
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=${LB_DEREGISTER_SCRIPT}

[Install]
WantedBy=multi-user.target
UNITEOF
        systemctl daemon-reload
        systemctl enable mistral_copilot-lb-deregister.service
        systemctl start mistral_copilot-lb-deregister.service
    fi
}

# --------------------------------------------------------------------------
# _register_lb_backends -- register local + static backends via LiteLLM API
#   Models registered via API are stored in DB (store_model_in_db=true) so
#   they can be managed from the UI without reappearing from the config file.
# --------------------------------------------------------------------------
_register_lb_backends() {
    # The master key authenticates to the local LiteLLM admin API; the inference
    # key is what a backend actually serves with. They are distinct secrets, so
    # the master key is never planted into a backend entry as an api_key.
    local _key _local_api
    _key=$(cat "${LB_MASTER_KEY_FILE}" 2>/dev/null || cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
    _local_api=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
    local _lb="https://127.0.0.1:${LITELLM_PORT}"

    # Helper: POST /model/new (idempotent -- LiteLLM upserts by model_info.id).
    # Localhost call, so -sk on the loopback self-signed cert carries no MITM
    # risk; the body is built with jq so names cannot break out of the JSON.
    _add_model() {
        local _mid="$1" _name="$2" _base="$3" _api_key="$4"
        local _body_json
        _body_json=$(jq -nc \
            --arg name "${_name}" \
            --arg base "${_base}" \
            --arg key "${_api_key}" \
            --arg id "${_mid}" \
            '{model_name:$name, litellm_params:{model:("openai/"+$name), api_base:$base, api_key:$key}, model_info:{id:$id}}') || return 0
        local _http_code
        _http_code=$(curl -sk -o /dev/null -w '%{http_code}' -X POST "${_lb}/model/new" \
            -H "Authorization: Bearer ${_key}" \
            -H "Content-Type: application/json" \
            -d "${_body_json}" 2>/dev/null) || _http_code="000"
        if [[ "${_http_code}" == "200" ]] || [[ "${_http_code}" == "201" ]]; then
            log_copilot info "Registered backend ${_mid} -> ${_base}"
        else
            log_copilot warning "Failed to register backend ${_mid} (HTTP ${_http_code})"
        fi
    }

    # Register static remote backends from ONEAPP_COPILOT_LB_BACKENDS (key@host:port,...)
    # Local backend is already in the config file (not API-managed).
    local _backends="${ONEAPP_COPILOT_LB_BACKENDS}"
    local _entries _entry _bkey _url _host
    IFS=',' read -ra _entries <<< "${_backends}"
    for _entry in "${_entries[@]}"; do
        _entry=$(echo "${_entry}" | xargs)
        [ -z "${_entry}" ] && continue
        _bkey="${_local_api}"
        _url="${_entry}"
        if [[ "${_entry}" == *@* ]]; then
            _bkey="${_entry%%@*}"
            _url="${_entry#*@}"
        fi
        [[ "${_url}" != https://* ]] && [[ "${_url}" != http://* ]] && _url="https://${_url}"
        _host=$(echo "${_url}" | sed 's|https\?://||;s|:.*||')
        _add_model "${ACTIVE_MODEL_ID}-${_host}" "${ACTIVE_MODEL_ID}" \
            "${_url}/v1" "${_bkey}"
    done
}

# --------------------------------------------------------------------------
# _setup_lb_healthcheck -- periodic health checker for dynamically registered
#   backends. Runs on the LB VM via systemd timer. Queries LiteLLM for all
#   models, health-checks each remote backend, removes unreachable ones.
# --------------------------------------------------------------------------
_setup_lb_healthcheck() {
    # The master key is read at runtime from a root-only file inside the
    # generated script, never templated into it (no secret left on a 0644 path).
    cat > "${LB_HEALTHCHECK_SCRIPT}" <<'HCEOF'
#!/usr/bin/env bash
# Auto-generated by Mistral Copilot -- removes dead backends from LiteLLM LB
set -o pipefail

LB_URL="https://127.0.0.1:LITELLM_PORT_PLACEHOLDER"
LB_KEY="$(cat /var/lib/mistral_copilot/lb_master_key 2>/dev/null || cat /var/lib/mistral_copilot/password 2>/dev/null)"
BACKEND_CA="/etc/ssl/mistral_copilot/backend-ca.pem"
HEALTH_TIMEOUT=10
MAX_FAILURES=3
STATE_DIR="/var/lib/mistral_copilot/healthcheck"
LOG="/var/log/one-appliance/mistral_copilot.log"

mkdir -p "${STATE_DIR}"

# Verify backend TLS with the internal CA when one is provided; otherwise fall
# back to unverified (self-signed backends on a trusted network).
if [[ -f "${BACKEND_CA}" ]]; then BACKEND_TLS=(--cacert "${BACKEND_CA}"); else BACKEND_TLS=(-k); fi

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] healthcheck: $*" >> "${LOG}"; }

# Get all models from LiteLLM
models_json=$(curl -sk --max-time 10 "${LB_URL}/model/info" \
    -H "Authorization: Bearer ${LB_KEY}" 2>/dev/null) || {
    log "Could not reach LiteLLM API -- skipping health check cycle"
    exit 0
}

# Extract model entries: id and api_base
# LiteLLM /model/info returns { "data": [ { "model_info": {"id":...}, "litellm_params": {"api_base":...} } ] }
echo "${models_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', [])
for m in data:
    mid = m.get('model_info', {}).get('id', '')
    base = m.get('litellm_params', {}).get('api_base', '')
    if mid and base:
        print(f'{mid}|{base}')
" 2>/dev/null | while IFS='|' read -r model_id api_base; do
    # Skip local backends (127.0.0.1 or localhost)
    if [[ "${api_base}" == *"127.0.0.1"* ]] || [[ "${api_base}" == *"localhost"* ]]; then
        continue
    fi

    # Health check: strip /v1 suffix, hit /health
    health_url="${api_base%/v1}/health"
    http_code=$(curl -s "${BACKEND_TLS[@]}" --max-time "${HEALTH_TIMEOUT}" -o /dev/null -w '%{http_code}' "${health_url}" 2>/dev/null) || http_code="000"

    state_file="${STATE_DIR}/${model_id}.failures"

    if [[ "${http_code}" == "200" ]]; then
        # Healthy -- reset failure counter
        rm -f "${state_file}"
    else
        # Unhealthy -- increment failure counter
        failures=$(cat "${state_file}" 2>/dev/null || echo 0)
        failures=$((failures + 1))
        echo "${failures}" > "${state_file}"

        if [[ ${failures} -ge ${MAX_FAILURES} ]]; then
            log "Removing dead backend ${model_id} (${api_base}) after ${failures} consecutive failures"
            curl -sk --max-time 10 -X POST "${LB_URL}/model/delete" \
                -H "Authorization: Bearer ${LB_KEY}" \
                -H "Content-Type: application/json" \
                -d "$(jq -nc --arg id "${model_id}" '{id:$id}')" >/dev/null 2>&1 || true
            rm -f "${state_file}"
        else
            log "Backend ${model_id} unhealthy (HTTP ${http_code}), failure ${failures}/${MAX_FAILURES}"
        fi
    fi
done
HCEOF

    # Replace the non-secret port placeholder only; the key is read at runtime.
    sed -i "s|LITELLM_PORT_PLACEHOLDER|${LITELLM_PORT}|g" "${LB_HEALTHCHECK_SCRIPT}"
    chmod 700 "${LB_HEALTHCHECK_SCRIPT}"

    # Systemd service (oneshot, triggered by timer)
    cat > "${LB_HEALTHCHECK_UNIT}" <<UNITEOF
[Unit]
Description=Mistral Copilot LB Backend Health Check
After=mistral_copilot-proxy.service

[Service]
Type=oneshot
ExecStart=${LB_HEALTHCHECK_SCRIPT}
UNITEOF

    # Systemd timer (every 60s)
    cat > "${LB_HEALTHCHECK_TIMER}" <<TIMEREOF
[Unit]
Description=Mistral Copilot LB Backend Health Check Timer

[Timer]
OnBootSec=120
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl daemon-reload
    systemctl enable mistral_copilot-lb-healthcheck.timer
    systemctl start mistral_copilot-lb-healthcheck.timer
    log_copilot info "LB health check timer enabled (every 60s, 3 strikes to remove)"
}

# ==========================================================================
#  LIFECYCLE: service_install  (Packer build-time, runs once)
# ==========================================================================
service_install() {
    init_copilot_log
    log_copilot info "=== service_install started ==="
    log_copilot info "Installing Mistral Copilot appliance components (llama-server)"

    # 1. Install build + runtime dependencies.
    # NOTE: do not add iptables-persistent here. ufw declares
    # "Breaks: iptables-persistent", so installing both in one transaction makes
    # apt fail with "held broken packages" (exit 100). Rules are not persisted to
    # disk: harden_firewall re-applies them on every boot
    # (ONE_SERVICE_RECONFIGURABLE=true), so ufw + iptables is sufficient.
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential cmake curl jq certbot libcurl4-openssl-dev libssl-dev \
        ufw iptables >/dev/null

    # 2. Clone and compile llama.cpp
    log_copilot info "Cloning llama.cpp at tag ${LLAMA_SERVER_VERSION}"
    local _build_dir="/tmp/llama-cpp-build"
    git clone --depth 1 --branch "${LLAMA_SERVER_VERSION}" \
        https://github.com/ggerganov/llama.cpp.git "${_build_dir}"
    # Supply-chain pin: fail closed if the tag no longer resolves to the audited
    # commit (detects a moved or re-pushed tag swapping the compiled sources).
    local _head_commit
    _head_commit=$(git -C "${_build_dir}" rev-parse HEAD 2>/dev/null || echo "")
    if [ "${_head_commit}" != "${LLAMA_SERVER_COMMIT}" ]; then
        log_copilot error "llama.cpp ${LLAMA_SERVER_VERSION} HEAD '${_head_commit}' != pinned ${LLAMA_SERVER_COMMIT} -- aborting build"
        exit 1
    fi

    log_copilot info "Compiling llama-server (this may take a while)"
    cmake -S "${_build_dir}" -B "${_build_dir}/build" \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_BACKEND_DIR=/usr/local/lib \
        -DBUILD_SHARED_LIBS=ON \
        -DLLAMA_CURL=ON \
        -DLLAMA_OPENSSL=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "${_build_dir}/build" --target llama-server -j"$(nproc)"

    # 3. Install binary and all shared libs (libllama, libggml, libmtmd, CPU backends)
    install -m 0755 "${_build_dir}/build/bin/llama-server" "${LLAMA_BIN}"
    find "${_build_dir}/build" -name "*.so*" -type f -exec cp -a {} /usr/local/lib/ \;
    find "${_build_dir}/build" -name "*.so*" -type l -exec cp -a {} /usr/local/lib/ \;
    ldconfig

    log_copilot info "llama-server installed to ${LLAMA_BIN}"

    # 4. Download Mistral 7B Instruct Q4_K_M GGUF from Hugging Face (built-in default)
    mkdir -p "${LLAMA_MODEL_DIR}"
    local _model_url="https://huggingface.co/${BUILTIN_MODEL_HF_REPO}/resolve/main/${BUILTIN_MODEL_GGUF}"
    log_copilot info "Downloading ${BUILTIN_MODEL_GGUF} from Hugging Face (approx 4 GB)"
    curl -fSL --progress-bar -o "${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}" "${_model_url}"
    if ! verify_sha256 "${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}" "${BUILTIN_MODEL_SHA256}"; then
        log_copilot error "Built-in model failed SHA256 verification -- aborting build"
        exit 1
    fi
    log_copilot info "Model downloaded and SHA256-verified at ${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}"

    # 5. Create wrapper script (handles conditional TLS for standalone vs LB mode)
    mkdir -p /etc/mistral_copilot
    # Custom Jinja chat template: uses Mistral's native tokens ([INST]/[/INST])
    # — works for both the built-in Mistral 7B Instruct and the opt-in Mistral/Devstral siblings
    # and merges consecutive same-role messages (required for OpenHands compatibility)
    cat > /etc/mistral_copilot/chat-template.jinja <<'JINJA_EOF'
{%- for message in messages -%}
  {%- if message.role == "system" -%}
    [SYSTEM_PROMPT]{{ message.content }}[/SYSTEM_PROMPT]
  {%- elif message.role == "user" -%}
    {%- if loop.index0 > 0 and messages[loop.index0 - 1].role == "user" -%}
{{ message.content }}
    {%- else -%}
[INST]{{ message.content }}
    {%- endif -%}
    {%- if loop.last or messages[loop.index0 + 1].role != "user" -%}
[/INST]
    {%- endif -%}
  {%- elif message.role == "assistant" -%}
{{ message.content }}</s>
  {%- endif -%}
{%- endfor -%}
JINJA_EOF

    cat > /usr/local/bin/mistral_copilot-start.sh <<'WRAPPER_EOF'
#!/bin/bash
source /etc/mistral_copilot/env
ARGS=(
    --host "${LLAMA_HOST}"
    --port "${LLAMA_PORT}"
    --model "${LLAMA_MODEL}"
    --alias "${LLAMA_ALIAS}"
    --ctx-size "${LLAMA_CTX_SIZE}"
    --threads "${LLAMA_THREADS}"
    --flash-attn on
    --jinja
    --chat-template-file /etc/mistral_copilot/chat-template.jinja
    --metrics
    --prio 2
    --parallel 1
    --api-key "${LLAMA_API_KEY}"
)
[ "${LLAMA_MLOCK}" = "on" ] && ARGS+=(--mlock)
[ -n "${LLAMA_SSL_KEY}" ] && ARGS+=(--ssl-key-file "${LLAMA_SSL_KEY}" --ssl-cert-file "${LLAMA_SSL_CERT}")
exec /usr/local/bin/llama-server "${ARGS[@]}"
WRAPPER_EOF
    chmod +x /usr/local/bin/mistral_copilot-start.sh

    # 6. Create systemd unit file (delegates to wrapper script)
    cat > "${LLAMA_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=Mistral Copilot AI Coding Assistant (llama-server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mistral_copilot-start.sh
Restart=on-failure
RestartSec=5
LimitMEMLOCK=infinity
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT_EOF

    # 7. Install LiteLLM proxy (optional load balancer, activated by ONEAPP_COPILOT_LB_BACKENDS)
    apt-get install -y -qq python3-pip python3-venv >/dev/null
    python3 -m venv /opt/litellm
    # Pinned versions for reproducible builds (no surprise upstream release at
    # build time). For full transitive integrity, regenerate a hash-locked set on
    # the Ubuntu build host: pip-compile --generate-hashes for the three below,
    # then install with --require-hashes.
    /opt/litellm/bin/pip install --quiet 'litellm[proxy]==1.89.1'
    /opt/litellm/bin/pip install --quiet 'prisma==0.15.0' 'nodeenv==1.10.0'

    # Install PostgreSQL (required for LiteLLM Web UI -- prisma schema mandates postgresql)
    apt-get install -y -qq postgresql postgresql-client >/dev/null

    # Pre-generate prisma client so first boot doesn't need to do it
    (
        export PATH="/opt/litellm/bin:${PATH}"
        cd /opt/litellm/lib/python3.*/site-packages/litellm/proxy
        prisma generate --schema=schema.prisma 2>/dev/null || true
    )

    /opt/litellm/bin/pip cache purge >/dev/null 2>&1 || true

    # Create systemd unit for LiteLLM proxy
    cat > "${LITELLM_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=Mistral Copilot LiteLLM Load Balancer
After=network-online.target mistral_copilot.service postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
EnvironmentFile=/etc/mistral_copilot/env
Environment=UI_USERNAME=admin
ExecStart=/opt/litellm/bin/litellm \
  --config /etc/mistral_copilot/litellm-config.yaml \
  --port 8443 \
  --num_workers 2 \
  --ssl_keyfile_path ${SLM_SSL_KEY} \
  --ssl_certfile_path ${SLM_SSL_CERT}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT_EOF

    # 8. Verify model file integrity (check file size is reasonable)
    local _model_size
    _model_size=$(stat -c%s "${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}" 2>/dev/null || echo 0)
    if [ "${_model_size}" -lt 1000000000 ]; then
        log_copilot error "Model file too small (${_model_size} bytes) -- download may be corrupted"
        exit 1
    fi
    log_copilot info "Model file verified ($(( _model_size / 1073741824 )) GB)"

    systemctl daemon-reload

    # 9. Clean up build dependencies to reduce image size
    rm -rf "${_build_dir}"
    apt-get purge -y build-essential cmake libcurl4-openssl-dev >/dev/null 2>&1 || true
    apt-get autoremove -y --purge >/dev/null 2>&1 || true
    apt-get clean -y
    rm -rf /var/lib/apt/lists/*

    # 10. Install SSH login banner
    cat > /etc/profile.d/mistral_copilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/mistral_copilot/password 2>/dev/null || echo 'see report')
_ui_password=$(cat /var/lib/mistral_copilot/ui_password 2>/dev/null || echo "${_password}")
_llama=$(systemctl is-active mistral_copilot 2>/dev/null || echo 'unknown')
_model=$(cat /var/lib/mistral_copilot/model_id 2>/dev/null || echo 'unknown')
_proxy=$(systemctl is-active mistral_copilot-proxy 2>/dev/null)
# In LB mode :8443 is the LiteLLM proxy (authenticates with the master key);
# in standalone mode it is llama-server (the inference key).
if [ "${_proxy}" = "active" ]; then
_client_key=$(cat /var/lib/mistral_copilot/lb_master_key 2>/dev/null || echo "${_password}")
else
_client_key="${_password}"
fi
printf '\n'
printf '  Mistral Copilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
if [ "${_proxy}" = "active" ]; then
printf '  Mode     : load balancer (litellm)\n'
else
printf '  Mode     : standalone (llama.cpp)\n'
fi
printf '  Status   : %s\n' "${_llama}"
printf '\n'
printf '  [OpenAI-compatible API]\n'
printf '  Base URL : https://%s:8443/v1\n' "${_vm_ip}"
printf '  API Key  : %s\n' "${_client_key}"
printf '  Model    : openai/%s\n' "${_model}"
printf '\n'
if [ "${_proxy}" = "active" ]; then
printf '  [Web UI]\n'
printf '  URL      : https://%s:8443/ui\n' "${_vm_ip}"
printf '  Login    : admin / %s\n' "${_ui_password}"
printf '\n'
fi
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : tail -f /var/log/one-appliance/mistral_copilot.log\n'
printf '\n'
BANNER_EOF
    chmod 0644 /etc/profile.d/mistral_copilot-banner.sh

    log_copilot info "Mistral Copilot appliance install complete (llama-server)"
}

# ==========================================================================
#  HELPER: materialize_backend_ca  (install optional internal CA bundle)
# ==========================================================================
# If ONEAPP_COPILOT_TLS_CA is set (a path to a PEM file or an inline PEM body),
# install it so LiteLLM (ssl_verify) and the register/healthcheck legs can
# verify self-signed LB/backend certs instead of disabling verification.
materialize_backend_ca() {
    local _ca="${ONEAPP_COPILOT_TLS_CA:-}"
    [ -z "${_ca}" ] && return 0
    mkdir -p "${LLAMA_CERT_DIR}"
    if [ -f "${_ca}" ]; then
        cp "${_ca}" "${BACKEND_CA_FILE}"
    else
        printf '%s\n' "${_ca}" > "${BACKEND_CA_FILE}"
    fi
    chmod 0644 "${BACKEND_CA_FILE}"
    log_copilot info "Internal CA bundle installed for LB/backend verification"
}

# ==========================================================================
#  HELPER: harden_firewall  (default-deny inbound + SMTP egress block)
# ==========================================================================
# Default-deny inbound except SSH (22), the API/UI port (8443) and ACME http-01
# (80). Blocks outbound SMTP so a compromised workload cannot send unsolicited
# mail (limits blast radius). Idempotent and best-effort: a firewall hiccup
# never aborts the boot.
harden_firewall() {
    log_copilot info "Hardening host firewall (default-deny inbound, SMTP egress block)"

    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset           >/dev/null 2>&1 || true
        ufw default deny incoming   >/dev/null 2>&1 || true
        ufw default allow outgoing  >/dev/null 2>&1 || true
        ufw allow 22/tcp   comment 'SSH'            >/dev/null 2>&1 || true
        ufw allow 80/tcp   comment 'ACME http-01'   >/dev/null 2>&1 || true
        ufw allow 8443/tcp comment 'Copilot API/UI' >/dev/null 2>&1 || true
        ufw logging low             >/dev/null 2>&1 || true
        ufw --force enable          >/dev/null 2>&1 || true
    fi

    # Block all outbound SMTP. The appliance never sends mail.
    if command -v iptables >/dev/null 2>&1; then
        iptables -C OUTPUT -p tcp -m multiport --dports 25,26,465,587,2525 -j REJECT 2>/dev/null \
            || iptables -A OUTPUT -p tcp -m multiport --dports 25,26,465,587,2525 -j REJECT 2>/dev/null || true
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -C OUTPUT -p tcp -m multiport --dports 25,26,465,587,2525 -j REJECT 2>/dev/null \
            || ip6tables -A OUTPUT -p tcp -m multiport --dports 25,26,465,587,2525 -j REJECT 2>/dev/null || true
    fi

    # No netfilter-persistent save: rules are re-applied on every boot, and the
    # package conflicts with ufw (see service_install), so it is not installed.

    log_copilot info "Firewall hardened (inbound 22/80/8443 only, SMTP egress blocked)"
}

# ==========================================================================
#  LIFECYCLE: service_configure  (runs at each VM boot)
# ==========================================================================
service_configure() {
    init_copilot_log
    log_copilot info "=== service_configure started ==="
    log_copilot info "Configuring Mistral Copilot"

    # 1. Validate context variables (fail-fast on invalid values)
    validate_config

    # 1b. Harden the host firewall (default-deny inbound, SMTP egress block)
    harden_firewall

    # 1c. Install optional internal CA bundle for LB/backend TLS verification
    materialize_backend_ca

    # 2. Check for AVX2 support (warn only, don't fail)
    if ! grep -q avx2 /proc/cpuinfo; then
        log_copilot warning "CPU does not support AVX2 -- llama-server inference may be slow (GGML_CPU_ALL_VARIANTS provides fallback)"
    fi

    # 3. Resolve model (built-in or download custom GGUF)
    resolve_model

    # 4. Generate/persist TLS certificate
    generate_selfsigned_cert

    # 5. Generate/persist API password
    generate_password

    # 6. Write llama-server environment file
    generate_llama_env

    # 7. Generate LiteLLM config if load balancing is enabled
    if is_lb_mode; then
        # Ensure PostgreSQL is running and litellm DB exists (for Web UI)
        systemctl start postgresql
        local _db_password
        _db_password=$(cat "${DB_PASSWORD_FILE}" 2>/dev/null || cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
        # Create the role if missing, else realign its password to the current
        # secret so Postgres and the generated DATABASE_URL stay in sync.
        if sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='litellm'" | grep -q 1; then
            sudo -u postgres psql -c "ALTER USER litellm WITH PASSWORD '${_db_password}'"
        else
            sudo -u postgres psql -c "CREATE USER litellm WITH PASSWORD '${_db_password}'"
        fi
        sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='litellm'" | grep -q 1 || \
            sudo -u postgres psql -c "CREATE DATABASE litellm OWNER litellm"
        # Push prisma schema (idempotent -- creates tables if missing)
        (
            export PATH="/opt/litellm/bin:${PATH}"
            export DATABASE_URL="postgresql://litellm:${_db_password}@localhost:5432/litellm"
            cd /opt/litellm/lib/python3.*/site-packages/litellm/proxy
            prisma db push --schema=schema.prisma --accept-data-loss 2>/dev/null || true
        )
        generate_litellm_config
    fi

    # 8. Reload systemd to pick up any env file changes
    systemctl daemon-reload

    log_copilot info "Mistral Copilot configuration complete"
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    init_copilot_log
    log_copilot info "=== service_bootstrap started ==="
    log_copilot info "Bootstrapping Mistral Copilot"

    # 0. Load model info persisted by service_configure
    _load_model_info

    # 0b. Clean up services from previous mode (handles standalone <-> LB switching)
    if is_lb_mode; then
        # LB mode: llama-server must not be on :8443 from a previous standalone boot
        systemctl stop mistral_copilot.service 2>/dev/null || true
    else
        # Standalone mode: disable proxy if it was enabled in a previous LB boot
        systemctl stop mistral_copilot-proxy.service 2>/dev/null || true
        systemctl disable mistral_copilot-proxy.service 2>/dev/null || true
        # Restart llama-server so it picks up the new env (0.0.0.0:8443 + TLS)
        # Without this, a still-running LB-mode process on 127.0.0.1:8444 makes
        # the later `systemctl start` a no-op, leaving :8443 unserved.
        systemctl stop mistral_copilot.service 2>/dev/null || true
    fi

    # 1. Attempt Let's Encrypt before starting llama-server (port 80 is free)
    attempt_letsencrypt

    # 2. Ensure a swap backstop before loading the model. With mlock off the
    #    GGUF weights are mmap'd and demand-paged, but the KV cache + compute
    #    graph (~1-2 GiB anon at ctx 8192) cannot be evicted. The marketplace
    #    certification harness runs the appliance in a generic 'base' VM whose
    #    RAM we do not control, so a small VM could OOM during model load. A
    #    guarded swapfile gives the kernel a paging backstop. Best-effort only.
    if [ ! -f /swapfile ] && ! swapon --show | grep -q '/swapfile'; then
        { fallocate -l 4G /swapfile \
            && chmod 600 /swapfile \
            && mkswap /swapfile \
            && swapon /swapfile \
            && log_copilot info "Enabled 4G swap backstop at /swapfile"; } \
            || log_copilot warning "Could not enable swap backstop (continuing without it)"
    fi

    # 3. Enable and start llama-server (both standalone and LB modes)
    systemctl enable mistral_copilot.service
    systemctl start mistral_copilot.service

    # 3. Wait for llama-server readiness
    if is_lb_mode; then
        wait_for_llama_local
    else
        wait_for_llama
    fi

    # 3b. Add persistent cross-site routes via local VR for multi-site LB
    #     VR VM lives at .99 on each site subnet and handles Tailscale
    #     subnet routing.  The local /24 is more specific so local
    #     traffic is unaffected.  192.168.96.0/20 covers sites 96-111
    #     (all current site subnets 101-109).
    #     Uses a netplan drop-in so the route survives reboots and does
    #     not depend on VR being reachable at boot time.
    if is_lb_mode; then
        local _gw _vr_ip
        _gw=$(ip route show default | awk '{print $3; exit}')
        _vr_ip="${_gw%.*}.99"
        cat > /etc/netplan/60-cross-site.yaml <<CROSSEOF
# Cross-site routing for LB mode -- route all site subnets via local VR
network:
  version: 2
  ethernets:
    ens3:
      routes:
        - to: 192.168.96.0/20
          via: ${_vr_ip}
          metric: 100
CROSSEOF
        chmod 600 /etc/netplan/60-cross-site.yaml
        netplan apply 2>/dev/null
        log_copilot info "Cross-site route persisted: 192.168.96.0/20 via ${_vr_ip} (netplan)"
    fi

    # 4. Start LiteLLM proxy if in LB mode
    if is_lb_mode; then
        systemctl enable mistral_copilot-proxy.service
        systemctl start mistral_copilot-proxy.service
        wait_for_litellm
        # 4a. Register backends via API (not config file, so UI deletions stick)
        _register_lb_backends
        # 4b. Start health check timer to cull dead remote backends
        _setup_lb_healthcheck
    else
        # Standalone mode: clean up LB-mode leftovers
        systemctl stop mistral_copilot-lb-healthcheck.timer 2>/dev/null || true
        systemctl disable mistral_copilot-lb-healthcheck.timer 2>/dev/null || true
        if [ -f /etc/netplan/60-cross-site.yaml ]; then
            rm -f /etc/netplan/60-cross-site.yaml
            netplan apply 2>/dev/null
        fi
    fi

    # 5. Write report file with connection info, credentials, client config
    write_report_file

    # 6. Register with remote LB if configured (standalone VMs only)
    register_with_lb

    if is_lb_mode; then
        log_copilot info "Mistral Copilot bootstrap complete -- LiteLLM proxy on 0.0.0.0:${LITELLM_PORT}, llama-server on 127.0.0.1:${LLAMA_PORT_LOCAL}"
    else
        log_copilot info "Mistral Copilot bootstrap complete -- llama-server on 0.0.0.0:${LLAMA_PORT}"
    fi
}

# ==========================================================================
#  LIFECYCLE: service_cleanup
# ==========================================================================
service_cleanup() {
    # No-op: the one-appliance framework calls cleanup between lifecycle stages,
    # but we must not destroy the service that bootstrap just started.
    # Service lifecycle is managed by systemd (Restart=on-failure).
    :
}

# ==========================================================================
#  LIFECYCLE: service_help
# ==========================================================================
service_help() {
    cat <<'HELP'
Mistral Copilot Appliance
=====================

Sovereign AI coding assistant powered by llama-server (llama.cpp) serving
Mistral 7B Instruct (Q4_K_M quantization) on CPU. OpenAI-compatible API
for aider and other OpenAI clients. Native TLS, Bearer token auth, Prometheus metrics.

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_AI_MODEL          AI model from catalog (default: Mistral 7B Instruct)
                                Available: Mistral 7B Instruct (built-in),
                                Devstral Small 2 24B, Mistral Small 24B, Mistral Nemo 12B
                                Non-default models are downloaded on first boot.
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 8192)
                                Valid range: 512-131072 tokens. Larger windows
                                allocate more KV-cache RAM; bump only on VMs
                                with memory to spare.
  ONEAPP_COPILOT_API_PASSWORD        API key / Bearer token (auto-generated sk-... if empty)
  ONEAPP_COPILOT_TLS_DOMAIN         FQDN for Let's Encrypt certificate (optional)
                                If empty, self-signed certificate is used
  ONEAPP_COPILOT_CPU_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance
  ONEAPP_COPILOT_LB_ENABLED         Enable LiteLLM load balancer mode (default: NO)
                                When YES, activates LiteLLM proxy on :8443 with Web UI
  ONEAPP_COPILOT_LB_BACKENDS        Remote backends for load balancing
                                Format: key@host:port,key@host:port
                                Requires ONEAPP_COPILOT_LB_ENABLED=YES

Ports:
  8443  HTTPS API (TLS + Bearer token auth + Prometheus metrics)

Service management:
  systemctl status mistral_copilot        Check inference server status
  systemctl restart mistral_copilot       Restart the inference server
  journalctl -u mistral_copilot -f        Follow inference server logs
  systemctl status mistral_copilot-proxy  Check LiteLLM proxy (LB mode only)
  journalctl -u mistral_copilot-proxy -f  Follow proxy logs (LB mode only)

Configuration files:
  /etc/mistral_copilot/env                            Environment file (llama-server config)
  /etc/ssl/mistral_copilot/cert.pem                   TLS certificate (symlink)
  /etc/ssl/mistral_copilot/key.pem                    TLS private key (symlink)
  /opt/models/                                     Model GGUF file(s)
  /etc/mistral_copilot/litellm-config.yaml             LiteLLM config (LB mode only)

Report and logs:
  /etc/one-appliance/config                    Service report (credentials, client config)
  /var/log/one-appliance/mistral_copilot.log       Application log (all stages)

Health check (self-signed: pin the shipped cert; Let's Encrypt: drop --cacert):
  curl --cacert /etc/ssl/mistral_copilot/cert.pem https://localhost:8443/health

Prometheus metrics:
  curl --cacert /etc/ssl/mistral_copilot/cert.pem https://localhost:8443/metrics

Test inference:
  curl --cacert /etc/ssl/mistral_copilot/cert.pem -H "Authorization: Bearer PASSWORD" \
    https://localhost:8443/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"mistral-7b","messages":[{"role":"user","content":"Hello"}]}'

Password retrieval:
  cat /var/lib/mistral_copilot/password
HELP
}

# ==========================================================================
#  HELPER: resolve_model  (determine model GGUF path, download if URL)
# ==========================================================================

# Globals set by resolve_model(), consumed by generate_llama_env/write_report
ACTIVE_MODEL_PATH=""
ACTIVE_MODEL_ID=""

resolve_model() {
    local _selection="${ONEAPP_COPILOT_AI_MODEL:-Mistral 7B Instruct (7B ~4GB built-in)}"

    # Look up the selection in the catalog
    local _entry="${MODEL_CATALOG[${_selection}]:-}"

    if [ -z "${_entry}" ]; then
        log_copilot error "Unknown model '${_selection}'. Available: ${!MODEL_CATALOG[*]}"
        exit 1
    fi

    # Parse catalog entry: "model_id|gguf_filename|hf_url|sha256"
    ACTIVE_MODEL_ID=$(echo "${_entry}" | cut -d'|' -f1)
    local _gguf_file _hf_url _sha256
    _gguf_file=$(echo "${_entry}" | cut -d'|' -f2)
    _hf_url=$(echo "${_entry}" | cut -d'|' -f3)
    _sha256=$(echo "${_entry}" | cut -d'|' -f4)

    ACTIVE_MODEL_PATH="${LLAMA_MODEL_DIR}/${_gguf_file}"

    # Check if model file already exists on disk (built-in or previously downloaded)
    if [ -f "${ACTIVE_MODEL_PATH}" ]; then
        local _size
        _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
        if [ "${_size}" -gt 1000000000 ]; then
            log_copilot info "Model ready: ${ACTIVE_MODEL_ID} ($(( _size / 1073741824 )) GB)"
            _persist_model_info
            return 0
        fi
        log_copilot warning "Model file incomplete, re-downloading: ${_gguf_file}"
    fi

    # No local file: download from HuggingFace
    if [ -z "${_hf_url}" ]; then
        log_copilot error "Built-in model file missing at ${ACTIVE_MODEL_PATH}"
        exit 1
    fi

    log_copilot info "Downloading ${ACTIVE_MODEL_ID} from HuggingFace..."
    mkdir -p "${LLAMA_MODEL_DIR}"
    if ! curl -4 -fSL --connect-timeout 15 --retry 2 --progress-bar -o "${ACTIVE_MODEL_PATH}" "${_hf_url}"; then
        log_copilot error "Failed to download model from ${_hf_url}"
        rm -f "${ACTIVE_MODEL_PATH}"

        # Graceful fallback: use built-in Mistral 7B Instruct if available
        local _fallback="${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}"
        if [ -f "${_fallback}" ]; then
            local _fb_size
            _fb_size=$(stat -c%s "${_fallback}" 2>/dev/null || echo 0)
            if [ "${_fb_size}" -gt 1000000000 ]; then
                log_copilot warning "Falling back to built-in Mistral 7B Instruct (download failed -- check VM internet connectivity)"
                ACTIVE_MODEL_ID="mistral-7b"
                ACTIVE_MODEL_PATH="${_fallback}"
                _persist_model_info
                return 0
            fi
        fi
        log_copilot error "No fallback model available. Ensure the VM has internet access and retry."
        exit 1
    fi

    # Integrity: verify the freshly downloaded GGUF against its pinned SHA256.
    # Fail closed -- a tampered or corrupted download is discarded, never served.
    if ! verify_sha256 "${ACTIVE_MODEL_PATH}" "${_sha256}"; then
        log_copilot error "Downloaded model failed SHA256 verification -- discarding"
        rm -f "${ACTIVE_MODEL_PATH}"
        local _fallback="${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}"
        if [ -f "${_fallback}" ] && verify_sha256 "${_fallback}" "${BUILTIN_MODEL_SHA256}"; then
            log_copilot warning "Falling back to built-in Mistral 7B Instruct (integrity check failed)"
            ACTIVE_MODEL_ID="mistral-7b"
            ACTIVE_MODEL_PATH="${_fallback}"
            _persist_model_info
            return 0
        fi
        log_copilot error "No verified fallback model available -- aborting"
        exit 1
    fi

    local _size
    _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
    log_copilot info "Model downloaded and SHA256-verified: ${ACTIVE_MODEL_ID} ($(( _size / 1073741824 )) GB)"
    _persist_model_info
}

# Persist resolved model path/ID so service_bootstrap can read them
_persist_model_info() {
    mkdir -p "${LLAMA_DATA_DIR}"
    echo "${ACTIVE_MODEL_PATH}" > "${LLAMA_DATA_DIR}/model_path"
    echo "${ACTIVE_MODEL_ID}" > "${LLAMA_DATA_DIR}/model_id"
}

# Load persisted model path/ID (for service_bootstrap, which runs in a separate stage)
_load_model_info() {
    ACTIVE_MODEL_PATH=$(cat "${LLAMA_DATA_DIR}/model_path" 2>/dev/null || echo "${LLAMA_MODEL_DIR}/${MODEL_GGUF}")
    ACTIVE_MODEL_ID=$(cat "${LLAMA_DATA_DIR}/model_id" 2>/dev/null || echo "mistral-7b")
}

# ==========================================================================
#  HELPER: validate_config  (fail-fast on invalid context variable values)
# ==========================================================================
validate_config() {
    local _errors=0

    # ONEAPP_COPILOT_CONTEXT_SIZE: must be a positive integer, reasonable range 512-131072
    if ! [[ "${ONEAPP_COPILOT_CONTEXT_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
        log_copilot error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- must be a positive integer"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -lt 512 ]; then
        log_copilot error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- minimum 512 tokens"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -gt 131072 ]; then
        log_copilot warning "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- very large context, may cause OOM on 32 GB VM"
    fi

    # ONEAPP_COPILOT_CPU_THREADS: must be a non-negative integer (0 = auto-detect)
    if ! [[ "${ONEAPP_COPILOT_CPU_THREADS}" =~ ^[0-9]+$ ]]; then
        log_copilot error "ONEAPP_COPILOT_CPU_THREADS='${ONEAPP_COPILOT_CPU_THREADS}' -- must be a non-negative integer (0=auto)"
        _errors=$((_errors + 1))
    fi

    # ONEAPP_COPILOT_TLS_DOMAIN: if set, must look like a valid FQDN (contains dot, no spaces)
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN}" ]; then
        if [[ "${ONEAPP_COPILOT_TLS_DOMAIN}" =~ [[:space:]] ]] || \
           [[ ! "${ONEAPP_COPILOT_TLS_DOMAIN}" =~ \. ]]; then
            log_copilot error "ONEAPP_COPILOT_TLS_DOMAIN='${ONEAPP_COPILOT_TLS_DOMAIN}' -- must be a valid FQDN (e.g., copilot.example.com)"
            _errors=$((_errors + 1))
        fi
    fi

    # Secrets and register identifiers: restrict to a safe charset so a value
    # cannot inject YAML/JSON/header/shell metacharacters into generated config.
    # The set (A-Za-z0-9 . _ -) still covers base64url and JWT-style tokens.
    local _f
    for _f in ONEAPP_COPILOT_API_PASSWORD ONEAPP_COPILOT_REGISTER_KEY \
              ONEAPP_COPILOT_REGISTER_MODEL_NAME ONEAPP_COPILOT_REGISTER_SITE_NAME; do
        case "${!_f}" in
            '') : ;;
            *[!A-Za-z0-9._-]*)
                log_copilot error "${_f} contains unsupported characters -- allowed: A-Z a-z 0-9 . _ -"
                _errors=$((_errors + 1)) ;;
        esac
    done

    # ONEAPP_COPILOT_REGISTER_URL: if set, must be https (credentials in transit).
    if [ -n "${ONEAPP_COPILOT_REGISTER_URL}" ] && [[ "${ONEAPP_COPILOT_REGISTER_URL}" != https://* ]]; then
        log_copilot error "ONEAPP_COPILOT_REGISTER_URL='${ONEAPP_COPILOT_REGISTER_URL}' -- must use https://"
        _errors=$((_errors + 1))
    fi

    # ONEAPP_COPILOT_TLS_EMAIL: basic sanity if set.
    if [ -n "${ONEAPP_COPILOT_TLS_EMAIL}" ]; then
        if [[ "${ONEAPP_COPILOT_TLS_EMAIL}" =~ [[:space:]] ]] || [[ "${ONEAPP_COPILOT_TLS_EMAIL}" != *@*.* ]]; then
            log_copilot error "ONEAPP_COPILOT_TLS_EMAIL='${ONEAPP_COPILOT_TLS_EMAIL}' -- must be a valid email address"
            _errors=$((_errors + 1))
        fi
    fi

    # Abort on validation errors
    if [ "${_errors}" -gt 0 ]; then
        log_copilot error "Configuration validation failed with ${_errors} error(s) -- aborting"
        exit 1
    fi

    log_copilot info "Configuration validation passed (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_CPU_THREADS}, domain=${ONEAPP_COPILOT_TLS_DOMAIN:-none})"
}

# ==========================================================================
#  HELPER: generate_selfsigned_cert  (self-signed X.509 with VM IP SAN)
# ==========================================================================
generate_selfsigned_cert() {
    local _vm_ip
    _vm_ip=$(hostname -I | awk '{print $1}')

    mkdir -p "${LLAMA_CERT_DIR}"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${LLAMA_CERT_DIR}/selfsigned-key.pem" \
        -out "${LLAMA_CERT_DIR}/selfsigned-cert.pem" \
        -days 3650 \
        -subj "/CN=Mistral Copilot" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${_vm_ip}"

    chmod 0600 "${LLAMA_CERT_DIR}/selfsigned-key.pem"
    chmod 0644 "${LLAMA_CERT_DIR}/selfsigned-cert.pem"

    # Active cert symlinks (Let's Encrypt replaces these if domain is set)
    ln -sf "${LLAMA_CERT_DIR}/selfsigned-cert.pem" "${LLAMA_CERT_DIR}/cert.pem"
    ln -sf "${LLAMA_CERT_DIR}/selfsigned-key.pem" "${LLAMA_CERT_DIR}/key.pem"

    log_copilot info "Self-signed certificate generated for ${_vm_ip}"
}

# ==========================================================================
#  HELPER: generate_password  (auto-generate or persist user-provided)
# ==========================================================================
# Create a random 0600 secret at the given path if it does not already exist.
# Idempotent so secrets are stable across reboots/reconfigures.
_ensure_secret() {
    local _file="$1" _prefix="${2:-}"
    [ -f "${_file}" ] && return 0
    mkdir -p "$(dirname "${_file}")"
    printf '%s%s\n' "${_prefix}" "$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)" > "${_file}"
    chmod 0600 "${_file}"
}

generate_password() {
    local _password="${ONEAPP_COPILOT_API_PASSWORD:-}"

    if [ -z "${_password}" ]; then
        # Preserve existing auto-generated password across reboots
        if [ -f "${LLAMA_DATA_DIR}/password" ]; then
            log_copilot info "Keeping existing auto-generated API key"
        else
            _password="sk-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)"
            log_copilot info "Auto-generated API key (no ONEAPP_COPILOT_API_PASSWORD set)"
        fi
    fi

    if [ -n "${_password}" ]; then
        mkdir -p "${LLAMA_DATA_DIR}"
        echo "${_password}" > "${LLAMA_DATA_DIR}/password"
        chmod 0600 "${LLAMA_DATA_DIR}/password"
        log_copilot info "API key persisted to ${LLAMA_DATA_DIR}/password"
    fi

    # Distinct per-role secrets so the inference key is never reused as the LB
    # master key, the Web UI login, or the database password.
    _ensure_secret "${LB_MASTER_KEY_FILE}" "sk-"
    _ensure_secret "${UI_PASSWORD_FILE}"
    _ensure_secret "${DB_PASSWORD_FILE}"
}

# ==========================================================================
#  HELPER: generate_llama_env  (write systemd environment file)
# ==========================================================================
generate_llama_env() {
    local _password
    _password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')

    local _threads="${ONEAPP_COPILOT_CPU_THREADS:-0}"
    if [ "${_threads}" = "0" ] || [ -z "${_threads}" ]; then
        _threads=$(nproc)
        log_copilot info "Auto-detected ${_threads} CPU threads"
    fi

    local _host="0.0.0.0"
    local _port="${LLAMA_PORT}"
    local _ssl_key="${LLAMA_CERT_DIR}/key.pem"
    local _ssl_cert="${LLAMA_CERT_DIR}/cert.pem"

    # mlock is OFF by default. llama.cpp mmaps the GGUF so pages fault in on
    # demand; this lets the model load on a modestly sized VM (the marketplace
    # certification harness instantiates a generic 'base' template, not the
    # 32 GB template declared in metadata.yaml). mlock would pin every page
    # resident and prevent demand-paging, hanging model load on a small VM.
    # It is a latency optimization only; correctness does not depend on it.
    local _mlock="off"
    if is_lb_mode; then
        _host="127.0.0.1"
        _port="${LLAMA_PORT_LOCAL}"
        _ssl_key=""
        _ssl_cert=""
        _mlock="off"
        ONEAPP_COPILOT_CONTEXT_SIZE=8192
        log_copilot info "LB mode: llama-server on 127.0.0.1:${LLAMA_PORT_LOCAL} (no TLS, ctx=8192, mlock=off)"
    fi

    mkdir -p /etc/mistral_copilot

    cat > "${LLAMA_ENV_FILE}" <<EOF
LLAMA_HOST=${_host}
LLAMA_PORT=${_port}
LLAMA_MODEL=${ACTIVE_MODEL_PATH}
LLAMA_ALIAS=${ACTIVE_MODEL_ID}
LLAMA_CTX_SIZE=${ONEAPP_COPILOT_CONTEXT_SIZE}
LLAMA_THREADS=${_threads}
LLAMA_SSL_KEY=${_ssl_key}
LLAMA_SSL_CERT=${_ssl_cert}
LLAMA_API_KEY=${_password}
LLAMA_MLOCK=${_mlock}
SLM_SSL_KEY=${LLAMA_CERT_DIR}/key.pem
SLM_SSL_CERT=${LLAMA_CERT_DIR}/cert.pem
EOF
    chmod 0600 "${LLAMA_ENV_FILE}"

    log_copilot info "Environment file written to ${LLAMA_ENV_FILE} (ctx_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${_threads})"
}

# ==========================================================================
#  HELPER: wait_for_llama  (poll health endpoint, 300s timeout)
# ==========================================================================
wait_for_llama() {
    local _timeout=300
    local _elapsed=0
    log_copilot info "Waiting for llama-server readiness (timeout: ${_timeout}s)"
    while ! curl -sfk "https://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            # Do NOT abort bootstrap: returning lets write_report_file run so
            # /etc/one-appliance/config always exists. The service keeps loading
            # under systemd (Restart=on-failure) and /health flips to 200 once
            # the model finishes. Aborting here would leave the report file
            # missing and fail readiness checks that gate on it.
            log_copilot warning "llama-server not ready after ${_timeout}s -- writing report anyway; systemd will keep retrying (journalctl -u mistral_copilot)"
            return 0
        fi
    done
    log_copilot info "llama-server ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: wait_for_llama_local  (poll HTTP health, LB mode only)
# ==========================================================================
wait_for_llama_local() {
    local _timeout=300 _elapsed=0
    log_copilot info "Waiting for local llama-server on :${LLAMA_PORT_LOCAL}"
    while ! curl -sf "http://127.0.0.1:${LLAMA_PORT_LOCAL}/health" >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "llama-server not ready after ${_timeout}s"
            exit 1
        fi
    done
    log_copilot info "Local llama-server ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: wait_for_litellm  (poll HTTPS health, LB mode only)
# ==========================================================================
wait_for_litellm() {
    local _timeout=60 _elapsed=0
    log_copilot info "Waiting for LiteLLM proxy on :${LITELLM_PORT}"
    while ! curl -sfk "https://127.0.0.1:${LITELLM_PORT}/health/liveliness" >/dev/null 2>&1; do
        sleep 3
        _elapsed=$((_elapsed + 3))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "LiteLLM proxy not ready after ${_timeout}s"
            exit 1
        fi
    done
    log_copilot info "LiteLLM proxy ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: generate_litellm_config  (LiteLLM YAML for load balancing)
# ==========================================================================
generate_litellm_config() {
    local _local_password _master_key _ui_password _db_password
    _local_password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
    _master_key=$(cat "${LB_MASTER_KEY_FILE}" 2>/dev/null || echo "${_local_password}")
    _ui_password=$(cat "${UI_PASSWORD_FILE}" 2>/dev/null || echo "${_local_password}")
    _db_password=$(cat "${DB_PASSWORD_FILE}" 2>/dev/null || echo "${_local_password}")

    # ssl_verify: pin to the internal CA bundle when provided (LiteLLM passes the
    # string path through to httpx); otherwise disable verification for
    # self-signed backends on a trusted network.
    local _ssl_verify="false"
    [ -f "${BACKEND_CA_FILE}" ] && _ssl_verify="\"${BACKEND_CA_FILE}\""

    # Local backend is always in config (not deletable from UI).
    # Remote backends are registered via API/DB so they can be managed from UI.
    cat > "${LITELLM_CONFIG}" <<EOF
model_list:
  - model_name: "${ACTIVE_MODEL_ID}"
    litellm_params:
      model: "openai/${ACTIVE_MODEL_ID}"
      api_base: "http://127.0.0.1:${LLAMA_PORT_LOCAL}/v1"
      api_key: "${_local_password}"
      timeout: 600
    model_info:
      id: "${ACTIVE_MODEL_ID}-local"
EOF

    # Append router and general settings
    cat >> "${LITELLM_CONFIG}" <<EOF

router_settings:
  routing_strategy: "least-busy"
  allowed_fails: 2
  cooldown_time: 30
  timeout: 600

litellm_settings:
  ssl_verify: ${_ssl_verify}
  default_model: "${ACTIVE_MODEL_ID}"
  request_timeout: 600

general_settings:
  master_key: "${_master_key}"
  database_url: "postgresql://litellm:${_db_password}@localhost:5432/litellm"
  admin_only_routes: ["/model/new", "/model/update", "/model/delete", "/key/generate", "/key/update", "/key/delete", "/user/new", "/user/update"]

environment_variables:
  STORE_MODEL_IN_DB: "True"
  UI_USERNAME: "admin"
  UI_PASSWORD: "${_ui_password}"
  LITELLM_HEALTH_CHECK_TIMEOUT: "120"
EOF

    chmod 0600 "${LITELLM_CONFIG}"
    log_copilot info "LiteLLM config generated (distinct master/UI/DB secrets, admin routes locked)"
}

# ==========================================================================
#  HELPER: smoke_test  (verify chat completions, streaming, and health)
# ==========================================================================
smoke_test() {
    local _endpoint="${1:-https://127.0.0.1:${LLAMA_PORT}}"
    local _api_key="${2:-$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')}"

    log_copilot info "Running smoke test against ${_endpoint}"

    # Test 1: Health endpoint
    curl -sfk "${_endpoint}/health" >/dev/null 2>&1 || {
        log_copilot error "Smoke test: health check (/health) did not return 200"
        return 1
    }
    log_copilot info "Smoke test: health check OK"

    # Test 2: Non-streaming chat completion
    local _model_id
    _model_id=$(cat "${LLAMA_DATA_DIR}/model_id" 2>/dev/null || echo "mistral-7b")
    local _response
    _response=$(curl -sfk "${_endpoint}/v1/chat/completions" \
        -H "Authorization: Bearer ${_api_key}" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${_model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python hello world\"}],\"max_tokens\":50}") || {
        log_copilot error "Smoke test: chat completion request failed"
        return 1
    }
    echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1 || {
        log_copilot error "Smoke test: no content in chat completion response"
        return 1
    }
    log_copilot info "Smoke test: chat completion OK"

    # Test 3: Streaming chat completion
    curl -sfk "${_endpoint}/v1/chat/completions" \
        -H "Authorization: Bearer ${_api_key}" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${_model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"max_tokens\":10,\"stream\":true}" \
        | grep -q 'data:' || {
        log_copilot error "Smoke test: streaming response has no SSE data lines"
        return 1
    }
    log_copilot info "Smoke test: streaming OK"

    log_copilot info "All smoke tests passed"
    return 0
}

# ==========================================================================
#  HELPER: attempt_letsencrypt  (certbot standalone, port 80 is free)
# ==========================================================================
attempt_letsencrypt() {
    local _domain="${ONEAPP_COPILOT_TLS_DOMAIN:-}"

    if [ -z "${_domain}" ]; then
        log_copilot info "ONEAPP_COPILOT_TLS_DOMAIN not set -- using self-signed certificate"
        return 0
    fi

    log_copilot info "Attempting Let's Encrypt certificate for ${_domain}"

    # Register with the operator's email when provided (enables expiry warnings
    # and account recovery); fall back to anonymous registration otherwise.
    local _email_args=(--register-unsafely-without-email)
    if [ -n "${ONEAPP_COPILOT_TLS_EMAIL:-}" ]; then
        _email_args=(--email "${ONEAPP_COPILOT_TLS_EMAIL}")
        log_copilot info "Registering Let's Encrypt account with ${ONEAPP_COPILOT_TLS_EMAIL}"
    fi

    # Port 80 is free (no nginx), use certbot standalone
    if certbot certonly \
        --non-interactive \
        --agree-tos \
        "${_email_args[@]}" \
        --standalone \
        --preferred-challenges http \
        -d "${_domain}" 2>&1; then

        # Success: switch active symlinks to Let's Encrypt certs
        ln -sf "/etc/letsencrypt/live/${_domain}/fullchain.pem" "${LLAMA_CERT_DIR}/cert.pem"
        ln -sf "/etc/letsencrypt/live/${_domain}/privkey.pem" "${LLAMA_CERT_DIR}/key.pem"
        log_copilot info "Let's Encrypt certificate installed for ${_domain}"

        # Set up renewal cron (restart llama-server to pick up new certs)
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/mistral_copilot-restart.sh <<'HOOK'
#!/bin/bash
systemctl restart mistral_copilot
# Also restart LiteLLM proxy if active (LB mode uses TLS on the proxy)
systemctl is-active --quiet mistral_copilot-proxy && systemctl restart mistral_copilot-proxy
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/mistral_copilot-restart.sh
    else
        log_copilot warning "Let's Encrypt failed for ${_domain} -- keeping self-signed certificate"
        log_copilot warning "Ensure: DNS resolves ${_domain} to this VM, port 80 is reachable from internet"
    fi
}
