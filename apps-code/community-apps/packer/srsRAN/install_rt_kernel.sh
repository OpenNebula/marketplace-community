#!/usr/bin/env bash

# RT Kernel Installation Script for srsRAN Project
# This script installs and configures the Real-Time kernel before the main srsRAN installation

# Configuration: Set to true to delete RT kernel packages after installation to save space
# Set to false to keep packages for future use
CLEANUP_RT_PACKAGES=true

set -e

# Logging function
msg()
{
    msg_type="$1"
    shift

    case "$msg_type" in
        info)
            printf "[%s] => " "$(date)"
            echo 'INFO:' "$@"
            ;;
        debug)
            printf "[%s] => " "$(date)" >&2
            echo 'DEBUG:' "$@" >&2
            ;;
        warning)
            printf "[%s] => " "$(date)" >&2
            echo 'WARNING [!]:' "$@" >&2
            ;;
        error)
            printf "[%s] => " "$(date)" >&2
            echo 'ERROR [!!]:' "$@" >&2
            return 1
            ;;
        *)
            printf "[%s] => " "$(date)" >&2
            echo 'UNKNOWN [?!]:' "$@" >&2
            return 2
            ;;
    esac
    return 0
}

# Configure GRUB to automatically boot RT kernel
configure_grub_rt_kernel() {
    msg info "Configuring GRUB to automatically boot RT kernel"
    
    # Update GRUB to detect new kernel
    update-grub
    
    # Find RT kernel entry
    local rt_kernel_id=""
    if [ -f /boot/grub/grub.cfg ]; then
        local submenu_id=$(grep "submenu.*Advanced options" /boot/grub/grub.cfg | head -1 | sed -n "s/.*submenu '[^']*' \$menuentry_id_option '\([^']*\)'.*/\1/p")
        local kernel_id=$(grep "menuentry.*preempt-rt" /boot/grub/grub.cfg | head -1 | sed -n "s/.*\$menuentry_id_option '\([^']*\)'.*/\1/p")
        
        if [ -n "$submenu_id" ] && [ -n "$kernel_id" ]; then
            rt_kernel_id="${submenu_id}>${kernel_id}"
        fi
    fi
    
    if [ -n "$rt_kernel_id" ]; then
        # Backup current GRUB config
        cp /etc/default/grub /etc/default/grub.backup
        
        # Set RT kernel as default
        if grep -q "^GRUB_DEFAULT=" /etc/default/grub; then
            sed -i "s#^GRUB_DEFAULT=.*#GRUB_DEFAULT=\"$rt_kernel_id\"#" /etc/default/grub
        else
            echo "GRUB_DEFAULT=\"$rt_kernel_id\"" >> /etc/default/grub
        fi
        
        # Set short timeout
        if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
            sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
        else
            echo "GRUB_TIMEOUT=3" >> /etc/default/grub
        fi
        
        # Ensure menu is accessible
        sed -i 's/^GRUB_HIDDEN_TIMEOUT/#GRUB_HIDDEN_TIMEOUT/g' /etc/default/grub
        sed -i 's/^GRUB_TIMEOUT_STYLE=hidden/#GRUB_TIMEOUT_STYLE=hidden/g' /etc/default/grub
        
        # Update GRUB
        update-grub
        
        msg info "RT kernel set as default boot option"
    else
        msg warning "Could not find RT kernel entry in GRUB"
    fi
}

# Configure system for real-time applications
configure_realtime_system() {
    msg info "Configuring system for real-time applications"
    
    # Create realtime limits configuration
    if [ ! -f /etc/security/limits.d/99-realtime.conf ]; then
        cat > /etc/security/limits.d/99-realtime.conf << 'EOF'
# Real-time limits for srsRAN applications
@realtime - rtprio 99
@realtime - memlock unlimited
@realtime - nice -19
EOF
    fi
    
    # Create realtime group if it doesn't exist
    if ! grep -q "^realtime:" /etc/group; then
        if ! getent group realtime >/dev/null 2>&1; then
            addgroup --system realtime
            msg info "Created realtime group"
        fi
    fi
    
    # Set CPU DMA latency permissions
    msg info "Setting CPU DMA latency permissions for realtime access"
    chmod 0666 /dev/cpu_dma_latency
    
    # Create udev rule for persistent permissions
    msg info "Creating udev rule for persistent CPU DMA latency permissions"
    cat > /etc/udev/rules.d/99-cpu-dma-latency.rules << 'EOF'
# Allow realtime group to control CPU DMA latency
KERNEL=="cpu_dma_latency", GROUP="realtime", MODE="0664"
EOF
    
    msg info "Real-time system configuration completed"
}

