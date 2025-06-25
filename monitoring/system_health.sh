#!/bin/bash

# System Health Monitoring Script
# Usage: ./system_health.sh [--email recipient@domain.com] [--threshold 80]

set -euo pipefail

# Default values
EMAIL_RECIPIENT=""
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
LOG_FILE="/var/log/system_health.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL_RECIPIENT="$2"
            shift 2
            ;;
        --threshold)
            CPU_THRESHOLD="$2"
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--email recipient@domain.com] [--threshold 80]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Send alert function
send_alert() {
    local message="$1"
    log_message "ALERT: $message"
    
    if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "System Alert - $(hostname)" "$EMAIL_RECIPIENT"
    fi
}

# Check CPU usage
check_cpu() {
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    cpu_usage=${cpu_usage%.*} # Remove decimal part
    
    echo -n "CPU Usage: ${cpu_usage}% "
    
    if (( cpu_usage > CPU_THRESHOLD )); then
        echo -e "${RED}[CRITICAL]${NC}"
        send_alert "High CPU usage detected: ${cpu_usage}%"
        return 1
    elif (( cpu_usage > CPU_THRESHOLD - 10 )); then
        echo -e "${YELLOW}[WARNING]${NC}"
        return 0
    else
        echo -e "${GREEN}[OK]${NC}"
        return 0
    fi
}

# Check memory usage
check_memory() {
    local memory_info
    memory_info=$(free | grep Mem)
    local total=$(echo "$memory_info" | awk '{print $2}')
    local used=$(echo "$memory_info" | awk '{print $3}')
    local memory_usage=$((used * 100 / total))
    
    echo -n "Memory Usage: ${memory_usage}% "
    
    if (( memory_usage > MEMORY_THRESHOLD )); then
        echo -e "${RED}[CRITICAL]${NC}"
        send_alert "High memory usage detected: ${memory_usage}%"
        return 1
    elif (( memory_usage > MEMORY_THRESHOLD - 10 )); then
        echo -e "${YELLOW}[WARNING]${NC}"
        return 0
    else
        echo -e "${GREEN}[OK]${NC}"
        return 0
    fi
}

# Check disk usage
check_disk() {
    local status=0
    echo "Disk Usage:"
    
    while read -r line; do
        if [[ "$line" =~ ^/dev/ ]]; then
            local usage=$(echo "$line" | awk '{print $5}' | cut -d'%' -f1)
            local mount=$(echo "$line" | awk '{print $6}')
            
            echo -n "  $mount: ${usage}% "
            
            if (( usage > DISK_THRESHOLD )); then
                echo -e "${RED}[CRITICAL]${NC}"
                send_alert "High disk usage detected on $mount: ${usage}%"
                status=1
            elif (( usage > DISK_THRESHOLD - 10 )); then
                echo -e "${YELLOW}[WARNING]${NC}"
            else
                echo -e "${GREEN}[OK]${NC}"
            fi
        fi
    done < <(df -h)
    
    return $status
}

# Check system load
check_load() {
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | cut -d',' -f1)
    local cpu_cores
    cpu_cores=$(nproc)
    local load_percentage
    load_percentage=$(echo "$load_avg $cpu_cores" | awk '{printf "%.0f", ($1/$2)*100}')
    
    echo -n "System Load: ${load_avg} (${load_percentage}%) "
    
    if (( load_percentage > 100 )); then
        echo -e "${RED}[CRITICAL]${NC}"
        send_alert "High system load detected: ${load_avg} (${load_percentage}%)"
        return 1
    elif (( load_percentage > 80 )); then
        echo -e "${YELLOW}[WARNING]${NC}"
        return 0
    else
        echo -e "${GREEN}[OK]${NC}"
        return 0
    fi
}

# Check critical services
check_services() {
    local services=("sshd" "NetworkManager" "systemd-resolved")
    local status=0
    
    echo "Service Status:"
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "  $service: ${GREEN}[RUNNING]${NC}"
        else
            echo -e "  $service: ${RED}[STOPPED]${NC}"
            send_alert "Critical service $service is not running"
            status=1
        fi
    done
    
    return $status
}

# Main execution
main() {
    echo "========================================="
    echo "System Health Check - $(date)"
    echo "Host: $(hostname)"
    echo "========================================="
    
    local overall_status=0
    
    check_cpu || overall_status=1
    check_memory || overall_status=1
    check_disk || overall_status=1
    check_load || overall_status=1
    check_services || overall_status=1
    
    echo "========================================="
    
    if (( overall_status == 0 )); then
        echo -e "Overall Status: ${GREEN}[HEALTHY]${NC}"
        log_message "System health check completed - All systems normal"
    else
        echo -e "Overall Status: ${RED}[ISSUES DETECTED]${NC}"
        log_message "System health check completed - Issues detected"
    fi
    
    return $overall_status
}

main "$@"
