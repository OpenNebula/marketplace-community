#!/usr/bin/env bash

# This script contains the implementation logic for the srsRAN Project appliance
# srsRAN Project is an open-source 5G software radio suite with Split 7.2 support

### srsRAN Project Configuration ##########################################################

# Configuration paths and variables
SRSRAN_CONFIG_DIR="/etc/srsran"
SRSRAN_INSTALL_DIR_BASE="/usr/local/srsran"
SRSRAN_INSTALL_DIR_DPDK="/usr/local/srsran-dpdk"
SRSRAN_LOG_DIR="/var/log/srsran"
SRSRAN_DATA_DIR="/opt/srsran"
ONE_SERVICE_SETUP_DIR="/opt/one-appliance" ### Install location. Required by bash helpers
SRSRAN_VERSION="release_24_10_1"
TEMP_DIR="/tmp/srsran_install"
BUILD_DIR="/tmp/srsran_build"

# Dynamic install directory based on DPDK selection (set in service_configure)
SRSRAN_INSTALL_DIR="${SRSRAN_INSTALL_DIR_BASE}"

### CONTEXT SECTION ##########################################################

# List of contextualization parameters
# These variables are defined in the CONTEXT section of the VM Template as custom variables
ONE_SERVICE_PARAMS=(
    'ONEAPP_SRSRAN_MODE'            'configure' 'srsRAN deployment mode (gnb: cu+du, cu, du)'           'gnb'
    'ONEAPP_SRSRAN_MCC'             'configure' 'Mobile Country Code'                                    '999'
    'ONEAPP_SRSRAN_MNC'             'configure' 'Mobile Network Code'                                    '75'
    'ONEAPP_SRSRAN_TAC'             'configure' 'Tracking Area Code'                                     '1'
    'ONEAPP_SRSRAN_ENABLE_DPDK'     'configure' 'Enable DPDK support'                                   'YES'
    'ONEAPP_SRSRAN_PCI'             'configure' 'Physical Cell Identity'                                '69'
    'ONEAPP_SRSRAN_DL_ARFCN'        'configure' 'Downlink ARFCN'                                        '656668'
    'ONEAPP_SRSRAN_BAND'            'configure' 'NR Band'                                               'n77'
    'ONEAPP_SRSRAN_COMMON_SCS'      'configure' 'Common Subcarrier Spacing'                            '30'
    'ONEAPP_SRSRAN_CHANNEL_BW_MHZ'  'configure' 'Channel Bandwidth MHz'                                 '100'
    'ONEAPP_SRSRAN_NR_CELLS'        'configure' 'Number of NR cells'                                    '1'
    'ONEAPP_SRSRAN_AMF_IPV4'        'configure' 'AMF IPv4 address'                                      '10.0.3.2'
    'ONEAPP_SRSRAN_NIC_PCI_ADDR'    'configure' 'NIC PCI passthrough address'                           '0000:01:01.0'
    'ONEAPP_SRSRAN_RU_MAC'          'configure' 'RU MAC address'                                        'e8:c7:4f:25:89:41'
)

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

# Appliance metadata
ONE_SERVICE_NAME='Service srsRAN ONEedge5G - KVM'
ONE_SERVICE_VERSION='0.5'   # srsRAN Project release_24_10_1
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance running srsRAN Project 5G software radio suite developed within ONEedge5G project'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled srsRAN Project - a complete 5G software radio suite
with Split 7.2 support for disaggregated deployments, developed within the ONEedge5G project.
Run with default values
and manually configure it, or use contextualization variables to automate the bootstrap.

After deploying the appliance, check the status of the deployment in
/etc/one-appliance/status. You can check the appliance logs in
/var/log/one-appliance/.

This appliance supports multiple deployment modes:
- **gNodeB**: CU+DU combined deployment (Split 7.2)
- **CU**: Central Unit (CU-CP + CU-UP combined)
- **DU**: Distributed Unit (Split 7.2)

The appliance includes:
- Dual installation support (base + DPDK versions) for high-performance deployments with DPDK 23.11
- Intel iavf driver v4.13.3 with PTP support for precise time synchronization
- LinuxPTP 4.3 for VM clock synchronization with hardware PTP clocks
- Real-Time (RT-PREEMPT) kernel 6.8.2-rt10 for ultra-low latency performance
- Performance optimizations: DRM KMS polling disabled, network buffers optimized, RT priorities elevated
- Optimized configuration for Split 7.2 deployments

**NOTE: The appliance supports reconfiguration. Modifying context variables
will trigger service reconfiguration on the next boot.**
EOF
)

# Reconfiguration support
ONE_SERVICE_RECONFIGURABLE=true

# ------------------------------------------------------------------------------
# Contextualization defaults
# ------------------------------------------------------------------------------

# Default values from LiteON production configuration
ONEAPP_SRSRAN_MODE="${ONEAPP_SRSRAN_MODE:-gnb}"
ONEAPP_SRSRAN_MCC="${ONEAPP_SRSRAN_MCC:-999}"
ONEAPP_SRSRAN_MNC="${ONEAPP_SRSRAN_MNC:-75}"
ONEAPP_SRSRAN_TAC="${ONEAPP_SRSRAN_TAC:-1}"
ONEAPP_SRSRAN_ENABLE_DPDK="${ONEAPP_SRSRAN_ENABLE_DPDK:-YES}"
ONEAPP_SRSRAN_PCI="${ONEAPP_SRSRAN_PCI:-69}"
ONEAPP_SRSRAN_DL_ARFCN="${ONEAPP_SRSRAN_DL_ARFCN:-656668}"
ONEAPP_SRSRAN_BAND="${ONEAPP_SRSRAN_BAND:-n77}"
ONEAPP_SRSRAN_COMMON_SCS="${ONEAPP_SRSRAN_COMMON_SCS:-30}"
ONEAPP_SRSRAN_CHANNEL_BW_MHZ="${ONEAPP_SRSRAN_CHANNEL_BW_MHZ:-100}"
ONEAPP_SRSRAN_NR_CELLS="${ONEAPP_SRSRAN_NR_CELLS:-1}"
ONEAPP_SRSRAN_AMF_IPV4="${ONEAPP_SRSRAN_AMF_IPV4:-10.0.3.2}"
ONEAPP_SRSRAN_NIC_PCI_ADDR="${ONEAPP_SRSRAN_NIC_PCI_ADDR:-0000:01:01.0}"
ONEAPP_SRSRAN_RU_MAC="${ONEAPP_SRSRAN_RU_MAC:-e8:c7:4f:25:89:41}"

###############################################################################
###############################################################################
###############################################################################

# Mandatory Functions - called by the appliance service manager

