#!/bin/bash

# srsRAN Project Configuration Display Script
# Shows current configuration in a formatted, easy-to-read manner

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration paths
SRSRAN_CONFIG_DIR="/etc/srsran"
ONE_SERVICE_REPORT="/etc/one-appliance/config"
CONTEXT_ENV="/var/lib/one-context/one_env"

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

log_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

log_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

log_config() {
    echo -e "${MAGENTA}$1${NC}"
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

log_value() {
    echo -e "${BOLD}$1:${NC} $2"
}

log_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "running")
            echo -e "🟢 ${GREEN}$message${NC}"
            ;;
        "stopped")
            echo -e "🔴 ${RED}$message${NC}"
            ;;
        "enabled")
            echo -e "✅ ${GREEN}$message${NC}"
            ;;
        "disabled")
            echo -e "❌ ${YELLOW}$message${NC}"
            ;;
        *)
            echo -e "ℹ️  ${BLUE}$message${NC}"
            ;;
    esac
}

# Get value from context environment
get_context_value() {
    local key="$1"
    local default="$2"
    
    if [ -f "$CONTEXT_ENV" ]; then
        grep "^$key=" "$CONTEXT_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "$default"
    else
        echo "$default"
    fi
}

# Get current srsRAN mode
get_current_mode() {
    get_context_value "ONEAPP_SRSRAN_MODE" "gnb"
}

# Get service name based on mode
get_service_name() {
    local mode="$1"
    case "$mode" in
        "gnb") echo "srsran-gnb" ;;
        "cu") echo "srsran-cu" ;;
        "du") echo "srsran-du" ;;
        *) echo "srsran-gnb" ;;
    esac
}

