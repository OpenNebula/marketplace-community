#!/usr/bin/env bash
set -o errexit -o pipefail

# --------------------------------------------------------------------------- #
# NemoClaw OpenNebula Marketplace Appliance
# --------------------------------------------------------------------------- #
# Pre-installs NemoClaw and all dependencies. After boot, the user runs
# `nemoclaw onboard` interactively following the official NVIDIA docs.
#
# Lifecycle:
#   service_install()   : Packer build time - bake dependencies into image
#   service_configure() : Every boot - detect GPU, write MOTD
#   service_bootstrap() : First boot - verify NemoClaw ready, show instructions
#   service_cleanup()   : Reconfigure support
# --------------------------------------------------------------------------- #

# ========================== Constants ====================================== #

NEMOCLAW_INSTALL_URL="https://www.nvidia.com/nemoclaw.sh"
NVIDIA_DRIVER_BRANCH="550-server"
NODEJS_MAJOR="22"

DOCKER_LOG_MAX_SIZE="10m"
DOCKER_LOG_MAX_FILE="3"

# ========================== Metadata ======================================= #

ONE_SERVICE_NAME='NemoClaw'
ONE_SERVICE_VERSION='0.1.0'
ONE_SERVICE_RECONFIGURABLE=true
ONE_SERVICE_SHORTSTARTMSG='NemoClaw appliance is starting...'
ONE_SERVICE_STARTMSG='All set and ready to serve'

# ========================== Parameters ===================================== #
# No mandatory parameters. User runs `nemoclaw onboard` after SSH.

ONE_SERVICE_PARAMS=()

# ========================== service_install() ============================== #
# Runs during Packer build. Installs all runtime dependencies.

service_install()
{
    # 0. Wait for any existing apt/dpkg locks (unattended-upgrades, cloud-init)
    msg info "Waiting for dpkg lock..."
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done
    while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true

    # 1. Prerequisites
    msg info "Installing prerequisite packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        pciutils \
        jq

    # 2. Docker Engine CE
    msg info "Installing Docker Engine CE..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable docker

    # Docker log rotation
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<DOCKER_EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "${DOCKER_LOG_MAX_SIZE}",
        "max-file": "${DOCKER_LOG_MAX_FILE}"
    }
}
DOCKER_EOF

    # 3. NVIDIA driver
    msg info "Installing NVIDIA driver ${NVIDIA_DRIVER_BRANCH}..."
    apt-get install -y "nvidia-driver-${NVIDIA_DRIVER_BRANCH}"

    # 4. NVIDIA Container Toolkit
    msg info "Installing NVIDIA Container Toolkit..."
    rm -f /etc/apt/sources.list.d/nvidia*.list 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/nvidia*.sources 2>/dev/null || true

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    chmod 644 /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    cat > /etc/apt/sources.list.d/nvidia-container-toolkit.sources <<'NCTK_EOF'
Types: deb
URIs: https://nvidia.github.io/libnvidia-container/stable/deb/$(ARCH)
Suites: /
Signed-By: /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
NCTK_EOF

    apt-get update
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker

    # 5. Node.js
    msg info "Installing Node.js ${NODEJS_MAJOR} LTS..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODEJS_MAJOR}.x" | bash -
    apt-get install -y nodejs

    # 6. NemoClaw
    msg info "Installing NemoClaw..."
    curl -fsSL "${NEMOCLAW_INSTALL_URL}" -o /tmp/nemoclaw-install.sh
    bash /tmp/nemoclaw-install.sh --non-interactive \
        || msg warning "NemoClaw onboard skipped (expected during build)"
    rm -f /tmp/nemoclaw-install.sh

    # 7. Disable systemd-networkd-wait-online (prevents boot delays)
    msg info "Disabling systemd-networkd-wait-online service..."
    systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

    # 8. Swap space
    msg info "Configuring 4G swap space..."
    fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 0600 /swapfile
    mkswap /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # 9. Login welcome banner (survives one-apps MOTD override)
    msg info "Creating login welcome banner..."
    cat > /etc/profile.d/99-nemoclaw-welcome.sh <<'WELCOME_EOF'
#!/bin/bash
case $- in
    *i*) ;;
      *) return;;
esac
echo "=================================================="
echo "  NemoClaw Appliance"
echo "  NVIDIA AI Agent Security Stack"
echo "=================================================="
echo ""
if command -v nemoclaw &>/dev/null; then
    echo "  NemoClaw: $(nemoclaw --version 2>/dev/null || echo 'installed')"