service_install()
{
    mkdir -p "$ONE_SERVICE_SETUP_DIR"
    mkdir -p "$SRSRAN_CONFIG_DIR"
    mkdir -p "$SRSRAN_LOG_DIR"
    mkdir -p "$SRSRAN_DATA_DIR"

    msg info "Update package repositories"
    apt-get update

    msg info "Install srsRAN Project dependencies (RT kernel already installed by Packer)"
    if ! apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev \
        libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev \
        git wget curl tar ethtool; then
        msg error "Failed to install build dependencies"
        exit 1
    fi

    msg info "Install tuna package for RT thread management"
    if ! apt-get install -y tuna; then
        msg warning "Failed to install tuna package - RT priority elevation may not work"
    else
        msg info "Tuna package installed successfully"
    fi

    msg info "Install LinuxPTP 4.3 from source for VM clock synchronization"
    install_linuxptp_from_source

    msg info "Configure ptp_kvm module for KVM PTP clock support"
    echo "ptp_kvm" > /etc/modules-load.d/ptp_kvm.conf
    msg info "ptp_kvm module configured to load at boot"

    msg info "Install Intel iavf driver v4.13.3 from source for PTP support"
    install_iavf_driver_from_source

    # Install DPDK 23.11 from source (recommended by srsRAN documentation)
    msg info "Installing DPDK 23.11 from source for dual installation"
    install_dpdk_from_source

    msg info "Installing igb_uio driver for DPDK support"
    install_igb_uio_driver

    msg info "Download srsRAN Project $SRSRAN_VERSION"
    # Create temporary directories
    rm -rf "$TEMP_DIR" "$BUILD_DIR"
    mkdir -p "$TEMP_DIR" "$BUILD_DIR"
    cd "$TEMP_DIR"

    # Download srsRAN Project from GitHub
    wget "https://github.com/srsran/srsRAN_Project/archive/${SRSRAN_VERSION}.tar.gz" -O "srsRAN_Project-${SRSRAN_VERSION}.tar.gz"
    
    if [ ! -f "srsRAN_Project-${SRSRAN_VERSION}.tar.gz" ]; then
        msg error "Failed to download srsRAN Project archive"
        exit 1
    fi

    msg info "Extracting srsRAN Project archive"
    tar -xzf "srsRAN_Project-${SRSRAN_VERSION}.tar.gz"
    
    # Find extracted directory
    local extracted_dir=$(find . -maxdepth 1 -name "srsRAN_Project*" -type d | head -1)
    if [ -z "$extracted_dir" ]; then
        msg error "Could not find extracted srsRAN directory"
        exit 1
    fi

    # Build both versions: regular and DPDK-enabled
    msg info "Building base srsRAN version..."
    if ! build_srsran_version "base" "$SRSRAN_INSTALL_DIR_BASE" "no"; then
        msg error "Failed to build base srsRAN version"
        exit 1
    fi
    
    # Check if DPDK is available and build DPDK version
    if check_dpdk_available; then
        msg info "Building DPDK srsRAN version..."
        if ! build_srsran_version "dpdk" "$SRSRAN_INSTALL_DIR_DPDK" "yes"; then
            msg warning "Failed to build DPDK srsRAN version, continuing with base version only"
        fi
    else
        msg warning "DPDK not available, skipping DPDK version build"
    fi

    msg info "Configure library paths for both installations"
    echo "$SRSRAN_INSTALL_DIR_BASE/lib" > /etc/ld.so.conf.d/srsran-base.conf
    if [ -d "$SRSRAN_INSTALL_DIR_DPDK/lib" ]; then
        echo "$SRSRAN_INSTALL_DIR_DPDK/lib" > /etc/ld.so.conf.d/srsran-dpdk.conf
    fi
    ldconfig

    # Update PATH for both versions - Fix PATH configuration for /etc/environment
    # Remove any existing srsRAN PATH entries first
    sed -i '/srsran/d' /etc/environment
    
    # Add srsRAN paths to system PATH properly
    current_path=$(grep "^PATH=" /etc/environment | cut -d'=' -f2- | tr -d '"' || echo "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    
    # Create new PATH with srsRAN directories
    new_path="$SRSRAN_INSTALL_DIR_BASE/bin:$SRSRAN_INSTALL_DIR_DPDK/bin:$current_path"
    
    # Update /etc/environment correctly (no export statement)
    sed -i '/^PATH=/d' /etc/environment
    echo "PATH=\"$new_path\"" >> /etc/environment
    
    # Also create profile script for immediate availability
    cat > /etc/profile.d/srsran.sh << 'EOF'
export PATH="/usr/local/srsran/bin:/usr/local/srsran-dpdk/bin:$PATH"
EOF
    chmod +x /etc/profile.d/srsran.sh

    # Create realtime group first
    if ! grep -q "^realtime:" /etc/group; then
        addgroup --system realtime
        msg info "Created realtime group"
    fi

    # Services will run as root - no dedicated user needed
    # msg info "Create srsRAN system user"
    # useradd -r -s /bin/false -d "$SRSRAN_DATA_DIR" srsran || true
    # 
    # # Add srsran user to realtime group for RT capabilities
    # usermod -a -G realtime srsran
    # msg info "Added srsran user to realtime group"
    msg info "Services will run as root - no dedicated user needed"
    
    chown -R root:root "$SRSRAN_DATA_DIR"
    chown -R root:root "$SRSRAN_LOG_DIR"

    msg info "Create systemd service files"
    create_systemd_services

    msg info "Install production configuration templates"
    install_config_templates

    msg info "Verify installations"
    export PATH="$SRSRAN_INSTALL_DIR_BASE/bin:$SRSRAN_INSTALL_DIR_DPDK/bin:$PATH"
    
    # Debug: List what's actually installed
    msg info "=== INSTALLATION DEBUG INFO ==="
    msg info "Available directories in /usr/local:"
    ls -la /usr/local/ || msg info "Cannot list /usr/local/"
    
    msg info "Checking for srsRAN base installation at: $SRSRAN_INSTALL_DIR_BASE"
    if [ -d "$SRSRAN_INSTALL_DIR_BASE" ]; then
        msg info "Base directory exists. Contents:"
        ls -la "$SRSRAN_INSTALL_DIR_BASE/" || msg info "Cannot list base directory"
        if [ -d "$SRSRAN_INSTALL_DIR_BASE/bin" ]; then
            msg info "Binaries in base installation:"
            ls -la "$SRSRAN_INSTALL_DIR_BASE/bin/" || msg info "Cannot list bin directory"
        else
            msg warning "No bin directory in base installation"
        fi
    else
        msg error "Base installation directory does not exist!"
    fi
    
    msg info "Checking for srsRAN DPDK installation at: $SRSRAN_INSTALL_DIR_DPDK"
    if [ -d "$SRSRAN_INSTALL_DIR_DPDK" ]; then
        msg info "DPDK directory exists. Contents:"
        ls -la "$SRSRAN_INSTALL_DIR_DPDK/" || msg info "Cannot list DPDK directory"
        if [ -d "$SRSRAN_INSTALL_DIR_DPDK/bin" ]; then
            msg info "Binaries in DPDK installation:"
            ls -la "$SRSRAN_INSTALL_DIR_DPDK/bin/" || msg info "Cannot list DPDK bin directory"
        else
            msg warning "No bin directory in DPDK installation"
        fi
    else
        msg warning "DPDK installation directory does not exist"
    fi
    
    # Verify base installation
    if [ -f "$SRSRAN_INSTALL_DIR_BASE/bin/gnb" ]; then
        local version_base=$(timeout 5 "$SRSRAN_INSTALL_DIR_BASE/bin/gnb" --version 2>/dev/null | head -1 || echo "Version check failed")
        msg info "✓ srsRAN base version installed successfully: $version_base"
    else
        msg error "✗ srsRAN base version not found after installation"
        msg error "Expected binary at: $SRSRAN_INSTALL_DIR_BASE/bin/gnb"
        exit 1
    fi
    
    # Verify DPDK installation if it exists
    if [ -f "$SRSRAN_INSTALL_DIR_DPDK/bin/gnb" ]; then
        local version_dpdk=$(timeout 5 "$SRSRAN_INSTALL_DIR_DPDK/bin/gnb" --version 2>/dev/null | head -1 || echo "Version check failed")
        msg info "✓ srsRAN DPDK version installed successfully: $version_dpdk"
    else
        msg info "ℹ srsRAN DPDK version not built (DPDK not available)"
    fi
    
    msg info "=== END INSTALLATION DEBUG INFO ==="

    msg info "Clean up build artifacts"
    msg info "Before cleanup - verifying installations are still present:"
    msg info "Checking $SRSRAN_INSTALL_DIR_BASE:"
    [ -d "$SRSRAN_INSTALL_DIR_BASE" ] && ls -la "$SRSRAN_INSTALL_DIR_BASE/" || msg warning "Base installation missing before cleanup!"
    if [ -d "$SRSRAN_INSTALL_DIR_DPDK" ]; then
        msg info "Checking $SRSRAN_INSTALL_DIR_DPDK:"
        ls -la "$SRSRAN_INSTALL_DIR_DPDK/" || msg warning "DPDK installation missing before cleanup!"
    fi
    
    # Only clean up temp and build directories, NOT installation directories
    msg info "Removing only temporary build directories: $TEMP_DIR and $BUILD_DIR"
    rm -rf "$TEMP_DIR" "$BUILD_DIR"
    
    msg info "After cleanup - verifying installations are still present:"
    msg info "Checking $SRSRAN_INSTALL_DIR_BASE:"
    [ -d "$SRSRAN_INSTALL_DIR_BASE" ] && ls -la "$SRSRAN_INSTALL_DIR_BASE/" || msg error "Base installation DELETED during cleanup!"
    if [ -d "$SRSRAN_INSTALL_DIR_DPDK" ]; then
        msg info "Checking $SRSRAN_INSTALL_DIR_DPDK:"
        ls -la "$SRSRAN_INSTALL_DIR_DPDK/" || msg error "DPDK installation DELETED during cleanup!"
    fi
    
    # Configure kernel parameters in GRUB during installation phase
    msg info "Configuring kernel parameters for optimal performance"
    
    # Configure hugepages parameters in GRUB
    make_hugepages_persistent
    
    # Disable AppArmor for optimal performance
    disable_apparmor_grub
    
    # Update GRUB configuration
    msg info "Updating GRUB configuration..."
    if update-grub; then
        msg info "✓ GRUB configuration updated successfully"
        msg info "Note: Reboot required for kernel parameters to take effect"
    else
        msg warning "Failed to update GRUB configuration"
    fi

    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    msg info "Configuring srsRAN Project"

    # Stop any running services
    systemctl stop srsran-gnb srsran-cu srsran-du || true

    # Select the appropriate installation directory based on DPDK setting
    if [[ "$ONEAPP_SRSRAN_ENABLE_DPDK" == "YES" ]]; then
        if [ -d "$SRSRAN_INSTALL_DIR_DPDK" ] && [ -f "$SRSRAN_INSTALL_DIR_DPDK/bin/gnb" ]; then
            SRSRAN_INSTALL_DIR="$SRSRAN_INSTALL_DIR_DPDK"
            msg info "Using srsRAN DPDK version: $SRSRAN_INSTALL_DIR"
            
            # Create DPDK indicator file
            touch "$SRSRAN_CONFIG_DIR/dpdk_enabled"
            msg info "✓ DPDK indicator file created at $SRSRAN_CONFIG_DIR/dpdk_enabled"
            
            # Configure DPDK drivers and system settings
            setup_dpdk_drivers_and_config
        else
            msg warning "DPDK version requested but not available, falling back to base version"
            SRSRAN_INSTALL_DIR="$SRSRAN_INSTALL_DIR_BASE"
            # Remove DPDK indicator file if it exists
            rm -f "$SRSRAN_CONFIG_DIR/dpdk_enabled"
        fi
    else
        SRSRAN_INSTALL_DIR="$SRSRAN_INSTALL_DIR_BASE"
        msg info "Using srsRAN base version: $SRSRAN_INSTALL_DIR"
        # Remove DPDK indicator file if it exists
        rm -f "$SRSRAN_CONFIG_DIR/dpdk_enabled"
    fi

    # Verify installation exists
    if [ ! -d "$SRSRAN_INSTALL_DIR" ]; then
        msg error "srsRAN installation directory not found: $SRSRAN_INSTALL_DIR"
        msg info "Available directories:"
        ls -la /usr/local/ | grep -E "(srsran|srs)" || msg info "No srsRAN directories found in /usr/local/"
        exit 1
    fi

    # Check for required binaries
    local missing_binaries=()
    [ ! -f "$SRSRAN_INSTALL_DIR/bin/gnb" ] && missing_binaries+=("gnb")
    [ ! -f "$SRSRAN_INSTALL_DIR/bin/srscu" ] && missing_binaries+=("srscu")
    [ ! -f "$SRSRAN_INSTALL_DIR/bin/srsdu" ] && missing_binaries+=("srsdu")
    
    if [ ${#missing_binaries[@]} -gt 0 ]; then
        msg error "srsRAN binaries not found: ${missing_binaries[*]}"
        msg info "Available binaries in $SRSRAN_INSTALL_DIR:"
        ls -la "$SRSRAN_INSTALL_DIR"/ || msg info "Directory is empty or not accessible"
        if [ -d "$SRSRAN_INSTALL_DIR/bin" ]; then
            ls -la "$SRSRAN_INSTALL_DIR/bin/" || msg info "bin directory is empty"
        fi
        exit 1
    fi

    # Services now run as root - no dedicated user needed
    # if ! id "srsran" &>/dev/null; then
    #     msg warning "srsran user does not exist, creating it now"
    #     # Ensure realtime group exists first
    #     if ! grep -q "^realtime:" /etc/group; then
    #         groupadd realtime
    #         msg info "Created realtime group"
    #     fi
    #     useradd -r -s /bin/false -d "$SRSRAN_DATA_DIR" srsran || true
    #     usermod -a -G realtime srsran
    #     msg info "Added srsran user to realtime group"
    # fi
    msg info "Services configured to run as root with full privileges"

    # Ensure directories exist and have correct ownership
    mkdir -p "$SRSRAN_CONFIG_DIR" "$SRSRAN_LOG_DIR" "$SRSRAN_DATA_DIR"
    chown -R root:root "$SRSRAN_DATA_DIR" "$SRSRAN_LOG_DIR"
    # Config directory owned by root for security
    chown root:root "$SRSRAN_CONFIG_DIR"
    chmod 755 "$SRSRAN_CONFIG_DIR"

    # Update systemd service files to use the correct installation directory
    msg info "Updating systemd service files to use $SRSRAN_INSTALL_DIR"
    update_systemd_services

    # Generate configuration files based on mode
    case "$ONEAPP_SRSRAN_MODE" in
        "gnb")
            configure_gnb
            ;;
        "cu")
            configure_cu
            ;;
        "du")
            configure_du
            ;;
        *)
            msg error "Invalid srsRAN mode: $ONEAPP_SRSRAN_MODE. Valid modes: gnb, cu, du"
            exit 1
            ;;
    esac

    # Create service report
    cat > "$ONE_SERVICE_REPORT" <<EOF
[srsRAN Project Configuration]
Mode: ${ONEAPP_SRSRAN_MODE}
Version: ${SRSRAN_VERSION}
MCC: ${ONEAPP_SRSRAN_MCC}
MNC: ${ONEAPP_SRSRAN_MNC}
TAC: ${ONEAPP_SRSRAN_TAC}
PCI: ${ONEAPP_SRSRAN_PCI}
DL ARFCN: ${ONEAPP_SRSRAN_DL_ARFCN}
Band: ${ONEAPP_SRSRAN_BAND}
Channel BW: ${ONEAPP_SRSRAN_CHANNEL_BW_MHZ} MHz
DPDK: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "Enabled" || echo "Disabled")
AMF IPv4: ${ONEAPP_SRSRAN_AMF_IPV4}
NIC PCI Address: ${ONEAPP_SRSRAN_NIC_PCI_ADDR}
RU MAC Address: ${ONEAPP_SRSRAN_RU_MAC}

[Configuration Files]
gNB Config: ${SRSRAN_CONFIG_DIR}/gnb.conf