# Check if service is running
is_service_running() {
    local service_name="$1"
    systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Check if service is enabled
is_service_enabled() {
    local service_name="$1"
    systemctl is-enabled --quiet "$service_name" 2>/dev/null
}

# Display service status
show_service_status() {
    log_section "Service Status"
    
    local current_mode=$(get_current_mode)
    local service_name=$(get_service_name "$current_mode")
    
    log_value "Current Mode" "$current_mode"
    log_value "Primary Service" "$service_name"
    echo ""
    
    # Check all srsRAN services
    local services=("srsran-gnb" "srsran-cu" "srsran-du")
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            local running_status="stopped"
            local enabled_status="disabled"
            
            if is_service_running "$service"; then
                running_status="running"
            fi
            
            if is_service_enabled "$service"; then
                enabled_status="enabled"
            fi
            
            echo -n "  $service: "
            log_status "$running_status" "$running_status"
            echo -n "    Auto-start: "
            log_status "$enabled_status" "$enabled_status"
        fi
    done
    echo ""
}

# Display network configuration
show_network_config() {
    log_section "Network Configuration"
    
    log_value "Mobile Country Code (MCC)" "$(get_context_value 'ONEAPP_SRSRAN_MCC' '999')"
    log_value "Mobile Network Code (MNC)" "$(get_context_value 'ONEAPP_SRSRAN_MNC' '75')"
    log_value "Tracking Area Code (TAC)" "$(get_context_value 'ONEAPP_SRSRAN_TAC' '1')"
    log_value "Physical Cell Identity (PCI)" "$(get_context_value 'ONEAPP_SRSRAN_PCI' '69')"
    echo ""
}

# Display radio configuration
show_radio_config() {
    log_section "Radio Configuration"
    
    log_value "NR Band" "$(get_context_value 'ONEAPP_SRSRAN_BAND' 'n77')"
    log_value "Downlink ARFCN" "$(get_context_value 'ONEAPP_SRSRAN_DL_ARFCN' '656668')"
    log_value "Channel Bandwidth" "$(get_context_value 'ONEAPP_SRSRAN_CHANNEL_BW_MHZ' '100') MHz"
    log_value "Common Subcarrier Spacing" "$(get_context_value 'ONEAPP_SRSRAN_COMMON_SCS' '30') kHz"
    log_value "Number of NR Cells" "$(get_context_value 'ONEAPP_SRSRAN_NR_CELLS' '1')"
    echo ""
}

# Display performance configuration
show_performance_config() {
    log_section "Performance Configuration"
    
    local dpdk_enabled=$(get_context_value 'ONEAPP_SRSRAN_ENABLE_DPDK' 'no')
    log_value "DPDK Support" "$dpdk_enabled"
    
    if [ "$dpdk_enabled" = "yes" ]; then
        log_info "DPDK is enabled for high-performance packet processing"
        if [ -d "/usr/local/srsran-dpdk" ]; then
            log_status "info" "DPDK installation found at /usr/local/srsran-dpdk"
        else
            log_warn "DPDK enabled but installation not found"
        fi
    else
        log_info "Using standard packet processing (DPDK disabled)"
    fi
    echo ""
}

# Display file locations
show_file_locations() {
    log_section "File Locations"
    
    log_value "Configuration Directory" "$SRSRAN_CONFIG_DIR"
    log_value "Log Directory" "/var/log/srsran"
    log_value "Data Directory" "/opt/srsran"
    log_value "Binary Location (Base)" "/usr/local/srsran/bin"
    
    if [ -d "/usr/local/srsran-dpdk" ]; then
        log_value "Binary Location (DPDK)" "/usr/local/srsran-dpdk/bin"
    fi
    
    echo ""
    
    # Check if configuration files exist
    log_info "Configuration Files:"
    local config_files=("gnb.conf" "cu_cp.conf" "cu_up.conf" "du.conf")
    
    for config_file in "${config_files[@]}"; do
        local full_path="$SRSRAN_CONFIG_DIR/$config_file"
        if [ -f "$full_path" ]; then
            log_status "info" "✓ $full_path ($(stat -c%s "$full_path" 2>/dev/null || echo '?') bytes)"
        else
            log_status "info" "✗ $full_path (not found)"
        fi
    done
    echo ""
}

# Display version information
show_version_info() {
    log_section "Version Information"
    
    log_value "srsRAN Project Version" "$(get_context_value 'SRSRAN_VERSION' 'release_24_10_1')"
    
    # Try to get actual binary version
    local current_mode=$(get_current_mode)
    local dpdk_enabled=$(get_context_value 'ONEAPP_SRSRAN_ENABLE_DPDK' 'no')
    
    if [ "$dpdk_enabled" = "yes" ] && [ -f "/usr/local/srsran-dpdk/bin/gnb" ]; then
        local version_output=$(timeout 5 /usr/local/srsran-dpdk/bin/gnb --version 2>/dev/null | head -1 || echo "Version check failed")
        log_value "Active Binary Version (DPDK)" "$version_output"
    elif [ -f "/usr/local/srsran/bin/gnb" ]; then
        local version_output=$(timeout 5 /usr/local/srsran/bin/gnb --version 2>/dev/null | head -1 || echo "Version check failed")
        log_value "Active Binary Version (Base)" "$version_output"
    else
        log_warn "No srsRAN binaries found"
    fi
    echo ""
}

# Display management commands
show_management_commands() {
    log_section "Management Commands"
    
    local current_mode=$(get_current_mode)
    local service_name=$(get_service_name "$current_mode")
    
    log_info "Service Management:"
    log_config "  sudo systemctl start $service_name     # Start service"
    log_config "  sudo systemctl stop $service_name      # Stop service"
    log_config "  sudo systemctl restart $service_name   # Restart service"
    log_config "  sudo systemctl status $service_name    # Check status"
    echo ""
    
    log_info "Log Monitoring:"
    log_config "  sudo journalctl -u $service_name -f   # Follow logs"
    log_config "  sudo journalctl -u $service_name -n 50 # Last 50 lines"
    echo ""
    
    log_info "Configuration:"
    log_config "  sudo /etc/one-appliance/service configure  # Reconfigure"
    log_config "  sudo nano $SRSRAN_CONFIG_DIR/gnb.conf      # Edit config"
    echo ""
    
    log_info "Quick Scripts:"
    log_config "  sudo /usr/local/bin/start.sh           # Interactive start"
    log_config "  sudo /usr/local/bin/stop.sh            # Interactive stop"
    log_config "  sudo /usr/local/bin/show_configuration.sh # This script"
    echo ""
}

# Show predefined configurations
show_predefined_configs() {
    local predefined_dir="/etc/srsran/pre-defined-configs"
    
    log_section "Available Predefined Configurations"
    
    if [ ! -d "$predefined_dir" ]; then
        log_warn "Predefined configurations directory not found: $predefined_dir"
        return 1
    fi
    
    local configs=()
    local config_details=()
    
    # Find all YAML configuration files
    while IFS= read -r -d '' config_file; do
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
    log_info "To use a predefined configuration, run: sudo /usr/local/bin/start.sh"
    echo ""
}

# Display service report if available
show_service_report() {
    if [ -f "$ONE_SERVICE_REPORT" ]; then
        log_section "Service Report"
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                echo -e "${CYAN}$line${NC}"
            elif [[ "$line" =~ ^[A-Za-z] ]]; then
                log_config "  $line"
            else
                echo "$line"
            fi
        done < "$ONE_SERVICE_REPORT"
        echo ""
    fi
}

# Main function
main() {
    log_header "srsRAN Project Configuration Overview"
    
    show_service_status
    show_network_config
    show_radio_config
    show_performance_config
    show_version_info
    show_file_locations
    show_predefined_configs
    show_management_commands
    show_service_report
    
    log_header "Configuration Display Complete"
}

# Run main function
main "$@"