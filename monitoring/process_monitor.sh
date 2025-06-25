#!/bin/bash

# Process Monitoring Script
# Usage: ./process_monitor.sh [--cpu-limit 90] [--memory-limit 90] [--kill] [--whitelist "process1,process2"]

set -euo pipefail

# Default values
CPU_LIMIT=90
MEMORY_LIMIT=90
KILL_MODE=false
WHITELIST=""
LOG_FILE="/var/log/process_monitor.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu-limit)
            CPU_LIMIT="$2"
            shift 2
            ;;
        --memory-limit)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --kill)
            KILL_MODE=true
            shift
            ;;
        --whitelist)
            WHITELIST="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--cpu-limit 90] [--memory-limit 90] [--kill] [--whitelist 'process1,process2']"
            echo "  --cpu-limit: CPU usage threshold (default: 90%)"
            echo "  --memory-limit: Memory usage threshold (default: 90%)"
            echo "  --kill: Actually kill processes (default: just report)"
            echo "  --whitelist: Comma-separated list of processes to never kill"
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
NC='\033[0m'

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if process is whitelisted
is_whitelisted() {
    local process_name="$1"
    if [[ -z "$WHITELIST" ]]; then
        return 1
    fi
    
    IFS=',' read -ra WHITELIST_ARRAY <<< "$WHITELIST"
    for whitelisted in "${WHITELIST_ARRAY[@]}"; do
        if [[ "$process_name" == *"$whitelisted"* ]]; then
            return 0
        fi
    done
    return 1
}

# Find high CPU processes
find_high_cpu_processes() {
    echo "Checking for high CPU usage processes (>${CPU_LIMIT}%)..."
    
    # Get processes with high CPU usage
    ps aux --sort=-%cpu | awk -v limit="$CPU_LIMIT" '
        NR > 1 && $3 > limit {
            printf "%s|%s|%.1f|%.1f|%s\n", $2, $1, $3, $4, $11
        }
    ' | while IFS='|' read -r pid user cpu_usage mem_usage command; do
        
        if is_whitelisted "$command"; then
            echo -e "  PID $pid ($command): ${YELLOW}HIGH CPU ${cpu_usage}% - WHITELISTED${NC}"
            log_message "High CPU process whitelisted: PID $pid ($command) - CPU: ${cpu_usage}%"
        else
            echo -e "  PID $pid ($command): ${RED}HIGH CPU ${cpu_usage}%${NC}"
            log_message "High CPU process detected: PID $pid ($command) - CPU: ${cpu_usage}%"
            
            if [[ "$KILL_MODE" == "true" ]]; then
                echo "    Attempting to kill process $pid..."
                if kill -TERM "$pid" 2>/dev/null; then
                    echo -e "    ${GREEN}Process $pid terminated${NC}"
                    log_message "Killed high CPU process: PID $pid ($command)"
                    sleep 2
                    # Check if process still exists, force kill if necessary
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -KILL "$pid" 2>/dev/null
                        echo -e "    ${RED}Process $pid force killed${NC}"
                        log_message "Force killed stubborn process: PID $pid ($command)"
                    fi
                else
                    echo -e "    ${RED}Failed to kill process $pid${NC}"
                    log_message "Failed to kill process: PID $pid ($command)"
                fi
            fi
        fi
    done
}

# Find high memory processes
find_high_memory_processes() {
    echo "Checking for high memory usage processes (>${MEMORY_LIMIT}%)..."
    
    # Get total system memory
    local total_mem
    total_mem=$(free -m | awk 'NR==2{print $2}')
    
    # Get processes with high memory usage
    ps aux --sort=-%mem | awk -v limit="$MEMORY_LIMIT" -v total="$total_mem" '
        NR > 1 && $4 > limit {
            mem_mb = ($4 * total) / 100
            printf "%s|%s|%.1f|%.1f|%.0f|%s\n", $2, $1, $3, $4, mem_mb, $11
        }
    ' | while IFS='|' read -r pid user cpu_usage mem_percent mem_mb command; do
        
        if is_whitelisted "$command"; then
            echo -e "  PID $pid ($command): ${YELLOW}HIGH MEMORY ${mem_percent}% (${mem_mb}MB) - WHITELISTED${NC}"
            log_message "High memory process whitelisted: PID $pid ($command) - Memory: ${mem_percent}% (${mem_mb}MB)"
        else
            echo -e "  PID $pid ($command): ${RED}HIGH MEMORY ${mem_percent}% (${mem_mb}MB)${NC}"
            log_message "High memory process detected: PID $pid ($command) - Memory: ${mem_percent}% (${mem_mb}MB)"
            
            if [[ "$KILL_MODE" == "true" ]]; then
                echo "    Attempting to kill process $pid..."
                if kill -TERM "$pid" 2>/dev/null; then
                    echo -e "    ${GREEN}Process $pid terminated${NC}"
                    log_message "Killed high memory process: PID $pid ($command)"
                    sleep 2
                    # Check if process still exists, force kill if necessary
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -KILL "$pid" 2>/dev/null
                        echo -e "    ${RED}Process $pid force killed${NC}"
                        log_message "Force killed stubborn process: PID $pid ($command)"
                    fi
                else
                    echo -e "    ${RED}Failed to kill process $pid${NC}"
                    log_message "Failed to kill process: PID $pid ($command)"
                fi
            fi
        fi
    done
}

# Show top processes summary
show_top_processes() {
    echo ""
    echo "Top 10 processes by CPU usage:"
    ps aux --sort=-%cpu | head -11 | awk '
        NR==1 {print "  " $0}
        NR>1 {printf "  %-8s %-10s %6s %6s %s\n", $2, $1, $3"%", $4"%", $11}
    '
    
    echo ""
    echo "Top 10 processes by Memory usage:"
    ps aux --sort=-%mem | head -11 | awk '
        NR==1 {print "  " $0}
        NR>1 {printf "  %-8s %-10s %6s %6s %s\n", $2, $1, $3"%", $4"%", $11}
    '
}

# Main execution
main() {
    echo "========================================="
    echo "Process Monitor - $(date)"
    echo "Host: $(hostname)"
    echo "Thresholds: CPU ${CPU_LIMIT}%, Memory ${MEMORY_LIMIT}%"
    echo "Kill Mode: $KILL_MODE"
    [[ -n "$WHITELIST" ]] && echo "Whitelist: $WHITELIST"
    echo "========================================="
    
    find_high_cpu_processes
    echo ""
    find_high_memory_processes
    
    show_top_processes
    
    echo ""
    echo "========================================="
    log_message "Process monitoring completed"
}

main "$@"