[Log Files]
Log Directory: ${SRSRAN_LOG_DIR}

[Services]
gNB Service: srsran-gnb

[Management Commands]
Start gNB: systemctl start srsran-gnb
View logs: journalctl -u srsran-gnb -f
Check status: systemctl status srsran-gnb

[Available Binaries]
gnb: ${SRSRAN_INSTALL_DIR}/bin/gnb
srscu: ${SRSRAN_INSTALL_DIR}/bin/srscu
srsdu: ${SRSRAN_INSTALL_DIR}/bin/srsdu

[Installation Details]
Active Version: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "DPDK-enabled" || echo "Base")
Base Installation: ${SRSRAN_INSTALL_DIR_BASE}
DPDK Installation: $([ -d "$SRSRAN_INSTALL_DIR_DPDK" ] && echo "$SRSRAN_INSTALL_DIR_DPDK" || echo "Not available")

[DPDK Configuration]
DPDK Version: 23.11
Hugepages: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "2GB (1G pages)" || echo "Not configured")
Hugepages Mount: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "/mnt/huge" || echo "Not mounted")
igb_uio Driver: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "Installed" || echo "Not installed")
DPDK Drivers: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "igb_uio, uio_pci_generic" || echo "Not configured")

[DPDK Management Commands]
Check Hugepages: cat /proc/meminfo | grep -i huge
Check Hugepages Status: ls -la /sys/kernel/mm/hugepages/
Mount Hugepages: mount -t hugetlbfs nodev /mnt/huge
Check DPDK Devices: dpdk-devbind.py --status
Bind Device to DPDK: dpdk-devbind.py --bind=igb_uio <PCI_ADDRESS>
Check igb_uio Driver: lsmod | grep igb_uio
Reload igb_uio: rmmod igb_uio && modprobe igb_uio

[VM Clock Synchronization]
PHC2SYS Service: phc2sys.service
LinuxPTP Version: 4.3
Source Clock: /dev/ptp1 (passed-through NIC hardware clock)
Target Clock: CLOCK_REALTIME (VM system clock)
Synchronization: Enabled

[PHC2SYS Management Commands]
Start PHC2SYS: systemctl start phc2sys.service
Stop PHC2SYS: systemctl stop phc2sys.service
Check Status: systemctl status phc2sys.service
View Logs: journalctl -u phc2sys.service -f
Monitor Sync: journalctl -u phc2sys.service | grep "sys offset"

[Intel iavf Driver]
Driver Version: 4.13.3
PTP Support: Enabled
Installation: Built from source
Module Status: Loaded automatically on boot

[iavf Driver Management Commands]
Check Driver Status: modinfo iavf
Reload Driver: rmmod iavf && modprobe iavf
Check PTP Devices: ls -la /dev/ptp*
Check Interface Capabilities: ethtool -T <interface>

[Split 7.2 Configuration]
This appliance is configured for Split 7.2 deployments with export capabilities.

[Performance Optimizations]
DRM KMS Polling: Disabled for reduced latency
Network Buffers: Optimized
RT Priorities: Elevated for kernel threads (ksoftirqd, kworker)
Tuna Package: Installed for RT thread management

[Performance Optimization Commands]
Check DRM Status: cat /sys/module/drm_kms_helper/parameters/poll
Check Network Buffers: sysctl net.core.rmem_max net.core.wmem_max
Check RT Priorities: tuna -P
Reload Optimizations: Restart VM or run service_configure
EOF

    chmod 600 "$ONE_SERVICE_REPORT"

    msg info "Enable services based on mode"
    case "$ONEAPP_SRSRAN_MODE" in
        "gnb")
            systemctl enable srsran-gnb
            ;;
        "cu")
            systemctl enable srsran-cu
            ;;
        "du")
            systemctl enable srsran-du
            ;;
    esac

    msg info "Configure PHC2SYS service for VM clock synchronization"
    configure_phc2sys_service

    msg info "Apply performance optimizations"
    disable_drm_kms_polling
    apply_network_optimizations
    elevate_rt_priorities

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "Starting srsRAN Project services"
    
    # Start PHC2SYS service for VM clock synchronization
    msg info "Starting PHC2SYS service for VM clock synchronization"
    if systemctl start phc2sys.service; then
        msg info "✓ PHC2SYS service started successfully"
    else
        msg warning "Failed to start PHC2SYS service - check logs with: journalctl -u phc2sys.service"
    fi
    
    case "$ONEAPP_SRSRAN_MODE" in
        "gnb")
            systemctl start srsran-gnb
            ;;
        "cu")
            systemctl start srsran-cu
            ;;
        "du")
            systemctl start srsran-du
            ;;
    esac
    
    msg info "BOOTSTRAP FINISHED"
}

service_help()
{
    msg info "srsRAN Project Appliance Help"
    msg info "============================="
    msg info ""
    msg info "This appliance provides srsRAN Project - a complete 5G software radio suite"
    msg info "with Split 7.2 support for disaggregated deployments."
    msg info ""
    msg info "Available modes:"
    msg info "  - gnb: gNodeB (CU+DU combined)"
    msg info "  - cu: Central Unit (CU-CP + CU-UP combined)"
    msg info "  - du: Distributed Unit"
    msg info ""
    msg info "Key configuration parameters:"
    msg info "  - ONEAPP_SRSRAN_MODE: Deployment mode (gnb, cu, du)"
    msg info "  - ONEAPP_SRSRAN_MCC/MNC: Network identity"
    msg info "  - ONEAPP_SRSRAN_BAND: NR Band (e.g., n3, n78)"
    msg info "  - ONEAPP_SRSRAN_DL_ARFCN: Downlink ARFCN"
    msg info "  - ONEAPP_SRSRAN_ENABLE_DPDK: Enable DPDK for high performance"
    msg info ""
    msg info "Management commands:"
    msg info "  - systemctl status srsran-gnb"
    msg info "  - journalctl -u srsran-gnb -f"
    msg info "  - gnb --help"
    msg info ""
    msg info "Configuration:"
    msg info "  - Config files: /etc/srsran/"
    msg info "  - Logs: /var/log/srsran/"
    msg info "  - Version: $SRSRAN_VERSION"
    msg info ""
    return 0
}

service_cleanup()
{
    # Empty function - do not clean up anything
    # This ensures installations persist after build process
    msg info "service_cleanup called - no cleanup performed to preserve installations"
}

############################################## Auxiliary Functions ##############################################

###############################################################################
# Real-time Kernel Installation Functions
###############################################################################

# NOTE: RT kernel installation is now handled by separate Packer script (install_rt_kernel.sh)
# The RT kernel is installed during the appliance build process, not at runtime

# NOTE: GRUB configuration and real-time system setup are now handled by
# the separate Packer script (install_rt_kernel.sh) during appliance build

###############################################################################
# DPDK Installation Functions
###############################################################################

install_dpdk_from_source()
{
    local dpdk_version="23.11"
    local dpdk_dir="/tmp/dpdk-install"
    
    msg info "Installing DPDK $dpdk_version from source"
    
    # Install DPDK build dependencies
    if ! apt-get install -y build-essential tar wget python3-pip libnuma-dev meson ninja-build python3-pyelftools; then
        msg warning "Failed to install DPDK build dependencies, will build only non-DPDK version"
        return 1
    fi
    
    # Create temporary directory for DPDK installation
    rm -rf "$dpdk_dir"
    mkdir -p "$dpdk_dir"
    cd "$dpdk_dir"
    
    # Download and extract DPDK
    msg info "Downloading DPDK $dpdk_version"
    if ! wget "https://fast.dpdk.org/rel/dpdk-${dpdk_version}.tar.xz"; then
        msg warning "Failed to download DPDK, will build only non-DPDK version"
        return 1
    fi
    
    msg info "Extracting DPDK archive"
    tar xf "dpdk-${dpdk_version}.tar.xz"
    cd "dpdk-${dpdk_version}"
    
    # Build and install DPDK
    msg info "Building DPDK $dpdk_version"
    meson setup build
    cd build
    ninja
    
    msg info "Installing DPDK $dpdk_version"
    meson install
    ldconfig
    
    msg info "✓ DPDK $dpdk_version installed successfully"
    
    # Cleanup
    cd /
    rm -rf "$dpdk_dir"
    
    return 0
}

install_igb_uio_driver()
{
    local dpdk_kmods_dir="/tmp/dpdk-kmods"
    
    msg info "Installing igb_uio driver from dpdk-kmods repository"
    
    # Install git if not already installed
    if ! command -v git >/dev/null 2>&1; then
        msg info "Installing git for dpdk-kmods download"
        apt-get install -y git
    fi
    
    # Create temporary directory for dpdk-kmods
    rm -rf "$dpdk_kmods_dir"
    mkdir -p "$dpdk_kmods_dir"
    cd "$dpdk_kmods_dir"
    
    # Clone dpdk-kmods repository
    msg info "Downloading dpdk-kmods from http://dpdk.org/git/dpdk-kmods"
    if ! git clone http://dpdk.org/git/dpdk-kmods; then
        msg warning "Failed to clone dpdk-kmods repository, igb_uio driver will not be available"
        return 1
    fi
    
    cd dpdk-kmods/linux/igb_uio
    
    # Build igb_uio driver
    msg info "Building igb_uio driver"
    if ! make; then
        msg warning "Failed to build igb_uio driver"
        return 1
    fi
    
    # Ensure uio module is loaded
    msg info "Loading uio module"
    modprobe uio || true
    
    # Install igb_uio driver permanently
    msg info "Installing igb_uio driver permanently"
    if [ -f "igb_uio.ko" ]; then
        # Create kernel modules directory if it doesn't exist
        local kernel_version=$(uname -r)
        local modules_dir="/lib/modules/$kernel_version/extra"
        mkdir -p "$modules_dir"
        
        # Copy module to permanent location
        cp igb_uio.ko "$modules_dir/"
        
        # Update module dependencies
        depmod -a
        
        # Load igb_uio driver
        msg info "Loading igb_uio driver"
        if modprobe igb_uio; then
            msg info "✓ igb_uio driver loaded successfully"
        else
            msg warning "Failed to load igb_uio driver, but module is installed"
        fi
        
        # Add to modules load at boot (avoid duplicates)
        if ! grep -q "^uio$" /etc/modules 2>/dev/null; then
            echo "uio" >> /etc/modules
        fi
        if ! grep -q "^igb_uio$" /etc/modules 2>/dev/null; then
            echo "igb_uio" >> /etc/modules
        fi
        
        msg info "✓ igb_uio driver installed permanently"
    else
        msg warning "igb_uio.ko not found after build"
        return 1
    fi
    
    # Cleanup
    cd /
    rm -rf "$dpdk_kmods_dir"
    
    return 0
}

# Function to get interface name from PCI address
get_interface_name_from_pci() {
    local pci_addr="$1"
    local net_path="/sys/bus/pci/devices/$pci_addr/net"
    
    # Method 1: Check /sys/bus/pci/devices/PCI_ADDR/net/ directory
    if [ -d "$net_path" ]; then
        local iface_name=$(ls "$net_path" 2>/dev/null | head -1)
        if [ -n "$iface_name" ]; then
            echo "$iface_name"
            return 0
        fi
    fi
    
    # Method 2: Search through all network interfaces
    for iface in $(ls /sys/class/net/ 2>/dev/null); do
        if [ -f "/sys/class/net/$iface/device/uevent" ]; then
            local iface_pci=$(basename $(readlink "/sys/class/net/$iface/device") 2>/dev/null)
            if [ "$iface_pci" = "$pci_addr" ]; then
                echo "$iface"
                return 0
            fi
        fi
    done
    
    # Method 3: Use ethtool to find interface by PCI address
    if command -v ethtool >/dev/null 2>&1; then
        for iface in $(ls /sys/class/net/ 2>/dev/null); do
            local bus_info=$(ethtool -i "$iface" 2>/dev/null | grep "bus-info:" | awk '{print $2}')
            if [ "$bus_info" = "$pci_addr" ]; then
                echo "$iface"
                return 0
            fi
        done
    fi
    
    # Fallback: return eth2 as default
    echo "eth2"
    return 1
}

