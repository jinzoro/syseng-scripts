#!/bin/bash

# System Maintenance Script
# Usage: ./system_maintenance.sh [--update] [--cleanup] [--optimize] [--reboot-if-needed]

set -euo pipefail

# Default values
UPDATE_SYSTEM=false
CLEANUP_SYSTEM=false
OPTIMIZE_SYSTEM=false
REBOOT_IF_NEEDED=false
DRY_RUN=false
MAINTENANCE_LOG="/var/log/maintenance.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --update)
            UPDATE_SYSTEM=true
            shift
            ;;
        --cleanup)
            CLEANUP_SYSTEM=true
            shift
            ;;
        --optimize)
            OPTIMIZE_SYSTEM=true
            shift
            ;;
        --reboot-if-needed)
            REBOOT_IF_NEEDED=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --log)
            MAINTENANCE_LOG="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [options]

Options:
  --update              Update system packages
  --cleanup             Clean up temporary files and caches
  --optimize            Optimize system performance
  --reboot-if-needed    Reboot system if required after updates
  --dry-run             Show what would be done without executing
  --log FILE            Maintenance log file (default: /var/log/maintenance.log)
  -h, --help           Show this help message

Examples:
  $0 --update --cleanup
  $0 --optimize --reboot-if-needed
  $0 --update --cleanup --optimize --reboot-if-needed
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$timestamp - $message" | tee -a "$MAINTENANCE_LOG"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Check system before maintenance
pre_maintenance_check() {
    log_message "${BLUE}Performing pre-maintenance checks...${NC}"
    
    # Check available disk space
    local root_usage
    root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $root_usage -gt 90 ]]; then
        log_message "${RED}Warning: Root filesystem is ${root_usage}% full${NC}"
        log_message "Consider freeing up space before maintenance"
    fi
    
    # Check system load
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | cut -d',' -f1)
    local cpu_cores
    cpu_cores=$(nproc)
    
    if (( $(echo "$load_avg > $cpu_cores" | bc -l) )); then
        log_message "${YELLOW}Warning: High system load detected: $load_avg${NC}"
    fi
    
    # Check if system needs reboot
    if [[ -f /var/run/reboot-required ]]; then
        log_message "${YELLOW}System reboot is required${NC}"
    fi
    
    log_message "${GREEN}Pre-maintenance checks completed${NC}"
}

# Update system packages
update_system() {
    log_message "${BLUE}Starting system update...${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "[DRY RUN] Would update system packages"
        dnf check-update
        return
    fi
    
    # Update package cache
    log_message "Updating package cache..."
    dnf clean all
    dnf makecache
    
    # Check for available updates
    log_message "Checking for available updates..."
    local update_count
    update_count=$(dnf list updates 2>/dev/null | grep -c "updates" || echo "0")
    
    if [[ $update_count -gt 0 ]]; then
        log_message "Found $update_count available updates"
        
        # Perform update
        log_message "Installing updates..."
        if dnf update -y; then
            log_message "${GREEN}System update completed successfully${NC}"
        else
            log_message "${RED}System update failed${NC}"
            return 1
        fi
        
        # Check if reboot is required
        if [[ -f /var/run/reboot-required ]]; then
            log_message "${YELLOW}Reboot required after updates${NC}"
        fi
    else
        log_message "${GREEN}System is already up to date${NC}"
    fi
}

