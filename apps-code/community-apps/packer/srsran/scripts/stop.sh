#!/bin/bash

# srsRAN Project Service Stop Script
# Provides interactive service stopping with status verification

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

# Get service status details
get_service_status() {
    local service_name="$1"
    local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    local enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")
    
    echo "Status: $status, Enabled: $enabled"
}

# Stop service
stop_service() {
    local service_name="$1"
    
    log_step "Stopping $service_name"
    if systemctl stop "$service_name"; then
        log_info "✓ $service_name stopped successfully"
        
        # Wait a moment and verify it's stopped
        sleep 2
        if ! is_service_running "$service_name"; then
            log_info "✓ Service confirmed stopped"
        else
            log_warn "Service may still be shutting down"
        fi
    else
        log_error "✗ Failed to stop $service_name"
        log_info "Check logs with: journalctl -u $service_name -n 50"
        return 1
    fi
}

# Stop all srsRAN services
stop_all_services() {
    local services=("srsran-gnb" "srsran-cu" "srsran-du")
    local stopped_count=0
    
    log_step "Stopping all srsRAN services"
    
    for service in "${services[@]}"; do
        if is_service_running "$service"; then
            log_info "Stopping $service..."
            if systemctl stop "$service" 2>/dev/null; then
                log_info "✓ $service stopped"
                ((stopped_count++))
            else
                log_warn "✗ Failed to stop $service"
            fi
        fi
    done
    
    if [ $stopped_count -eq 0 ]; then
        log_info "No srsRAN services were running"
    else
        log_info "✓ Stopped $stopped_count srsRAN service(s)"
    fi
}

# Show running services
show_running_services() {
    local services=("srsran-gnb" "srsran-cu" "srsran-du")
    local running_services=()
    
    log_step "Checking srsRAN service status"
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            local status=$(get_service_status "$service")
            if is_service_running "$service"; then
                log_info "🟢 $service - $status"
                running_services+=("$service")
            else
                log_info "🔴 $service - $status"
            fi
        fi
    done
    
    echo ""
    if [ ${#running_services[@]} -eq 0 ]; then
        log_info "No srsRAN services are currently running"
        return 1
    else
        log_info "Found ${#running_services[@]} running srsRAN service(s)"
        return 0
    fi
}

# Main function
main() {
    log_header "srsRAN Project Service Manager - Stop"
    
    # Show current service status
    if ! show_running_services; then
        log_info "Nothing to stop"
        exit 0
    fi
    
    # Get current mode and service name
    local current_mode=$(get_current_mode)
    local service_name=$(get_service_name "$current_mode")
    
    log_info "Current deployment mode: $current_mode"
    log_info "Primary service: $service_name"
    echo ""
    
    # Ask what to stop
    echo -e "${YELLOW}What would you like to stop?${NC}"
    echo "1) Current service only ($service_name)"
    echo "2) All srsRAN services"
    echo "3) Cancel"
    echo -e "${YELLOW}Enter your choice (1-3): ${NC}"
    read -r choice
    
    case $choice in
        1)
            if is_service_running "$service_name"; then
                echo -e "${YELLOW}Are you sure you want to stop $service_name? (y/n): ${NC}"
                read -r confirm
                case $confirm in
                    [Yy]*)
                        stop_service "$service_name"
                        ;;
                    *)
                        log_info "Operation cancelled"
                        ;;
                esac
            else
                log_warn "Service $service_name is not running"
            fi
            ;;
        2)
            echo -e "${YELLOW}Are you sure you want to stop ALL srsRAN services? (y/n): ${NC}"
            read -r confirm
            case $confirm in
                [Yy]*)
                    stop_all_services
                    ;;
                *)
                    log_info "Operation cancelled"
                    ;;
            esac
            ;;
        3)
            log_info "Operation cancelled"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please enter 1, 2, or 3"
            exit 1
            ;;
    esac
    
    echo ""
    log_info "Final status:"
    show_running_services || true
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Run main function
main "$@"