configure_dpdk_hugepages()
{
    msg info "Configuring DPDK hugepages (runtime configuration only)"
    
    # Check if dpdk-hugepages.py is available
    local dpdk_hugepages_script=""
    local dpdk_hugepages_paths=(
        "/usr/local/bin/dpdk-hugepages.py"
        "/usr/bin/dpdk-hugepages.py"
        "/opt/dpdk/bin/dpdk-hugepages.py"
        "/usr/local/share/dpdk/usertools/dpdk-hugepages.py"
    )
    
    for path in "${dpdk_hugepages_paths[@]}"; do
        if [ -f "$path" ]; then
            dpdk_hugepages_script="$path"
            msg info "Found dpdk-hugepages.py at: $path"
            break
        fi
    done
    
    if [ -z "$dpdk_hugepages_script" ]; then
        msg warning "dpdk-hugepages.py not found, configuring hugepages manually"
        configure_hugepages_manual
        return $?
    fi
    
    # Configure hugepages using dpdk-hugepages.py
    # Recommended: 2GB of 1G hugepages for single sector 4x2 100MHz
    msg info "Configuring 2GB of 1G hugepages for DPDK"
    
    if python3 "$dpdk_hugepages_script" -p 1G --setup 2G; then
        msg info "✓ Hugepages configured successfully using dpdk-hugepages.py"
    else
        msg warning "Failed to configure hugepages with dpdk-hugepages.py, trying manual configuration"
        configure_hugepages_manual
        return $?
    fi
    
    # Note: GRUB configuration and persistent hugepages are now handled during installation
    # Only verify hugepages configuration here
    verify_hugepages_config
    
    return 0
}

configure_hugepages_manual()
{
    msg info "Configuring hugepages manually"
    
    # Configure 2 hugepages of 1GB each (total 2GB)
    local hugepages_1g=2
    
    # Set hugepages for 1GB pages
    msg info "Setting up $hugepages_1g hugepages of 1GB each"
    
    # Enable 1GB hugepages
    echo $hugepages_1g > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages
    
    # Verify the configuration
    local configured_1g=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo "0")
    
    if [ "$configured_1g" -eq "$hugepages_1g" ]; then
        msg info "✓ Successfully configured $configured_1g hugepages of 1GB"
    else
        msg warning "Hugepages configuration may have failed. Requested: $hugepages_1g, Configured: $configured_1g"
        return 1
    fi
    
    return 0
}

make_hugepages_persistent()
{
    msg info "Making hugepages configuration persistent across reboots (called during installation)"
    
    # Create hugepages mount point
    mkdir -p /mnt/huge
    
    # Add hugepages mount to /etc/fstab if not already present
    if ! grep -q "/mnt/huge" /etc/fstab; then
        echo "nodev /mnt/huge hugetlbfs defaults 0 0" >> /etc/fstab
        msg info "✓ Added hugepages mount to /etc/fstab"
    else
        msg info "✓ Hugepages mount already configured in /etc/fstab"
    fi
    
    # Mount hugepages if not already mounted
    if ! mountpoint -q /mnt/huge; then
        if mount /mnt/huge; then
            msg info "✓ Hugepages mounted at /mnt/huge"
        else
            msg warning "Failed to mount hugepages at /mnt/huge"
        fi
    else
        msg info "✓ Hugepages already mounted at /mnt/huge"
    fi
    
    # Add hugepages configuration to kernel parameters for persistence
    local grub_file="/etc/default/grub"
    local hugepages_param="hugepagesz=1G hugepages=2 default_hugepagesz=1G"
    
    if [ -f "$grub_file" ]; then
        # Check if hugepages parameters are already configured
        if ! grep -q "hugepages" "$grub_file"; then
            # Add hugepages parameters to GRUB_CMDLINE_LINUX_DEFAULT
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $hugepages_param\"/" "$grub_file"
            msg info "✓ Added hugepages parameters to GRUB configuration"
            msg info "Note: Run 'update-grub' and reboot to make kernel parameters persistent"
        else
            msg info "✓ Hugepages parameters already configured in GRUB"
        fi
    else
        msg warning "GRUB configuration file not found at $grub_file"
    fi
}

disable_apparmor_grub()
{
    msg info "Disabling AppArmor in GRUB configuration for optimal performance (called during installation)"
    
    local grub_file="/etc/default/grub"
    local apparmor_param="apparmor=0"
    
    if [ -f "$grub_file" ]; then
        # Check if apparmor=0 parameter is already configured
        if ! grep -q "apparmor=0" "$grub_file"; then
            # Add apparmor=0 parameter to GRUB_CMDLINE_LINUX_DEFAULT
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $apparmor_param\"/" "$grub_file"
            msg info "✓ Added apparmor=0 parameter to GRUB configuration"
            msg info "Note: Run 'update-grub' and reboot to disable AppArmor completely"
        else
            msg info "✓ AppArmor already disabled in GRUB configuration"
        fi
    else
        msg warning "GRUB configuration file not found at $grub_file"
    fi
}

verify_hugepages_config()
{
    msg info "Verifying hugepages configuration"
    
    # Check 1GB hugepages
    local hugepages_1g_total=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo "0")
    local hugepages_1g_free=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo "0")
    
    msg info "Hugepages Status:"
    msg info "  1GB hugepages - Total: $hugepages_1g_total, Free: $hugepages_1g_free"
    
    # Check total hugepages memory
    local total_hugepages_mb=$((hugepages_1g_total * 1024))
    msg info "  Total hugepages memory: ${total_hugepages_mb}MB"
    
    # Check if hugepages mount exists
    if mountpoint -q /mnt/huge; then
        msg info "  ✓ Hugepages mounted at /mnt/huge"
    else
        msg warning "  ✗ Hugepages not mounted at /mnt/huge"
    fi
    
    # Verify minimum requirements (at least 1GB)
    if [ "$total_hugepages_mb" -ge 1024 ]; then
        msg info "✓ Hugepages configuration meets minimum requirements for DPDK"
        return 0
    else
        msg warning "✗ Hugepages configuration below minimum requirements (need at least 1GB)"
        return 1
    fi
}