# Clean up system
cleanup_system() {
    log_message "${BLUE}Starting system cleanup...${NC}"
    
    local cleaned_space=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "[DRY RUN] Would perform system cleanup"
        return
    fi
    
    # Clean package cache
    log_message "Cleaning package cache..."
    local cache_size_before
    cache_size_before=$(du -s /var/cache/dnf 2>/dev/null | cut -f1 || echo "0")
    
    dnf clean all
    
    local cache_size_after
    cache_size_after=$(du -s /var/cache/dnf 2>/dev/null | cut -f1 || echo "0")
    local cache_cleaned=$((cache_size_before - cache_size_after))
    cleaned_space=$((cleaned_space + cache_cleaned))
    
    log_message "Package cache cleaned: $(numfmt --to=iec $((cache_cleaned * 1024)))"
    
    # Clean temporary files
    log_message "Cleaning temporary files..."
    local temp_size_before
    temp_size_before=$(du -s /tmp /var/tmp 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
    
    local temp_size_after
    temp_size_after=$(du -s /tmp /var/tmp 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    local temp_cleaned=$((temp_size_before - temp_size_after))
    cleaned_space=$((cleaned_space + temp_cleaned))
    
    log_message "Temporary files cleaned: $(numfmt --to=iec $((temp_cleaned * 1024)))"
    
    # Clean old log files
    log_message "Cleaning old log files..."
    local log_size_before
    log_size_before=$(du -s /var/log 2>/dev/null | cut -f1 || echo "0")
    
    # Rotate logs if logrotate is available
    if command -v logrotate >/dev/null 2>&1; then
        logrotate -f /etc/logrotate.conf
    fi
    
    # Remove old compressed logs (older than 30 days)
    find /var/log -name "*.gz" -type f -mtime +30 -delete 2>/dev/null || true
    find /var/log -name "*.old" -type f -mtime +30 -delete 2>/dev/null || true
    
    local log_size_after
    log_size_after=$(du -s /var/log 2>/dev/null | cut -f1 || echo "0")
    local log_cleaned=$((log_size_before - log_size_after))
    cleaned_space=$((cleaned_space + log_cleaned))
    
    log_message "Old log files cleaned: $(numfmt --to=iec $((log_cleaned * 1024)))"
    
    # Clean user caches
    log_message "Cleaning user caches..."
    local cache_dirs=("/home/*/.cache" "/root/.cache")
    
    for cache_pattern in "${cache_dirs[@]}"; do
        for cache_dir in $cache_pattern; do
            if [[ -d "$cache_dir" ]]; then
                find "$cache_dir" -type f -atime +30 -delete 2>/dev/null || true
            fi
        done
    done
    
    # Clean journal logs
    if command -v journalctl >/dev/null 2>&1; then
        log_message "Cleaning journal logs older than 30 days..."
        journalctl --vacuum-time=30d
    fi
    
    # Remove orphaned packages
    log_message "Removing orphaned packages..."
    if command -v dnf >/dev/null 2>&1; then
        dnf autoremove -y
    fi
    
    log_message "${GREEN}System cleanup completed. Total space freed: $(numfmt --to=iec $((cleaned_space * 1024)))${NC}"
}

# Optimize system performance
optimize_system() {
    log_message "${BLUE}Starting system optimization...${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "[DRY RUN] Would optimize system performance"
        return
    fi
    
    # Update locate database
    if command -v updatedb >/dev/null 2>&1; then
        log_message "Updating locate database..."
        updatedb
    fi
    
    # Rebuild man-db
    if command -v mandb >/dev/null 2>&1; then
        log_message "Rebuilding man database..."
        mandb -q
    fi
    
    # Optimize package database
    log_message "Optimizing package database..."
    if command -v dnf >/dev/null 2>&1; then
        dnf makecache
    fi
    
    # Defragment if using ext4 (careful operation)
    log_message "Checking filesystem fragmentation..."
    local root_fs
    root_fs=$(df -T / | awk 'NR==2 {print $2}')
    
    if [[ "$root_fs" == "ext4" ]]; then
        if command -v e4defrag >/dev/null 2>&1; then
            log_message "Running filesystem optimization..."
            e4defrag -c / 2>/dev/null || log_message "Filesystem defragmentation not needed"
        fi
    fi
    
    # Clear swap if available and not heavily used
    local swap_usage
    swap_usage=$(free | awk '/Swap:/ {if($2>0) print int($3/$2*100); else print 0}')
    
    if [[ $swap_usage -lt 10 && $swap_usage -gt 0 ]]; then
        log_message "Optimizing swap usage..."
        swapoff -a && swapon -a
    fi
    
    # Sync filesystems
    log_message "Syncing filesystems..."
    sync
    
    log_message "${GREEN}System optimization completed${NC}"
}

# Generate maintenance report
generate_report() {
    log_message "${BLUE}Generating maintenance report...${NC}"
    
    local report_file="/tmp/maintenance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "System Maintenance Report"
        echo "========================"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        
        echo "System Information:"
        echo "==================="
        echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "Kernel: $(uname -r)"
        echo "Uptime: $(uptime -p)"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo ""
        
        echo "Disk Usage:"
        echo "==========="
        df -h | grep -E '^/dev'
        echo ""
        
        echo "Memory Usage:"
        echo "============="
        free -h
        echo ""
        
        echo "Service Status:"
        echo "==============="
        systemctl list-units --failed --no-pager
        echo ""
        
        echo "Recent Errors (last 24 hours):"
        echo "==============================="
        journalctl --since "24 hours ago" --priority=3 --no-pager | tail -20
        echo ""
        
        echo "Security Updates:"
        echo "================="
        if command -v dnf >/dev/null 2>&1; then
            dnf updateinfo list security | wc -l | xargs echo "Available security updates:"
        fi
        
    } > "$report_file"
    
    log_message "Maintenance report saved to: $report_file"
}

# Reboot system if needed
check_reboot_needed() {
    if [[ "$REBOOT_IF_NEEDED" == "true" ]]; then
        if [[ -f /var/run/reboot-required ]]; then
            log_message "${YELLOW}System reboot is required${NC}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_message "[DRY RUN] Would reboot system"
                return
            fi
            
            log_message "Scheduling system reboot in 1 minute..."
            shutdown -r +1 "System maintenance completed. Rebooting for updates to take effect."
        else
            log_message "${GREEN}No reboot required${NC}"
        fi
    fi
}

# Main execution
main() {
    log_message "${GREEN}Starting system maintenance${NC}"
    log_message "Update: $UPDATE_SYSTEM, Cleanup: $CLEANUP_SYSTEM, Optimize: $OPTIMIZE_SYSTEM"
    log_message "Reboot if needed: $REBOOT_IF_NEEDED, Dry run: $DRY_RUN"
    
    # Check if running as root (except for dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        check_root
    fi
    
    # Pre-maintenance checks
    pre_maintenance_check
    
    # Perform requested maintenance tasks
    if [[ "$UPDATE_SYSTEM" == "true" ]]; then
        update_system
    fi
    
    if [[ "$CLEANUP_SYSTEM" == "true" ]]; then
        cleanup_system
    fi
    
    if [[ "$OPTIMIZE_SYSTEM" == "true" ]]; then
        optimize_system
    fi
    
    # Generate report
    generate_report
    
    # Check if reboot is needed
    check_reboot_needed
    
    log_message "${GREEN}System maintenance completed successfully${NC}"
}

main "$@"
