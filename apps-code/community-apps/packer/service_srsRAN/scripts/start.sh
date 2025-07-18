#!/bin/bash

# srsRAN Project Service Start Script
# Provides interactive service management with configuration display and modification

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration paths
SRSRAN_CONFIG_DIR="/etc/srsran"
ONE_SERVICE_REPORT="/etc/one-appliance/config"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

log_config() {
    echo -e "${MAGENTA}$1${NC}"
}

# Get current srsRAN mode from context or default
get_current_mode() {
    local mode="gnb"
    if [ -f "/var/lib/one-context/one_env" ]; then
        mode=$(grep "^ONEAPP_SRSRAN_MODE=" /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "gnb")
    fi
    echo "$mode"
}

# Get service name based on mode
get_service_name() {
    local mode="$1"
    case "$mode" in
        "gnb") echo "srsran-gnb" ;;
        "cu_cp") echo "srsran-cu-cp" ;;
        "cu_up") echo "srsran-cu-up" ;;
        "du") echo "srsran-du" ;;
        *) echo "srsran-gnb" ;;
    esac
}

# Check if service is running
is_service_running() {
    local service_name="$1"
    systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Display current configuration
show_current_config() {
    log_header "Current srsRAN Configuration"
    
    if [ -f "$ONE_SERVICE_REPORT" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                echo -e "${CYAN}$line${NC}"
            elif [[ "$line" =~ ^[A-Za-z] ]]; then
                log_config "  $line"
            else
                echo "$line"
            fi
        done < "$ONE_SERVICE_REPORT"
    else
        log_warn "Configuration report not found at $ONE_SERVICE_REPORT"
        log_info "Reading from context variables..."
        
        if [ -f "/var/lib/one-context/one_env" ]; then
            log_config "  Mode: $(grep '^ONEAPP_SRSRAN_MODE=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo 'gnb')"
            log_config "  MCC: $(grep '^ONEAPP_SRSRAN_MCC=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '999')"
            log_config "  MNC: $(grep '^ONEAPP_SRSRAN_MNC=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '75')"
            log_config "  TAC: $(grep '^ONEAPP_SRSRAN_TAC=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '1')"
            log_config "  PCI: $(grep '^ONEAPP_SRSRAN_PCI=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '69')"
            log_config "  DL ARFCN: $(grep '^ONEAPP_SRSRAN_DL_ARFCN=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '656668')"
            log_config "  Band: $(grep '^ONEAPP_SRSRAN_BAND=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo 'n77')"
            log_config "  Channel BW: $(grep '^ONEAPP_SRSRAN_CHANNEL_BW_MHZ=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo '100') MHz"
            log_config "  DPDK: $(grep '^ONEAPP_SRSRAN_ENABLE_DPDK=' /var/lib/one-context/one_env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo 'no')"
        else
            log_warn "Context variables not found"
        fi
    fi
    echo ""
}

 # Extract configuration details from YAML file
extract_config_details() {
    local config_file="$1"
    local mode="Unknown"
    local ru="Unknown"
    local band="Unknown"
    local bandwidth="Unknown"
    local antennas="Unknown"
    local dpdk="Unknown"
    
    if [ -f "$config_file" ]; then
        # First try to extract from header comments (more reliable)
        local header_info=$(head -15 "$config_file" | grep "^#")
        
        # Extract deployment mode from comments
        if echo "$header_info" | grep -qi "CU + DU.*gNB"; then
            mode="gNB"
        elif echo "$header_info" | grep -qi "CU.*CP.*UP"; then
            mode="CU (CP+UP)"
        elif echo "$header_info" | grep -qi "CU-CP"; then
            mode="CU-CP"
        elif echo "$header_info" | grep -qi "CU-UP"; then
            mode="CU-UP"
        elif echo "$header_info" | grep -qi "DU"; then
            mode="DU"
        else
            # Fallback to YAML content analysis
            if grep -q "^cu_cp:" "$config_file"; then
                if grep -q "^cu_up:" "$config_file"; then
                    mode="CU (CP+UP)"
                else
                    mode="CU-CP"
                fi
            elif grep -q "^cu_up:" "$config_file"; then
                mode="CU-UP"
            elif grep -q "^du:" "$config_file"; then
                mode="DU"
            else
                mode="gNB"
            fi
        fi
        
        # Extract RU information from comments
        if echo "$header_info" | grep -qi "RU LiteON"; then
            ru="LiteON"
        elif echo "$header_info" | grep -qi "O-RAN"; then
            ru="O-RAN RU"
        elif [[ "$config_file" == *"liteon"* ]]; then
            ru="LiteON"
        elif grep -q "ru_ofh:" "$config_file"; then
            ru="O-RAN RU"
        else
            ru="Software"
        fi
        
        # Extract band from comments
        local band_comment=$(echo "$header_info" | grep -i "band" | head -1)
        if [[ "$band_comment" =~ [Bb]and[[:space:]]+([nN]?[0-9]+) ]]; then
            band="${BASH_REMATCH[1]}"
            [[ "$band" != n* ]] && band="n$band"
        else
            # Fallback to YAML content
            band=$(grep "band:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "Unknown")
            if [ "$band" != "Unknown" ]; then
                band="n$band"
            fi
        fi
        
        # Extract bandwidth from comments
        local bw_comment=$(echo "$header_info" | grep -i "MHz" | head -1)
        if [[ "$bw_comment" =~ ([0-9]+)[[:space:]]*MHz ]]; then
            bandwidth="${BASH_REMATCH[1]}MHz"
        else
            # Fallback to YAML content
            bandwidth=$(grep "channel_bandwidth_MHz:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "Unknown")
            if [ "$bandwidth" != "Unknown" ]; then
                bandwidth="${bandwidth}MHz"
            fi
        fi
        
        # Extract antenna configuration from comments
        local ant_comment=$(echo "$header_info" | grep -i "MIMO\|antenna" | head -1)
        if [[ "$ant_comment" =~ MIMO[[:space:]]+([0-9]+)x([0-9]+) ]]; then
            antennas="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
        else
            # Fallback to YAML content
            local dl_ant=$(grep "nof_antennas_dl:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "0")
            local ul_ant=$(grep "nof_antennas_ul:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "0")
            if [ "$dl_ant" != "0" ] && [ "$ul_ant" != "0" ]; then
                antennas="${dl_ant}x${ul_ant}"
            fi
        fi
        
        # Extract DPDK information from comments
        if echo "$header_info" | grep -qi "DPDK"; then
            dpdk="Yes"
        elif grep -q "eal_args:" "$config_file"; then
            dpdk="Yes"
        else
            dpdk="No"
        fi
    fi
    
    echo "$mode|$ru|$band|$bandwidth|$antennas|$dpdk"
}

# Show predefined configurations table
show_predefined_configs() {
    local predefined_dir="/etc/srsran/pre-defined-configs"
    
    log_header "Available Predefined Configurations"
    
    if [ ! -d "$predefined_dir" ]; then
        log_warn "Predefined configurations directory not found: $predefined_dir"
        return 1
    fi
    
    local configs=()
    local config_details=()
    local index=1
    
    # Find all YAML configuration files
    while IFS= read -r -d '' config_file; do
        local filename=$(basename "$config_file")
        configs+=("$config_file")
        local details=$(extract_config_details "$config_file")
        config_details+=("$details")
    done < <(find "$predefined_dir" -name "*.yaml" -print0 2>/dev/null)
    
    if [ ${#configs[@]} -eq 0 ]; then
        log_warn "No predefined configuration files found in $predefined_dir"
        return 1
    fi
    
    # Print table header
    printf "${CYAN}%-3s %-35s %-12s %-10s %-8s %-12s %-8s %-6s${NC}\n" "#" "Configuration File" "Mode" "RU Type" "Band" "Bandwidth" "Antennas" "DPDK"
    printf "${CYAN}%-3s %-35s %-12s %-10s %-8s %-12s %-8s %-6s${NC}\n" "---" "-----------------------------------" "------------" "----------" "--------" "------------" "--------" "------"
    
    # Print table rows
    for i in "${!configs[@]}"; do
        local filename=$(basename "${configs[$i]}")
        IFS='|' read -r mode ru band bandwidth antennas dpdk <<< "${config_details[$i]}"
        printf "${WHITE}%-3d${NC} %-35s %-12s %-10s %-8s %-12s %-8s %-6s\n" "$((i+1))" "$filename" "$mode" "$ru" "$band" "$bandwidth" "$antennas" "$dpdk"
    done
    
    echo ""
    return 0
}

# Apply predefined configuration
apply_predefined_config() {
    local predefined_dir="/etc/srsran/pre-defined-configs"
    local configs=()
    
    # Find all YAML configuration files
    while IFS= read -r -d '' config_file; do
        configs+=("$config_file")
    done < <(find "$predefined_dir" -name "*.yaml" -print0 2>/dev/null)
    
    if [ ${#configs[@]} -eq 0 ]; then
        log_error "No predefined configurations available"
        return 1
    fi
    
    echo -e "${YELLOW}Select a predefined configuration (1-${#configs[@]}) or 0 for custom: ${NC}"
    read -r selection
    
    if [ "$selection" = "0" ]; then
        log_info "Custom configuration selected"
        log_warn "For custom configuration, you have two options:"
        log_config "  1. Modify context variables and run: /etc/one-appliance/service configure"
        log_config "  2. Manually edit the configuration file and restart the service"
        echo ""
        log_info "Available context variables:"
        log_config "  - ONEAPP_SRSRAN_MODE (gnb, cu, du)"
        log_config "  - ONEAPP_SRSRAN_MCC (Mobile Country Code)"
        log_config "  - ONEAPP_SRSRAN_MNC (Mobile Network Code)"
        log_config "  - ONEAPP_SRSRAN_TAC (Tracking Area Code)"
        log_config "  - ONEAPP_SRSRAN_PCI (Physical Cell Identity)"
        log_config "  - ONEAPP_SRSRAN_DL_ARFCN (Downlink ARFCN)"
        log_config "  - ONEAPP_SRSRAN_BAND (NR Band, e.g., n77)"
        log_config "  - ONEAPP_SRSRAN_CHANNEL_BW_MHZ (Channel Bandwidth)"
        log_config "  - ONEAPP_SRSRAN_ENABLE_DPDK (yes/no)"
        echo ""
        log_info "To modify context variables: edit /var/lib/one-context/one_env and run configuration"
        log_info "To manually edit config: modify files in /etc/srsran/ and restart the service"
        return 0
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#configs[@]} ]; then
        local selected_config="${configs[$((selection-1))]}"
        local filename=$(basename "$selected_config")
        
        log_step "Applying predefined configuration: $filename"
        
        # Determine target configuration file based on current mode
        local current_mode=$(get_current_mode)
        local target_config=""
        
        case "$current_mode" in
            "gnb") target_config="/etc/srsran/gnb.yaml" ;;
            "cu") target_config="/etc/srsran/cu.yaml" ;;
            "du") target_config="/etc/srsran/du.yaml" ;;
            *) target_config="/etc/srsran/gnb.yaml" ;;
        esac
        
        # Backup current configuration
        if [ -f "$target_config" ]; then
            cp "$target_config" "${target_config}.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "Current configuration backed up"
        fi
        
        # Copy predefined configuration
        if cp "$selected_config" "$target_config"; then
            log_info "✓ Configuration applied successfully"
            log_info "Configuration file: $target_config"
            log_warn "Note: You may need to adjust network interfaces and addresses for your environment"
            return 0
        else
            log_error "✗ Failed to apply configuration"
            return 1
        fi
    else
        log_error "Invalid selection: $selection"
        return 1
    fi
}

# Prompt for configuration changes
prompt_config_change() {
    echo -e "${YELLOW}Do you want to modify the configuration? (y/n): ${NC}"
    read -r choice
    case $choice in
        [Yy]*)
            log_step "Configuration modification"
            
            # Show predefined configurations table
            if show_predefined_configs; then
                echo -e "${YELLOW}Do you want to use a predefined configuration? (y/n): ${NC}"
                read -r predefined_choice
                case $predefined_choice in
                    [Yy]*)
                        apply_predefined_config
                        ;;
                    *)
                        log_info "Using custom configuration"
                        log_warn "For custom configuration, you have two options:"
                        log_config "  1. Modify context variables and run: /etc/one-appliance/service configure"
                        log_config "  2. Manually edit the configuration file and restart the service"
                        echo ""
                        log_info "Available context variables:"
                        log_config "  - ONEAPP_SRSRAN_MODE (gnb, cu, du)"
                        log_config "  - ONEAPP_SRSRAN_MCC (Mobile Country Code)"
                        log_config "  - ONEAPP_SRSRAN_MNC (Mobile Network Code)"
                        log_config "  - ONEAPP_SRSRAN_TAC (Tracking Area Code)"
                        log_config "  - ONEAPP_SRSRAN_PCI (Physical Cell Identity)"
                        log_config "  - ONEAPP_SRSRAN_DL_ARFCN (Downlink ARFCN)"
                        log_config "  - ONEAPP_SRSRAN_BAND (NR Band, e.g., n77)"
                        log_config "  - ONEAPP_SRSRAN_CHANNEL_BW_MHZ (Channel Bandwidth)"
                        log_config "  - ONEAPP_SRSRAN_ENABLE_DPDK (yes/no)"
                        echo ""
                        log_info "To modify context variables: edit /var/lib/one-context/one_env and run configuration"
                        log_info "To manually edit config: modify files in /etc/srsran/ and restart the service"
                        ;;
                esac
            else
                log_warn "Falling back to custom configuration options"
                log_info "Available configuration parameters:"
                log_config "  - ONEAPP_SRSRAN_MODE (gnb, cu, du)"
                log_config "  - ONEAPP_SRSRAN_MCC (Mobile Country Code)"
                log_config "  - ONEAPP_SRSRAN_MNC (Mobile Network Code)"
                log_config "  - ONEAPP_SRSRAN_TAC (Tracking Area Code)"
                log_config "  - ONEAPP_SRSRAN_PCI (Physical Cell Identity)"
                log_config "  - ONEAPP_SRSRAN_DL_ARFCN (Downlink ARFCN)"
                log_config "  - ONEAPP_SRSRAN_BAND (NR Band, e.g., n77)"
                log_config "  - ONEAPP_SRSRAN_CHANNEL_BW_MHZ (Channel Bandwidth)"
                log_config "  - ONEAPP_SRSRAN_ENABLE_DPDK (yes/no)"
                echo ""
                log_info "To modify, edit /var/lib/one-context/one_env and run configuration"
            fi
            ;;
        *)
            log_info "Proceeding with current configuration"
            ;;
    esac
}

# Start service
start_service() {
    local service_name="$1"
    
    log_step "Starting $service_name"
    if systemctl start "$service_name"; then
        log_info "✓ $service_name started successfully"
        log_info "View logs with: journalctl -u $service_name -f"
        log_info "Check status with: systemctl status $service_name"
    else
        log_error "✗ Failed to start $service_name"
        log_info "Check logs with: journalctl -u $service_name -n 50"
        return 1
    fi
}

# Restart service
restart_service() {
    local service_name="$1"
    
    log_step "Restarting $service_name"
    if systemctl restart "$service_name"; then
        log_info "✓ $service_name restarted successfully"
        log_info "View logs with: journalctl -u $service_name -f"
    else
        log_error "✗ Failed to restart $service_name"
        log_info "Check logs with: journalctl -u $service_name -n 50"
        return 1
    fi
}

# Main function
main() {
    log_header "srsRAN Project Service Manager - Start"
    
    # Get current mode and service name
    local current_mode=$(get_current_mode)
    local service_name=$(get_service_name "$current_mode")
    
    log_info "Current deployment mode: $current_mode"
    log_info "Service name: $service_name"
    echo ""
    
    # Check if service is running
    if is_service_running "$service_name"; then
        log_warn "Service $service_name is already running"
        echo -e "${YELLOW}Do you want to restart it? (y/n): ${NC}"
        read -r choice
        case $choice in
            [Yy]*)
                show_current_config
                prompt_config_change
                restart_service "$service_name"
                ;;
            *)
                log_info "Service start cancelled"
                exit 0
                ;;
        esac
    else
        log_info "Service $service_name is not running"
        echo -e "${YELLOW}Do you want to start it? (y/n): ${NC}"
        read -r choice
        case $choice in
            [Yy]*)
                show_current_config
                prompt_config_change
                start_service "$service_name"
                ;;
            *)
                log_info "Service start cancelled"
                exit 0
                ;;
        esac
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Run main function
main "$@"