setup_dpdk_drivers_and_config()
{
    msg info "Configuring DPDK drivers and system settings"
    
    # Verify that the system is completely initialized before continuing
    wait_for_system_ready
    
    # Configure hugepages first (required for DPDK)
    configure_dpdk_hugepages
    
    # Use the PCI address from context variable
    local pci_device="$ONEAPP_SRSRAN_NIC_PCI_ADDR"
    local interface_name=$(get_interface_name_from_pci "$pci_device")
    
    msg info "Target PCI Device: $pci_device"
    msg info "Detected interface name: $interface_name"
    
    # Verify that DPDK drivers are ready
    wait_for_dpdk_ready "$pci_device"
    
    # Check if dpdk-devbind.py is available
    if ! command -v dpdk-devbind.py >/dev/null 2>&1; then
        msg warning "dpdk-devbind.py not found in PATH, DPDK configuration may fail"
        msg info "Checking common DPDK installation paths..."
        
        # Try to find dpdk-devbind.py in common locations
        local dpdk_devbind_paths=(
            "/usr/local/bin/dpdk-devbind.py"
            "/usr/bin/dpdk-devbind.py"
            "/opt/dpdk/bin/dpdk-devbind.py"
        )
        
        for path in "${dpdk_devbind_paths[@]}"; do
            if [ -f "$path" ]; then
                msg info "Found dpdk-devbind.py at: $path"
                export PATH="$(dirname "$path"):$PATH"
                break
            fi
        done
        
        if ! command -v dpdk-devbind.py >/dev/null 2>&1; then
            msg error "dpdk-devbind.py still not found, cannot configure DPDK drivers"
            return 1
        fi
    fi
    
    # Check if PCI device exists
    msg info "Checking PCI device $pci_device..."
    if ! lspci -s "$pci_device" >/dev/null 2>&1; then
        msg error "PCI device $pci_device not found"
        msg info "Available network devices:"
        lspci | grep -i ethernet || msg warning "No ethernet devices found"
        return 1
    fi
    
    local device_info=$(lspci -s "$pci_device")
    msg info "✓ PCI device $pci_device found: $device_info"
    
    # Get current driver for PCI device
    get_current_driver() {
        local pci_dev="$1"
        local driver_path="/sys/bus/pci/devices/$pci_dev/driver"
        
        if [ -L "$driver_path" ]; then
            basename "$(readlink "$driver_path")"
        else
            echo "none"
        fi
    }
    
    local current_driver=$(get_current_driver "$pci_device")
    msg info "Current driver for $pci_device: $current_driver"
    
    # Configure network interface if available
    configure_network_interface() {
        local iface="$1"
        msg info "Configuring network interface $iface..."
        
        # Check if interface is available
        if ! ip link show "$iface" >/dev/null 2>&1; then
            msg warning "Network interface $iface not available (may be bound to DPDK driver)"
            return 1
        fi
        
        local config_count=0
        
        # Enable promiscuous mode
        msg info "Enabling promiscuous mode on $iface..."
        if ip link set "$iface" promisc on; then
            msg info "✓ Promiscuous mode enabled"
            config_count=$((config_count + 1))
        else
            msg warning "Failed to enable promiscuous mode"
        fi
        
        # Enable allmulticast mode
        msg info "Enabling allmulticast mode on $iface..."
        if ip link set "$iface" allmulticast on; then
            msg info "✓ Allmulticast mode enabled"
            config_count=$((config_count + 1))
        else
            msg warning "Failed to enable allmulticast mode"
        fi
        
        # Configure ring buffer sizes if ethtool is available
        if command -v ethtool >/dev/null 2>&1; then
            msg info "Configuring ring buffer sizes (TX: 4096, RX: 4096)..."
            if ethtool -G "$iface" tx 4096 rx 4096 2>/dev/null; then
                msg info "✓ Ring buffer sizes configured"
                config_count=$((config_count + 1))
            else
                msg warning "Failed to configure ring buffer sizes (may not be supported)"
            fi
        else
            msg warning "ethtool not available, skipping ring buffer configuration"
        fi
        
        if [ "$config_count" -ge 2 ]; then
            msg info "✓ Network interface configuration completed ($config_count configurations successful)"
            return 0
        else
            msg warning "Some network interface configurations failed"
            return 1
        fi
    }
    
    # Step 1: Load iavf driver
    msg info "Loading iavf driver for PCI device $pci_device..."
    # Add delay before attempting binding to avoid system locks
    msg info "Waiting 5 seconds before attempting iavf driver binding..."
    sleep 5
    
    if dpdk-devbind.py --bind iavf "$pci_device" 2>/dev/null; then
        # Increase wait time to ensure driver loads completely
        msg info "Waiting 4 seconds for iavf driver to load completely..."
        sleep 4 
        local new_driver=$(get_current_driver "$pci_device")
        if [ "$new_driver" = "iavf" ]; then
            msg info "✓ iavf driver successfully loaded for $pci_device"
        else
            msg warning "iavf driver binding may have failed (current: $new_driver)"
        fi
    else
        msg warning "Failed to bind iavf driver to $pci_device"
    fi
    
    # Step 2: Configure network interface (if available)
    configure_network_interface "$interface_name" || msg warning "Network interface configuration failed"
    
    # Step 3: Load igb_uio driver
    msg info "Loading igb_uio driver for PCI device $pci_device..."
    
    # Function to ensure igb_uio is available
    ensure_igb_uio_available() {
        # Check if igb_uio module is loaded
        if lsmod | grep -q igb_uio; then
            msg info "✓ igb_uio module already loaded"
            return 0
        fi
        
        # Try to load igb_uio module
        msg info "Attempting to load igb_uio module..."
        if modprobe igb_uio 2>/dev/null; then
            msg info "✓ igb_uio module loaded successfully"
            return 0
        fi
        
        # Check if module file exists
        local kernel_version=$(uname -r)
        local module_path="/lib/modules/$kernel_version/extra/igb_uio.ko"
        
        if [ ! -f "$module_path" ]; then
            msg warning "igb_uio module not found at $module_path, reinstalling..."
            # Reinstall igb_uio driver
            if install_igb_uio_driver; then
                msg info "igb_uio driver reinstalled, attempting to load..."
                if modprobe igb_uio 2>/dev/null; then
                    msg info "✓ igb_uio module loaded after reinstallation"
                    return 0
                fi
            fi
        fi
        
        msg warning "Failed to load igb_uio module"
        return 1
    }
    
    # Ensure uio module is loaded first
    modprobe uio 2>/dev/null || true
    
    # Ensure igb_uio is available
    ensure_igb_uio_available
    
    if dpdk-devbind.py --bind=igb_uio "$pci_device" 2>/dev/null; then
        sleep 2
        local new_driver=$(get_current_driver "$pci_device")
        if [ "$new_driver" = "igb_uio" ]; then
            msg info "✓ igb_uio driver successfully loaded for $pci_device"
        else
            msg warning "igb_uio driver binding may have failed (current: $new_driver)"
        fi
    else
        msg warning "Failed to bind igb_uio driver to $pci_device"
    fi
    
    # Step 4: Check uio_pci_generic status
    msg info "Checking uio_pci_generic driver status..."
    local final_driver=$(get_current_driver "$pci_device")
    if [ "$final_driver" = "uio_pci_generic" ]; then
        msg info "✓ uio_pci_generic driver is loaded for $pci_device"
    else
        msg info "uio_pci_generic driver is not loaded (current: $final_driver)"
        if modinfo uio_pci_generic >/dev/null 2>&1; then
            msg info "uio_pci_generic module is available in the system"
            msg info "To bind uio_pci_generic driver manually, use:"
            msg info "  dpdk-devbind.py --bind=uio_pci_generic $pci_device"
        fi
    fi
    
    # Display final status
    msg info "========================================================================="
    msg info "                    DPDK CONFIGURATION STATUS"
    msg info "========================================================================="
    msg info "PCI Device: $pci_device"
    msg info "Current Driver: $(get_current_driver "$pci_device")"
    
    if ip link show "$interface_name" >/dev/null 2>&1; then
        msg info "Network Interface: $interface_name (Available)"
        local flags=$(ip link show "$interface_name" | grep -o 'flags=<[^>]*>' | sed 's/flags=<\|>//g')
        msg info "Interface Flags: $flags"
    else
        msg info "Network Interface: $interface_name (Not available - may be bound to DPDK)"
    fi
    
    msg info "Loaded DPDK-related Modules:"
    lsmod | grep -E "(igb_uio|uio_pci_generic|vfio)" || msg info "  No DPDK-related modules loaded"
    
    # Additional igb_uio diagnostics
    msg info "igb_uio Module Diagnostics:"
    local kernel_version=$(uname -r)
    local module_path="/lib/modules/$kernel_version/extra/igb_uio.ko"
    
    if [ -f "$module_path" ]; then
        msg info "  ✓ igb_uio.ko found at: $module_path"
        local module_info=$(modinfo "$module_path" 2>/dev/null | grep -E "(filename|version|description)" | head -3 || echo "Module info not available")
        msg info "  Module details: $module_info"
    else
        msg warning "  ✗ igb_uio.ko not found at: $module_path"
    fi
    
    if grep -q "^igb_uio$" /etc/modules 2>/dev/null; then
        msg info "  ✓ igb_uio configured to load at boot"
    else
        msg warning "  ✗ igb_uio not configured to load at boot"
    fi
    
    # Check if depmod was run
    if [ -f "/lib/modules/$kernel_version/modules.dep" ]; then
        if grep -q "igb_uio" "/lib/modules/$kernel_version/modules.dep" 2>/dev/null; then
            msg info "  ✓ igb_uio found in module dependencies"
        else
            msg warning "  ✗ igb_uio not found in module dependencies (run 'depmod -a')"
        fi
    fi
    
    msg info "=========================================================================="
    
    # Verify configuration
    local final_driver=$(get_current_driver "$pci_device")
    if [[ "$final_driver" =~ ^(iavf|igb_uio|uio_pci_generic|vfio-pci)$ ]]; then
        msg info "✓ DPDK-compatible driver verification passed: $final_driver"
        return 0
    else
        msg warning "DPDK-compatible driver verification failed: $final_driver"
        return 1
    fi
}

install_linuxptp_from_source()
{
    local linuxptp_version="4.3"
    local linuxptp_dir="/tmp/linuxptp-install"
    
    msg info "Installing LinuxPTP $linuxptp_version from source"
    
    # Install LinuxPTP build dependencies
    if ! apt-get install -y build-essential git; then
        msg error "Failed to install LinuxPTP build dependencies"
        exit 1
    fi
    
    # Create temporary directory for LinuxPTP installation
    rm -rf "$linuxptp_dir"
    mkdir -p "$linuxptp_dir"
    cd "$linuxptp_dir"
    
    # Clone LinuxPTP repository and checkout version 4.3
    msg info "Downloading LinuxPTP $linuxptp_version from GitHub"
    if ! git clone https://github.com/richardcochran/linuxptp.git; then
        msg error "Failed to clone LinuxPTP repository"
        exit 1
    fi
    
    cd linuxptp
    
    # Checkout specific version
    msg info "Checking out LinuxPTP version $linuxptp_version"
    if ! git checkout "v$linuxptp_version"; then
        msg error "Failed to checkout LinuxPTP version $linuxptp_version"
        exit 1
    fi
    
    # Build LinuxPTP
    msg info "Building LinuxPTP $linuxptp_version"
    if ! make; then
        msg error "Failed to build LinuxPTP"
        exit 1
    fi
    
    # Install LinuxPTP binaries to /usr/local/sbin
    msg info "Installing LinuxPTP $linuxptp_version"
    if ! make install; then
        msg error "Failed to install LinuxPTP"
        exit 1
    fi
    
    # Verify installation
    if [ -f "/usr/local/sbin/phc2sys" ]; then
        msg info "✓ LinuxPTP $linuxptp_version installed successfully"
        msg info "✓ phc2sys binary available at /usr/local/sbin/phc2sys"
    else
        msg error "LinuxPTP installation verification failed"
        exit 1
    fi
    
    # Cleanup
    cd /
    rm -rf "$linuxptp_dir"
    
    return 0
}

install_iavf_driver_from_source()
{
    local iavf_version="4.13.3"
    local iavf_dir="/tmp/iavf-install"
    local kernel_version=$(uname -r)
    
    msg info "Installing Intel iavf driver v$iavf_version from source"
    
    # Install iavf build dependencies
    if ! apt-get install -y build-essential linux-headers-$kernel_version dkms; then
        msg error "Failed to install iavf build dependencies"
        exit 1
    fi
    
    # Create temporary directory for iavf installation
    rm -rf "$iavf_dir"
    mkdir -p "$iavf_dir"
    cd "$iavf_dir"
    
    # Download iavf driver from GitHub releases
    msg info "Downloading iavf driver v$iavf_version from GitHub"
    if ! wget "https://github.com/intel/ethernet-linux-iavf/releases/download/v$iavf_version/iavf-$iavf_version.tar.gz"; then
        msg error "Failed to download iavf driver archive"
        exit 1
    fi
    
    # Extract the archive
    msg info "Extracting iavf driver archive"
    if ! tar -xzf "iavf-$iavf_version.tar.gz"; then
        msg error "Failed to extract iavf driver archive"
        exit 1
    fi
    
    cd "iavf-$iavf_version/src"
    
    # Remove any existing iavf module
    msg info "Removing existing iavf module if present"
    rmmod iavf 2>/dev/null || true
    
    # Build the driver
    msg info "Building iavf driver v$iavf_version"
    if ! make install; then
        msg error "Failed to build and install iavf driver"
        exit 1
    fi
    
    # Load the new driver
    msg info "Loading iavf driver v$iavf_version"
    if ! modprobe iavf; then
        msg error "Failed to load iavf driver"
        exit 1
    fi
    
    # Verify installation
    local installed_version=$(modinfo iavf | grep "^version:" | awk '{print $2}' || echo "unknown")
    if [ "$installed_version" = "$iavf_version" ]; then
        msg info "✓ Intel iavf driver v$iavf_version installed successfully"
        msg info "✓ Driver version: $installed_version"
    else
        msg warning "iavf driver installed but version mismatch. Expected: $iavf_version, Got: $installed_version"
    fi
    
    # Ensure driver loads on boot
    echo "iavf" >> /etc/modules
    
    # Cleanup
    cd /
    rm -rf "$iavf_dir"
    
    return 0
}

check_dpdk_available()
{
    # Check if DPDK is available by looking for dpdk library
    if ldconfig -p | grep -q libdpdk || pkg-config --exists libdpdk; then
        return 0
    else
        return 1
    fi
}



###############################################################################
# Build Environment Management Functions
###############################################################################

setup_build_environment()
{
    msg info "Setting up optimized build environment"
    
    # Create temporary swap file to prevent OOM during compilation
    local swap_file="/tmp/build_swap"
    local swap_size="4G"
    
    if [ ! -f "$swap_file" ]; then
        msg info "Creating temporary swap file ($swap_size) for compilation"
        
        # Create swap file
        if fallocate -l "$swap_size" "$swap_file" 2>/dev/null || dd if=/dev/zero of="$swap_file" bs=1M count=4096 2>/dev/null; then
            chmod 600 "$swap_file"
            mkswap "$swap_file" >/dev/null 2>&1
            
            if swapon "$swap_file" 2>/dev/null; then
                msg info "✓ Temporary swap file activated: $swap_size"
                echo "$swap_file" > /tmp/active_swap_file
            else
                msg warning "Failed to activate swap file, continuing without extra swap"
                rm -f "$swap_file"
            fi
        else
            msg warning "Failed to create swap file, continuing without extra swap"
        fi
    fi
    
    # Set compiler memory optimization flags
    export CXXFLAGS="${CXXFLAGS:-} -O2 -g0"  # Reduce debug info to save memory
    export CFLAGS="${CFLAGS:-} -O2 -g0"
    
    # Set make flags for memory optimization
    export MAKEFLAGS="${MAKEFLAGS:-} --no-print-directory"
    
    msg info "✓ Build environment optimized for memory usage"
}