# Main RT kernel installation function
install_rt_kernel()
{
    msg info "Installing Real-Time kernel for performance optimization"
    
    # Kernel version constants
    local KERNEL_VERSION="6.8.2"
    local KERNEL_VERSION_PATCH="6.8.2-rt10"
    local RT_DOWNLOAD_DIR="/tmp/rt_preempt_kernel_install"
    local RT_BUILD_DIR="/tmp/rt_kernel_build"
    local DEFAULT_CONFIG="/boot/config-$(uname -r)"
    
    # Check if RT kernel is already installed
    local current_kernel=$(uname -r)
    if [[ "$current_kernel" == *"rt"* ]]; then
        msg info "Real-time kernel already running: $current_kernel"
        return 0
    fi
    
    # Check if target RT kernel is already installed
    if dpkg -l | grep -q "linux-image.*${KERNEL_VERSION_PATCH}.*preempt-rt"; then
        msg info "Target RT kernel $KERNEL_VERSION_PATCH already installed"
        configure_grub_rt_kernel
        return 0
    fi
    
    # Check if pre-built RT kernel packages exist and install them
    if [ -d "/etc/rt-kernel-packages" ] && [ "$(ls -A /etc/rt-kernel-packages/*.deb 2>/dev/null)" ]; then
        msg info "Found pre-built RT kernel packages in /etc/rt-kernel-packages/"
        
        # Find and install packages
        local header_pkg=$(ls /etc/rt-kernel-packages/linux-headers-${KERNEL_VERSION_PATCH}-preempt-rt_*.deb 2>/dev/null | head -1)
        local image_pkg=$(ls /etc/rt-kernel-packages/linux-image-${KERNEL_VERSION_PATCH}-preempt-rt_*.deb 2>/dev/null | head -1)
        local libc_pkg=$(ls /etc/rt-kernel-packages/linux-libc-dev_*.deb 2>/dev/null | head -1)
        
        if [ -n "$header_pkg" ] && [ -n "$image_pkg" ]; then
            msg info "Installing pre-built RT kernel packages"
            
            dpkg -i "$header_pkg" || {
                msg error "Failed to install pre-built kernel headers"
                exit 1
            }
            
            dpkg -i "$image_pkg" || {
                msg error "Failed to install pre-built kernel image"
                exit 1
            }
            
            if [ -n "$libc_pkg" ]; then
                dpkg -i "$libc_pkg" || msg warning "Failed to install pre-built libc package (non-critical)"
            fi
            
            msg info "Pre-built RT kernel packages installed successfully"
            
            # Handle cleanup of pre-built packages if requested
            if [ "$CLEANUP_RT_PACKAGES" = "true" ]; then
                msg info "CLEANUP_RT_PACKAGES is enabled - removing pre-built RT kernel packages to save space"
                rm -rf /etc/rt-kernel-packages
                msg info "Removed RT kernel packages directory"
            fi
            
            # Configure GRUB and system
            configure_grub_rt_kernel
            configure_realtime_system
            
            msg info "RT kernel installation completed using pre-built packages"
            msg info "System will boot with RT kernel after reboot"
            return 0
        else
            msg warning "Pre-built packages found but incomplete (missing headers or image), proceeding with compilation"
        fi
    else
        msg info "No pre-built RT kernel packages found, proceeding with compilation"
    fi
    
    msg info "Installing RT kernel build dependencies"
    apt-get update
    apt-get install -y build-essential libelf-dev libncurses-dev libssl-dev \
        flex bison dwarves zstd debhelper bc kmod cpio rsync wget xz-utils \
        rt-tests || {
        msg error "Failed to install RT kernel dependencies"
        exit 1
    }
    
    # Check available disk space (at least 20GB)
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    local required_space=$((20 * 1024 * 1024))  # 20GB in KB
    if [ "$available_space" -lt "$required_space" ]; then
        msg error "Insufficient disk space in /tmp. Required: 20GB, Available: $((available_space / 1024 / 1024))GB"
        exit 1
    fi
    
    # Check if current config exists
    if [ ! -f "$DEFAULT_CONFIG" ]; then
        msg error "Current kernel config not found: $DEFAULT_CONFIG"
        exit 1
    fi
    
    # Clean and prepare directories
    rm -rf "$RT_BUILD_DIR" "$RT_DOWNLOAD_DIR"
    mkdir -p "$RT_DOWNLOAD_DIR" "$RT_BUILD_DIR"
    
    msg info "Downloading kernel sources and RT patches"
    cd "$RT_DOWNLOAD_DIR"
    
    # Download kernel and patch
    wget "https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" || {
        msg error "Failed to download kernel sources"
        exit 1
    }
    
    wget "https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.8/older/patch-${KERNEL_VERSION_PATCH}.patch.xz" || {
        msg error "Failed to download RT patch"
        exit 1
    }
    
    msg info "Extracting and patching kernel"
    cd "$RT_BUILD_DIR"
    tar --xz -xf "$RT_DOWNLOAD_DIR/linux-${KERNEL_VERSION}.tar.xz"
    cd "linux-${KERNEL_VERSION}/"
    
    # Apply RT patch
    xzcat "$RT_DOWNLOAD_DIR/patch-${KERNEL_VERSION_PATCH}.patch.xz" | patch -p1 || {
        msg error "Failed to apply RT patch"
        exit 1
    }
    
    msg info "Configuring RT kernel"
    # Copy current kernel config as base
    cp "$DEFAULT_CONFIG" .config
    
    # Enable RT preemption
    scripts/config --set-str LOCALVERSION "-preempt-rt"
    scripts/config --enable PREEMPT_RT
    scripts/config --disable PREEMPT_VOLUNTARY
    scripts/config --disable PREEMPT
    
    # Disable problematic options for compilation
    scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
    scripts/config --disable MODULE_COMPRESS_ZSTD
    scripts/config --enable MODULE_COMPRESS_NONE
    
    # RT optimizations
    scripts/config --enable HIGH_RES_TIMERS
    scripts/config --enable NO_HZ_FULL
    scripts/config --set-val HZ_1000 y
    scripts/config --set-val HZ 1000
    
    # Resolve dependencies
    make olddefconfig
    
    msg info "Building RT kernel (this may take 30-60 minutes)"
    local cpu_count=$(nproc)
    make -j"$cpu_count" bindeb-pkg || {
        msg error "Failed to build RT kernel"
        exit 1
    }
    
    msg info "Installing RT kernel packages"
    cd "$RT_BUILD_DIR"
    
    # Find and install packages
    local header_pkg=$(ls linux-headers-${KERNEL_VERSION_PATCH}-preempt-rt_*.deb 2>/dev/null | head -1)
    local image_pkg=$(ls linux-image-${KERNEL_VERSION_PATCH}-preempt-rt_*.deb 2>/dev/null | head -1)
    local libc_pkg=$(ls linux-libc-dev_*.deb 2>/dev/null | head -1)
    
    if [ -z "$header_pkg" ] || [ -z "$image_pkg" ]; then
        msg error "Built kernel packages not found"
        exit 1
    fi
    
    dpkg -i "$header_pkg" || {
        msg error "Failed to install kernel headers"
        exit 1
    }
    
    dpkg -i "$image_pkg" || {
        msg error "Failed to install kernel image"
        exit 1
    }
    
    if [ -n "$libc_pkg" ]; then
        dpkg -i "$libc_pkg" || msg warning "Failed to install libc package (non-critical)"
    fi
    
    # Handle RT kernel packages based on CLEANUP_RT_PACKAGES setting
    if [ "$CLEANUP_RT_PACKAGES" = "true" ]; then
        msg info "CLEANUP_RT_PACKAGES is enabled - RT kernel packages will be deleted to save space"
        # Remove any existing RT kernel packages directory
        if [ -d "/etc/rt-kernel-packages" ]; then
            rm -rf /etc/rt-kernel-packages
            msg info "Removed existing RT kernel packages directory"
        fi
    else
        msg info "CLEANUP_RT_PACKAGES is disabled - copying RT kernel packages to /etc/rt-kernel-packages/ for future use"
        mkdir -p /etc/rt-kernel-packages
        
        # Copy all generated .deb packages
        cp "$RT_BUILD_DIR"/*.deb /etc/rt-kernel-packages/ 2>/dev/null || {
            msg warning "Some packages could not be copied to /etc/rt-kernel-packages/"
        }
        
        # Create package inventory file
        ls -la "$RT_BUILD_DIR"/*.deb > /etc/rt-kernel-packages/package-inventory.txt 2>/dev/null
        echo "RT Kernel packages built on: $(date)" >> /etc/rt-kernel-packages/package-inventory.txt
        echo "Kernel version: $KERNEL_VERSION_PATCH" >> /etc/rt-kernel-packages/package-inventory.txt
        
        msg info "RT kernel packages preserved in /etc/rt-kernel-packages/"
    fi
    
    # Configure GRUB
    configure_grub_rt_kernel
    
    # Configure system for real-time
    configure_realtime_system
    
    # Cleanup
    rm -rf "$RT_BUILD_DIR" "$RT_DOWNLOAD_DIR"
    
    msg info "RT kernel installation completed successfully"
    msg info "System will boot with RT kernel after reboot"
}

# Main execution
if [ "$EUID" -ne 0 ]; then
    msg error "This script must be run as root"
    exit 1
fi

msg info "Starting RT kernel installation process"
install_rt_kernel
msg info "RT kernel installation script completed"