else
    echo "  NemoClaw: not found"
fi
echo ""
echo "  Get started:"
echo "    1. Get your API key at https://build.nvidia.com"
echo "    2. Run: nemoclaw onboard"
echo "    3. Follow the interactive setup wizard"
echo "    4. Connect: nemoclaw <sandbox-name> connect"
echo ""
echo "  Docs: https://docs.nvidia.com/nemoclaw/latest/"
echo ""
echo "  Default root password: opennebula"
echo "=================================================="
WELCOME_EOF
    chmod +x /etc/profile.d/99-nemoclaw-welcome.sh

    # 10. Cleanup
    msg info "Running post-install cleanup..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true
    find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
    rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
    sync
}

# ========================== service_configure() ============================ #
# Runs at every boot. Detects GPU, ensures Docker is running.

service_configure()
{
    msg info "Configuring NemoClaw appliance..."

    # Set default root password if not already set (virt-sysprep clears it)
    local _shadow
    _shadow=$(getent shadow root | cut -d: -f2)
    if [ "$_shadow" = "*" ] || [ "$_shadow" = "!" ] || [ -z "$_shadow" ]; then
        msg info "Setting default root password (opennebula)..."
        echo 'root:opennebula' | chpasswd
    fi

    # Ensure Docker is running
    if ! systemctl is-active --quiet docker; then
        msg info "Starting Docker daemon..."
        systemctl start docker
    fi

    # Detect GPU
    detect_gpu

    # Write MOTD
    write_motd

    return 0
}

# ========================== service_bootstrap() ============================ #
# Runs at first boot. Verifies NemoClaw is installed and shows instructions.

service_bootstrap()
{
    msg info "Bootstrapping NemoClaw appliance..."

    # Verify NemoClaw CLI is available
    if ! command -v nemoclaw &>/dev/null; then
        msg error "NemoClaw CLI not found. Installation may have failed."
        return 1
    fi

    local _version
    _version=$(nemoclaw --version 2>/dev/null || echo "unknown")
    msg info "NemoClaw ${_version} is installed and ready for onboarding."

    # Write final MOTD with instructions
    write_motd

    # Append success marker
    echo "" >> /etc/motd
    echo "  ${ONE_SERVICE_STARTMSG}" >> /etc/motd
    echo "" >> /etc/motd

    return 0
}

# ========================== service_cleanup() ============================== #

service_cleanup()
{
    msg info "Cleanup for recontext..."
    return 0
}

# ========================== GPU Detection ================================== #

GPU_DETECTED=false
GPU_MODEL=""
GPU_MEMORY=""

detect_gpu()
{
    msg info "Detecting NVIDIA GPU..."

    if lspci 2>/dev/null | grep -qi 'nvidia'; then
        if [ -e /dev/nvidia0 ] || [ -e /dev/nvidiactl ]; then
            if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
                GPU_DETECTED=true
                GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
                GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
                msg info "GPU detected: ${GPU_MODEL} (${GPU_MEMORY})"

                if command -v nvidia-ctk &>/dev/null; then
                    nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>/dev/null || true
                fi
                return 0
            fi
        fi
    fi

    GPU_DETECTED=false
    msg info "No GPU detected. NemoClaw will use cloud inference."
    return 0
}

# ========================== MOTD =========================================== #

write_motd()
{
    local _ver=""
    if command -v nemoclaw &>/dev/null; then
        _ver=$(nemoclaw --version 2>/dev/null || echo "unknown")
    fi

    cat > /etc/motd <<MOTD_EOF
============================================================
  NemoClaw Appliance v${ONE_SERVICE_VERSION}
  NemoClaw: ${_ver:-not installed}
============================================================

  GPU: $(if [ "${GPU_DETECTED}" = "true" ]; then echo "YES - ${GPU_MODEL} (${GPU_MEMORY})"; else echo "NO - Cloud inference available"; fi)

  Get started:
    1. Get your API key at https://build.nvidia.com
    2. Run: nemoclaw onboard
    3. Follow the interactive setup wizard
    4. Connect: nemoclaw <sandbox-name> connect

  Docs: https://docs.nvidia.com/nemoclaw/latest/

  WARNING: NemoClaw is alpha software. APIs may change.
============================================================
MOTD_EOF

    chmod 644 /etc/motd
}