cleanup_build_environment()
{
    msg info "Cleaning up build environment"
    
    # Remove temporary swap file if it exists
    if [ -f /tmp/active_swap_file ]; then
        local swap_file=$(cat /tmp/active_swap_file)
        if [ -f "$swap_file" ]; then
            swapoff "$swap_file" 2>/dev/null || true
            rm -f "$swap_file"
            rm -f /tmp/active_swap_file
            msg info "✓ Temporary swap file removed"
        fi
    fi
    
    # Reset environment variables
    unset CXXFLAGS CFLAGS MAKEFLAGS
    
    msg info "✓ Build environment cleaned up"
}

###############################################################################
# srsRAN Build Functions
###############################################################################

build_srsran_version()
{
    local build_type="$1"
    local install_dir="$2"
    local enable_dpdk="$3"
    
    msg info "Building srsRAN Project ($build_type version) with Split 7.2 configuration"
    
    # Setup temporary swap to prevent OOM during compilation
    setup_build_environment
    
    # Create separate build directory for this version
    local build_subdir="$BUILD_DIR/${build_type}"
    rm -rf "$build_subdir"
    mkdir -p "$build_subdir"
    cd "$build_subdir"
    
    # Copy source code
    cp -r "$TEMP_DIR"/srsRAN_Project*/* .
    
    mkdir -p build
    cd build

    # Configure cmake for Split 7.2 only (no Split 8/RF drivers needed)
    local cmake_flags=()
    cmake_flags+=("-DENABLE_EXPORT=ON")  # Enable Split 7.2
    cmake_flags+=("-DDU_SPLIT_TYPE=SPLIT_7_2")  # Force Split 7.2 only
    cmake_flags+=("-DCMAKE_BUILD_TYPE=Release")  # Optimize for release
    
    if [[ "$enable_dpdk" == "yes" ]]; then
        msg info "Enabling DPDK support for $build_type build"
        cmake_flags+=("-DENABLE_DPDK=True" "-DASSERT_LEVEL=MINIMAL")
        # Disable some memory-intensive features for DPDK build
        cmake_flags+=("-DBUILD_TESTS=OFF")  # Skip tests for DPDK to save memory
    fi

    msg info "Configuring $build_type build with cmake (Split 7.2 only)"
    msg info "CMAKE_INSTALL_PREFIX will be set to: $install_dir"
    if ! cmake ../ "${cmake_flags[@]}" -DCMAKE_INSTALL_PREFIX="$install_dir"; then
        msg error "CMake configuration failed for $build_type build"
        msg info "CMake configuration details:"
        cmake ../ "${cmake_flags[@]}" -DCMAKE_INSTALL_PREFIX="$install_dir" || true
        cleanup_build_environment
        return 1
    fi
    
    # Verify cmake configuration
    msg info "Verifying CMake configuration..."
    if ! cmake -LA -N . | grep CMAKE_INSTALL_PREFIX; then
        msg warning "Could not verify CMAKE_INSTALL_PREFIX from cmake"
    else
        cmake -LA -N . | grep CMAKE_INSTALL_PREFIX | msg info "CMAKE config:"
    fi

    msg info "Building srsRAN Project ($build_type version)"
    local cpu_count=$(nproc)
    
    msg info "Building with $cpu_count parallel jobs (full CPU utilization)"
    
    # Build with full parallelization
    if ! make -j"$cpu_count"; then
        msg error "Build failed for $build_type version"
        cleanup_build_environment
        return 1
    fi
    
    # Only run tests for base version to save time and memory
    if [[ "$enable_dpdk" != "yes" ]]; then
        msg info "Running tests for $build_type build"
        make test -j1 || msg warning "Some tests failed for $build_type build, continuing with installation"
    else
        msg info "Skipping tests for DPDK build to save time and memory"
    fi

    msg info "Installing srsRAN Project ($build_type version)"
    if ! make install; then
        msg error "Installation failed for $build_type version"
        cleanup_build_environment
        return 1
    fi

    # Set ownership and execution permissions for srsRAN binaries
    msg info "Setting ownership and permissions for srsRAN binaries"
    if [ -d "$install_dir/bin" ]; then
        # Change ownership to root user
        chown -R root:root "$install_dir/bin" 2>/dev/null || true
        # Ensure execution permissions
        chmod +x "$install_dir/bin"/* 2>/dev/null || true
        msg info "✓ Ownership and execution permissions set for binaries in $install_dir/bin"
    else
        msg warning "Binary directory $install_dir/bin not found"
    fi
    
    # Set directory permissions and ownership for the entire installation directory
    if [ -d "$install_dir" ]; then
        # Set directory permissions first
        chmod 755 "$install_dir" 2>/dev/null || true
        chmod 755 "$install_dir/bin" 2>/dev/null || true
        msg info "✓ Directory permissions (755) set for $install_dir and $install_dir/bin"
        
        # Then set ownership
        chown -R root:root "$install_dir" 2>/dev/null || true
        msg info "✓ Ownership set for entire installation directory $install_dir"
    fi

    # Verify installation immediately after make install
    local missing_binaries=()
    
    # Check for required binaries
    [ ! -f "$install_dir/bin/gnb" ] && missing_binaries+=("gnb")
    [ ! -f "$install_dir/bin/srscu" ] && missing_binaries+=("srscu")
    [ ! -f "$install_dir/bin/srsdu" ] && missing_binaries+=("srsdu")
    
    if [ ${#missing_binaries[@]} -gt 0 ]; then
        msg error "Installation verification failed: missing binaries: ${missing_binaries[*]}"
        msg info "Contents of $install_dir:"
        ls -la "$install_dir" || msg info "Cannot list $install_dir"
        if [ -d "$install_dir/bin" ]; then
            msg info "Contents of $install_dir/bin:"
            ls -la "$install_dir/bin" || msg info "Cannot list $install_dir/bin"
        fi
        cleanup_build_environment
        return 1
    else
        msg info "✓ Installation verification successful: all required binaries found (gnb, srscu, srsdu)"
    fi
    
    # Cleanup build environment
    cleanup_build_environment
    
    msg info "✓ srsRAN $build_type version build completed"
}

###############################################################################
# Helper Functions
###############################################################################

# Function to verify that the system is ready
wait_for_system_ready()
{
    local max_wait=60  # Maximum 1 minutes wait
    local wait_time=0
    local check_interval=3
    
    msg info "Verifying that essential system components are ready..."
    
    while [ $wait_time -lt $max_wait ]; do
        local ready=true
        
        # Verify that kernel modules are loaded
        if ! lsmod | grep -q "ptp_kvm\|uio"; then
            ready=false
            msg info "Waiting for kernel modules to be loaded..."
        fi
        
        # Verify that filesystems are completely mounted
        if ! mountpoint -q /proc || ! mountpoint -q /sys; then
            ready=false
            msg info "Waiting for filesystems to be mounted..."
        fi
                    
        if [ "$ready" = "true" ]; then
            msg info "✓ Essential system components ready after ${wait_time}s"
            return 0
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    msg warning "Essential system components not ready after ${max_wait}s, continuing anyway"
    return 1
}

# Function to verify and wait for DPDK drivers to be ready
wait_for_dpdk_ready()
{
    local pci_device="$1"
    local max_wait=60  # Maximum 1 minute wait
    local wait_time=0
    local check_interval=2
    
    msg info "Verifying that DPDK drivers are ready for device $pci_device..."
    
    while [ $wait_time -lt $max_wait ]; do
        # Verify that the PCI device is available
        if lspci -s "$pci_device" >/dev/null 2>&1; then
            # Verify that no binding operations are in progress
            if ! pgrep -f "dpdk-devbind" >/dev/null 2>&1; then
                msg info "✓ DPDK drivers ready after ${wait_time}s"
                return 0
            else
                msg info "Waiting for ongoing binding operations to complete..."
            fi
        else
            msg info "Waiting for PCI device $pci_device to be available..."
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    msg warning "DPDK drivers not ready after ${max_wait}s, continuing anyway"
    return 1
}

create_systemd_services()
{
    # Use the base installation for systemd services during install phase
    # This will be updated during configure phase to use the correct installation
    local install_dir_for_service="${SRSRAN_INSTALL_DIR:-$SRSRAN_INSTALL_DIR_BASE}"
    
    # Create system verification script
    cat > /usr/local/bin/srsran-system-check.sh <<'SCRIPT_EOF'
#!/bin/bash
# System verification script for srsRAN

echo "[$(date)] Starting system verification for srsRAN..."

# Verify that necessary modules are loaded
echo "[$(date)] Checking kernel modules..."
for module in uio ptp_kvm; do
    if ! lsmod | grep -q "$module"; then
        echo "[$(date)] Loading module $module..."
        modprobe "$module" 2>/dev/null || echo "[$(date)] Warning: Could not load module $module"
    else
        echo "[$(date)] ✓ Module $module is already loaded"
    fi
done

# Basic network subsystem check (not interface-specific)
echo "[$(date)] Checking network subsystem..."
if systemctl is-active --quiet network.target; then
    echo "[$(date)] ✓ Network subsystem initialized"
else
    echo "[$(date)] Warning: Network subsystem not fully initialized"
fi
echo "[$(date)] Note: DPDK interfaces may not appear in standard network tools after binding"

# Verify that systemd has finished initializing
echo "[$(date)] Checking systemd status..."
system_state=$(systemctl is-system-running)
echo "[$(date)] System state: $system_state"

# Verify hugepages if DPDK is enabled
if [ -f "/etc/srsran/dpdk_enabled" ]; then
    echo "[$(date)] Checking hugepages configuration for DPDK..."
    hugepages_1g=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo "0")
    echo "[$(date)] 1GB hugepages configured: $hugepages_1g"
    
    if [ "$hugepages_1g" -gt 0 ]; then
        echo "[$(date)] ✓ Hugepages configured correctly"
    else
        echo "[$(date)] Warning: No 1GB hugepages configured"
    fi
fi

echo "[$(date)] System verification completed"
exit 0
SCRIPT_EOF

    chmod +x /usr/local/bin/srsran-system-check.sh

    # gNodeB Service
    cat > /etc/systemd/system/srsran-gnb.service <<EOF
[Unit]
Description=srsRAN Project gNodeB
After=network.target
# Execute system verification before starting the service
ExecStartPre=/usr/local/bin/srsran-system-check.sh
# Add additional delay to ensure stability
ExecStartPre=/bin/sleep 15

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${SRSRAN_DATA_DIR}
ExecStart=${install_dir_for_service}/bin/gnb -c ${SRSRAN_CONFIG_DIR}/gnb.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # CU Service (unified CU-CP and CU-UP)
    cat > /etc/systemd/system/srsran-cu.service <<EOF
[Unit]
Description=srsRAN Project CU (Central Unit - CP and UP combined)
After=network.target
# Execute system verification before starting the service
ExecStartPre=/usr/local/bin/srsran-system-check.sh
# Add additional delay to ensure stability
ExecStartPre=/bin/sleep 15

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${SRSRAN_DATA_DIR}
ExecStart=${install_dir_for_service}/bin/srscu -c ${SRSRAN_CONFIG_DIR}/cu.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # DU Service
    cat > /etc/systemd/system/srsran-du.service <<EOF
[Unit]
Description=srsRAN Project DU (Distributed Unit)
After=network.target
# Execute system verification before starting the service
ExecStartPre=/usr/local/bin/srsran-system-check.sh
# Add additional delay to ensure stability
ExecStartPre=/bin/sleep 15

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${SRSRAN_DATA_DIR}
ExecStart=${install_dir_for_service}/bin/srsdu -c ${SRSRAN_CONFIG_DIR}/du.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

update_systemd_services()
{
    # Update systemd service files to use the correct installation directory
    # This function is called during configure phase to update the ExecStart paths
    
    msg info "Updating systemd service files to use correct installation directory"
    
    # Update gNodeB Service
    sed -i "s|ExecStart=.*gnb|ExecStart=${SRSRAN_INSTALL_DIR}/bin/gnb|g; s|/bin/gnb\.yaml|/bin/gnb -c ${SRSRAN_CONFIG_DIR}/gnb.yaml|g" /etc/systemd/system/srsran-gnb.service

    # Update CU service (unified CU-CP and CU-UP)
    sed -i "s|ExecStart=.*srscu|ExecStart=${SRSRAN_INSTALL_DIR}/bin/srscu|g; s|/bin/srscu\.yaml|/bin/srscu -c ${SRSRAN_CONFIG_DIR}/cu.yaml|g" /etc/systemd/system/srsran-cu.service

    # Update DU service
    sed -i "s|ExecStart=.*srsdu|ExecStart=${SRSRAN_INSTALL_DIR}/bin/srsdu|g; s|/bin/srsdu\.yaml|/bin/srsdu -c ${SRSRAN_CONFIG_DIR}/du.yaml|g" /etc/systemd/system/srsran-du.service
    
    # Reload systemd to pick up changes
    systemctl daemon-reload
    
    msg info "✓ Systemd service files updated to use $SRSRAN_INSTALL_DIR"
}

configure_gnb()
{
    msg info "Configuring srsRAN Project gNodeB (CU+DU combined)"
    
    # Create customized gNB configuration based on production template
    # Update the production template with user-provided parameters
    cat > "${SRSRAN_CONFIG_DIR}/gnb.yaml" <<EOF
gnb_id: 0
gnb_id_bit_length: 32
gnb_du_id: 2

cu_cp:
  amf:
    addr: ${ONEAPP_SRSRAN_AMF_IPV4}                    # The address or hostname of the AMF.
    bind_addr: 10.0.3.3                              # A local IP that the gNB binds to for traffic from the AMF.
    supported_tracking_areas:                        # Sets the list of tracking areas supported by this AMF
      - tac: ${ONEAPP_SRSRAN_TAC}                     # Supported TAC. Sets the Tracking Area Code 
        plmn_list:                                     # Sets the list of PLMN items supported for this TAC
          - plmn: "${ONEAPP_SRSRAN_MCC}${ONEAPP_SRSRAN_MNC}"  # Sets the Public Land Mobile Network code
            tai_slice_support_list:                      # Sets the list of TAI slices for this PLMN item
              - sst: 1                                     # Sets the Slice Service Type 

cell_cfg:
  sector_id: 1
  plmn: ${ONEAPP_SRSRAN_MCC}${ONEAPP_SRSRAN_MNC}
  slicing:
    - sst: 1
  pci: ${ONEAPP_SRSRAN_PCI}
  tac: ${ONEAPP_SRSRAN_TAC}
  dl_arfcn: ${ONEAPP_SRSRAN_DL_ARFCN}
  band: ${ONEAPP_SRSRAN_BAND#n}                        # Remove 'n' prefix if present
  channel_bandwidth_MHz: ${ONEAPP_SRSRAN_CHANNEL_BW_MHZ}
  common_scs: ${ONEAPP_SRSRAN_COMMON_SCS}
  nof_antennas_dl: 4
  nof_antennas_ul: 2
  pcg_p_nr_fr1: 23
  
  ssb:
    ssb_period: 10
    ssb_block_power_dbm: -11
    pss_to_sss_epre_db: 0

  ul_common:
    p_max: 23

  pdsch:
    mcs_table: qam256
    max_pdschs_per_slot: 6
    max_alloc_attempts: 8
    olla_target_bler: 0.1
    olla_max_cqi_offset: 20
    olla_cqi_inc_step: 0.05
    dc_offset: center

  pusch:
    mcs_table: qam256
    min_k2: 2
    olla_target_bler: 0.1
    olla_snr_inc_step: 0.05
    olla_max_snr_offset: 20
    p0_nominal_with_grant: -76

  pucch:
    min_k1: 2
    nof_cell_harq_pucch_res_sets: 6
    sr_period_ms: 10

  prach:
    preamble_trans_max: 200
    power_ramping_step_db: 2
    prach_config_index: 159

  tdd_ul_dl_cfg: 
    dl_ul_tx_period: 10
    nof_dl_slots: 7
    nof_dl_symbols: 6
    nof_ul_slots: 2
    nof_ul_symbols: 4

# Open Fronthaul RU configuration for Split 7.2
ru_ofh:
  t1a_max_cp_dl: 380
  t1a_min_cp_dl: 180
  t1a_max_cp_ul: 380
  t1a_min_cp_ul: 180
  t1a_max_up: 380
  t1a_min_up: 180
  ta4_max: 500
  ta4_min: 0

  compr_method_ul: bfp
  compr_bitwidth_ul: 9
  compr_method_dl: bfp
  compr_bitwidth_dl: 9
  compr_method_prach: bfp
  compr_bitwidth_prach: 9

  is_prach_cp_enabled: true
  enable_ul_static_compr_hdr: true
  enable_dl_static_compr_hdr: true
  ignore_ecpri_payload_size: false
  ignore_ecpri_seq_id: true
  iq_scaling: 3

  cells:
    - network_interface: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "${ONEAPP_SRSRAN_NIC_PCI_ADDR}" || echo "eth1")
      ru_mac_addr: ${ONEAPP_SRSRAN_RU_MAC}
      du_mac_addr: a2:b3:a6:4e:de:49
      vlan_tag_cp: 564
      vlan_tag_up: 564
      prach_port_id: [0,1]
      dl_port_id: [0,1,2,3]
      ul_port_id: [0,1]
EOF

    # Add HAL configuration only for DPDK version
    if [[ "$ONEAPP_SRSRAN_ENABLE_DPDK" == "YES" ]]; then
        cat >> "${SRSRAN_CONFIG_DIR}/gnb.yaml" <<EOF

# HAL configuration for DPDK
hal:
  eal_args: "--lcores (0-1)@(6-10,22-26) --proc-type auto -a ${ONEAPP_SRSRAN_NIC_PCI_ADDR}"
EOF
    fi

    cat >> "${SRSRAN_CONFIG_DIR}/gnb.yaml" <<EOF

# Expert PHY configuration
expert_phy:
  max_request_headroom_slots: 3
  max_proc_delay: 6
  pusch_dec_max_iterations: 4

# Expert execution configuration
expert_execution:
  affinities:
    low_priority_cpus: 7-8,23-25
    low_priority_pinning: mask
    ru_timing_cpu: 6,22
    ofh:
      - ru_txrx_cpus: 10,26
  cell_affinities:
    -
      l1_dl_cpus: 7-8,23-25
      l1_dl_pinning: mask
      l1_ul_cpus: 7-8,23-25
      l1_ul_pinning: mask
      l2_cell_cpus: 9
      l2_cell_pinning: mask
      ru_cpus: 10,26
      ru_pinning: mask
  threads:
    upper_phy:
      pdsch_processor_type: auto
      nof_pusch_decoder_threads: 2
      nof_ul_threads: 1
      nof_dl_threads: 4
    ofh:
      enable_dl_parallelization: 1

log:
  filename: ${SRSRAN_LOG_DIR}/gnb.log
  all_level: info
EOF

    chown root:root "${SRSRAN_CONFIG_DIR}/gnb.yaml"
    
    msg info "gNB configuration created: ${SRSRAN_CONFIG_DIR}/gnb.yaml"
    msg info "To start gNB: gnb -c ${SRSRAN_CONFIG_DIR}/gnb.yaml"
    msg info "For production Split 7.2 with OFH, use: gnb -c ${SRSRAN_CONFIG_DIR}/gnb_ru_liteon_tdd_n77_100mhz_4x2.yaml"
}

configure_cu()
{
    msg info "Configuring srsRAN Project CU (CU-CP + CU-UP combined)"
    
    # Create CU configuration based on the production YAML template
    cat > "${SRSRAN_CONFIG_DIR}/cu.yaml" <<EOF
#
# srsRAN Project CU configuration file (CU-CP + CU-UP combined)
# Based on production configuration template
#

gnb_id: 0
gnb_id_bit_length: 32

cu_cp:
  amf:
    addr: ${ONEAPP_SRSRAN_AMF_IPV4}                    # The address or hostname of the AMF.
    bind_addr: 127.0.0.1                              # A local IP that the gNB binds to for traffic from the AMF.
    supported_tracking_areas:                        # Sets the list of tracking areas supported by this AMF
      - tac: ${ONEAPP_SRSRAN_TAC}                     # Supported TAC. Sets the Tracking Area Code 
        plmn_list:                                     # Sets the list of PLMN items supported for this TAC
          - plmn: "${ONEAPP_SRSRAN_MCC}${ONEAPP_SRSRAN_MNC}"  # Sets the Public Land Mobile Network code
            tai_slice_support_list:                      # Sets the list of TAI slices for this PLMN item
              - sst: 1                                     # Sets the Slice Service Type 

  f1ap:
    bind_addr: 127.0.0.1                              # A local IP that the CU-CP binds to for traffic from the DU.

cu_up:
  f1u:
    socket:
      - bind_addr: 127.0.0.1                          # Sets the address that the F1-U socket will bind to.

  gtpu:
    bind_addr: 127.0.0.1                              # A local IP that the CU-UP binds to for traffic from the UPF.

log:
  filename: ${SRSRAN_LOG_DIR}/cu.log
  all_level: info
EOF

    chown root:root "${SRSRAN_CONFIG_DIR}/cu.yaml"
    
    msg info "CU configuration created: ${SRSRAN_CONFIG_DIR}/cu.yaml"
    msg info "To start CU: srscu -c ${SRSRAN_CONFIG_DIR}/cu.yaml"
}

configure_du()
{
    msg info "Configuring srsRAN Project DU"
    
    cat > "${SRSRAN_CONFIG_DIR}/du.yaml" <<EOF
gnb_id: 0
gnb_id_bit_length: 32
gnb_du_id: 2

# F1AP configuration for DU
f1ap:
  cu_cp_addr: 127.0.0.1                              # Address of the CU-CP
  cu_cp_port: 38472                                   # Port of the CU-CP
  bind_addr: 127.0.0.1                               # Local IP that the DU binds to for F1AP

cell_cfg:
  sector_id: 1
  plmn: ${ONEAPP_SRSRAN_MCC}${ONEAPP_SRSRAN_MNC}
  slicing:
    - sst: 1
  pci: ${ONEAPP_SRSRAN_PCI}
  tac: ${ONEAPP_SRSRAN_TAC}
  dl_arfcn: ${ONEAPP_SRSRAN_DL_ARFCN}
  band: ${ONEAPP_SRSRAN_BAND#n}                        # Remove 'n' prefix if present
  channel_bandwidth_MHz: ${ONEAPP_SRSRAN_CHANNEL_BW_MHZ}
  common_scs: ${ONEAPP_SRSRAN_COMMON_SCS}
  nof_antennas_dl: 4
  nof_antennas_ul: 2
  pcg_p_nr_fr1: 23
  
  ssb:
    ssb_period: 10
    ssb_block_power_dbm: -11
    pss_to_sss_epre_db: 0

  ul_common:
    p_max: 23

  pdsch:
    mcs_table: qam256
    max_pdschs_per_slot: 6
    max_alloc_attempts: 8
    olla_target_bler: 0.1
    olla_max_cqi_offset: 20
    olla_cqi_inc_step: 0.05
    dc_offset: center

  pusch:
    mcs_table: qam256
    min_k2: 2
    olla_target_bler: 0.1
    olla_snr_inc_step: 0.05
    olla_max_snr_offset: 20
    p0_nominal_with_grant: -76

  pucch:
    min_k1: 2
    nof_cell_harq_pucch_res_sets: 6
    sr_period_ms: 10

  prach:
    preamble_trans_max: 200
    power_ramping_step_db: 2
    prach_config_index: 159

  tdd_ul_dl_cfg: 
    dl_ul_tx_period: 10
    nof_dl_slots: 7
    nof_dl_symbols: 6
    nof_ul_slots: 2
    nof_ul_symbols: 4

# Open Fronthaul RU configuration for Split 7.2
ru_ofh:
  t1a_max_cp_dl: 380
  t1a_min_cp_dl: 180
  t1a_max_cp_ul: 380
  t1a_min_cp_ul: 180
  t1a_max_up: 380
  t1a_min_up: 180
  ta4_max: 500
  ta4_min: 0

  compr_method_ul: bfp
  compr_bitwidth_ul: 9
  compr_method_dl: bfp
  compr_bitwidth_dl: 9
  compr_method_prach: bfp
  compr_bitwidth_prach: 9

  is_prach_cp_enabled: true
  enable_ul_static_compr_hdr: true
  enable_dl_static_compr_hdr: true
  ignore_ecpri_payload_size: false
  ignore_ecpri_seq_id: true
  iq_scaling: 3

  cells:
    - network_interface: $([ "$ONEAPP_SRSRAN_ENABLE_DPDK" = "YES" ] && echo "${ONEAPP_SRSRAN_NIC_PCI_ADDR}" || echo "eth1")
      ru_mac_addr: ${ONEAPP_SRSRAN_RU_MAC}
      du_mac_addr: a2:b3:a6:4e:de:49
      vlan_tag_cp: 564
      vlan_tag_up: 564
      prach_port_id: [0,1]
      dl_port_id: [0,1,2,3]
      ul_port_id: [0,1]
EOF

    # Add HAL configuration only for DPDK version
    if [[ "$ONEAPP_SRSRAN_ENABLE_DPDK" == "YES" ]]; then
        cat >> "${SRSRAN_CONFIG_DIR}/du.yaml" <<EOF

# HAL configuration for DPDK
hal:
  eal_args: "--lcores (0-1)@(6-10,22-26) --proc-type auto -a ${ONEAPP_SRSRAN_NIC_PCI_ADDR}"
EOF
    fi

    cat >> "${SRSRAN_CONFIG_DIR}/du.yaml" <<EOF

# Expert PHY configuration
expert_phy:
  max_request_headroom_slots: 3
  max_proc_delay: 6
  pusch_dec_max_iterations: 4

# Expert execution configuration
expert_execution:
  affinities:
    low_priority_cpus: 7-8,23-25
    low_priority_pinning: mask
    ru_timing_cpu: 6,22
    ofh:
      - ru_txrx_cpus: 10,26
  cell_affinities:
    -
      l1_dl_cpus: 7-8,23-25
      l1_dl_pinning: mask
      l1_ul_cpus: 7-8,23-25
      l1_ul_pinning: mask
      l2_cell_cpus: 9
      l2_cell_pinning: mask
      ru_cpus: 10,26
      ru_pinning: mask
  threads:
    upper_phy:
      pdsch_processor_type: auto
      nof_pusch_decoder_threads: 2
      nof_ul_threads: 1
      nof_dl_threads: 4
    ofh:
      enable_dl_parallelization: 1

log:
  filename: ${SRSRAN_LOG_DIR}/du.log
  all_level: info
EOF

    chown root:root "${SRSRAN_CONFIG_DIR}/du.yaml"
    
    msg info "DU configuration created: ${SRSRAN_CONFIG_DIR}/du.yaml"
    msg info "To start DU: srsdu -c ${SRSRAN_CONFIG_DIR}/du.yaml"
}

configure_phc2sys_service()
{
    msg info "Configuring PHC2SYS service for VM clock synchronization"
    
    # Check if LinuxPTP is installed
    if [ ! -f "/usr/local/sbin/phc2sys" ]; then
        msg warning "PHC2SYS binary not found at /usr/local/sbin/phc2sys"
        msg warning "LinuxPTP may not be installed correctly"
        return 1
    fi
    
    # Check if service file exists
    if [ ! -f "/etc/systemd/system/phc2sys.service" ]; then
        msg warning "PHC2SYS service file not found at /etc/systemd/system/phc2sys.service"
        msg warning "Service file may not have been copied correctly"
        return 1
    fi
    
    # Stop conflicting time synchronization services
    msg info "Stopping conflicting time synchronization services"
    local conflicting_services=("chrony" "systemd-timesyncd" "ntpd" "ptpd" "ptp4l")
    
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            msg info "Stopping $service..."
            systemctl stop "$service" || true
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            msg info "Disabling $service..."
            systemctl disable "$service" || true
        fi
    done
    
    # Reload systemd daemon to recognize the new service
    msg info "Reloading systemd daemon"
    systemctl daemon-reload
    
    # Enable PHC2SYS service
    msg info "Enabling PHC2SYS service"
    if systemctl enable phc2sys.service; then
        msg info "✓ PHC2SYS service enabled successfully"
    else
        msg error "Failed to enable PHC2SYS service"
        return 1
    fi
    
    msg info "PHC2SYS service configuration completed"
    msg info "Service will start automatically on boot"
    msg info "To start manually: systemctl start phc2sys.service"
    msg info "To check status: systemctl status phc2sys.service"
    msg info "To view logs: journalctl -u phc2sys.service -f"
    
    return 0
}


# Disable DRM KMS polling for performance optimization
disable_drm_kms_polling()
{
    msg info "Disabling DRM KMS polling for performance optimization..."
    
    local drm_poll_file="/sys/module/drm_kms_helper/parameters/poll"
    
    if [ -f "$drm_poll_file" ]; then
        local current_status=$(cat "$drm_poll_file" 2>/dev/null || echo "unknown")
        msg info "Current DRM KMS polling status: $current_status"
        
        if [ "$current_status" = "N" ]; then
            msg info "DRM KMS polling already disabled"
            return 0
        fi
        
        # Disable DRM KMS polling
        if echo N | tee "$drm_poll_file" >/dev/null 2>&1; then
            msg info "DRM KMS polling disabled successfully"
            
            # Verify the change
            local new_status=$(cat "$drm_poll_file" 2>/dev/null || echo "unknown")
            msg info "Verification: DRM KMS polling status is now $new_status"
        else
            msg warning "Failed to disable DRM KMS polling - system may not support this optimization"
            return 1
        fi
    else
        msg warning "DRM KMS helper module not loaded or available - skipping this optimization"
        return 0
    fi
}

# Apply network buffer optimizations
apply_network_optimizations()
{
    msg info "Applying network buffer optimizations..."
    
    # Set network buffer sizes for better performance
    msg info "Setting network buffer sizes..."
    sysctl -w net.core.wmem_max=33554432 || msg warning "Failed to set wmem_max"
    sysctl -w net.core.rmem_max=33554432 || msg warning "Failed to set rmem_max"
    sysctl -w net.core.wmem_default=33554432 || msg warning "Failed to set wmem_default"
    sysctl -w net.core.rmem_default=33554432 || msg warning "Failed to set rmem_default"
    
    # Make these settings persistent
    local sysctl_conf="/etc/sysctl.d/99-srsran-network.conf"
    msg info "Making network optimizations persistent in $sysctl_conf..."
    
    cat > "$sysctl_conf" << 'EOF'
# srsRAN Network Buffer Optimizations
net.core.wmem_max = 33554432
net.core.rmem_max = 33554432
net.core.wmem_default = 33554432
net.core.rmem_default = 33554432
EOF
    
    msg info "Network buffer optimizations applied and made persistent"
    return 0
}

# Elevate RT priorities for kernel threads
elevate_rt_priorities()
{
    msg info "Elevating RT priorities for kernel threads..."
    
    # Check if tuna is available
    if ! command -v tuna >/dev/null 2>&1; then
        msg info "tuna command not found - installing tuna package..."
        apt-get update >/dev/null 2>&1
        if apt-get install -y tuna >/dev/null 2>&1; then
            msg info "tuna package installed successfully"
        else
            msg warning "Failed to install tuna package - skipping RT priority elevation"
            msg warning "Please install tuna manually: apt-get install tuna"
            return 1
        fi
    fi
    
    msg info "Elevating ksoftirqd priorities..."
    
    # Elevate RT priorities for ksoftirqd threads (CPUs 1-15)
    local x=1
    local y=15
    for i in $(seq $x $y); do
        if pgrep -f "ksoftirqd/$i" >/dev/null 2>&1; then
            tuna -t "ksoftirqd/$i" -p fifo:99 >/dev/null 2>&1 || msg warning "Failed to set priority for ksoftirqd/$i"
        fi
    done
    
    # Elevate RT priorities for ksoftirqd threads (CPUs 17-31)
    local a=17
    local b=31
    for i in $(seq $a $b); do
        if pgrep -f "ksoftirqd/$i" >/dev/null 2>&1; then
            tuna -t "ksoftirqd/$i" -p fifo:99 >/dev/null 2>&1 || msg warning "Failed to set priority for ksoftirqd/$i"
        fi
    done
    
    msg info "Elevating kworker/u48 priorities..."
    
    # Elevate RT priorities for kworker/u48 threads
    for i in $(pgrep kworker/u48 2>/dev/null || true); do
        if [ -n "$i" ]; then
            tuna -t "$i" -p fifo:99 >/dev/null 2>&1 || msg warning "Failed to set priority for kworker/u48 PID $i"
        fi
    done
    
    msg info "RT priorities elevated for kernel threads"
    return 0
}

install_config_templates()
{
    msg info "Installing production-ready configuration templates"
    
    # Copy predefined configuration templates from /etc/srsran/pre-defined-configs/
    if [ -d "/etc/srsran/pre-defined-configs" ]; then
        msg info "Copying configuration templates from /etc/srsran/pre-defined-configs/"
        cp /etc/srsran/pre-defined-configs/*.yaml "${SRSRAN_CONFIG_DIR}/" 2>/dev/null || true
        chown root:root "${SRSRAN_CONFIG_DIR}"/*.yaml 2>/dev/null || true
        
        if [ -f "${SRSRAN_CONFIG_DIR}/gnb_ru_liteon_tdd_n77_100mhz_4x2.yaml" ]; then
            msg info "Production configuration template installed: gnb_ru_liteon_tdd_n77_100mhz_4x2.yaml"
            msg info "This configuration is for LiteON RU with TDD n77 band, 100MHz BW, 4x2 MIMO"
        else
            msg warning "Template gnb_ru_liteon_tdd_n77_100mhz_4x2.yaml not found in /etc/srsran/pre-defined-configs/"
        fi
    else
        msg warning "Pre-defined configs directory /etc/srsran/pre-defined-configs/ not found"
        msg info "Skipping template installation"
    fi
}
