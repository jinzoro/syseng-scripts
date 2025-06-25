#!/bin/bash

# Log Management Script
# Usage: ./log_manager.sh [--rotate] [--analyze] [--cleanup] [--monitor] [--path /path/to/logs]

set -euo pipefail

# Default values
LOG_PATH="/var/log"
ROTATE_LOGS=false
ANALYZE_LOGS=false
CLEANUP_LOGS=false
MONITOR_LOGS=false
RETENTION_DAYS=30
SIZE_THRESHOLD="100M"
ERROR_THRESHOLD=10
EMAIL_ALERTS=""
COMPRESS_ROTATED=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            LOG_PATH="$2"
            shift 2
            ;;
        --rotate)
            ROTATE_LOGS=true
            shift
            ;;
        --analyze)
            ANALYZE_LOGS=true
            shift
            ;;
        --cleanup)
            CLEANUP_LOGS=true
            shift
            ;;
        --monitor)
            MONITOR_LOGS=true
            shift
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --size-threshold)
            SIZE_THRESHOLD="$2"
            shift 2
            ;;
        --error-threshold)
            ERROR_THRESHOLD="$2"
            shift 2
            ;;
        --email)
            EMAIL_ALERTS="$2"
            shift 2
            ;;
        --no-compress)
            COMPRESS_ROTATED=false
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [options]

Options:
  --path PATH             Log directory path (default: /var/log)
  --rotate                Rotate logs based on size
  --analyze               Analyze logs for errors and patterns
  --cleanup               Clean up old log files
  --monitor               Monitor logs in real-time
  --retention DAYS        Retention period in days (default: 30)
  --size-threshold SIZE   Size threshold for rotation (default: 100M)
  --error-threshold NUM   Error count threshold for alerts (default: 10)
  --email ADDRESS         Email address for alerts
  --no-compress           Disable compression of rotated logs
  -h, --help             Show this help message

Examples:
  $0 --analyze --path /var/log/myapp
  $0 --rotate --cleanup --retention 7
  $0 --monitor --email admin@company.com
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
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Convert size to bytes
size_to_bytes() {
    local size="$1"
    local unit="${size: -1}"
    local number="${size%?}"
    
    case "$unit" in
        K|k) echo $((number * 1024)) ;;
        M|m) echo $((number * 1024 * 1024)) ;;
        G|g) echo $((number * 1024 * 1024 * 1024)) ;;
        *) echo "$size" ;;
    esac
}

# Send alert email
send_alert() {
    local subject="$1"
    local message="$2"
    
    if [[ -n "$EMAIL_ALERTS" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$EMAIL_ALERTS"
        log_message "Alert sent to $EMAIL_ALERTS"
    fi
}

# Rotate log files
rotate_logs() {
    log_message "${BLUE}Starting log rotation...${NC}"
    
    local threshold_bytes
    threshold_bytes=$(size_to_bytes "$SIZE_THRESHOLD")
    local rotated_count=0
    
    find "$LOG_PATH" -name "*.log" -type f | while read -r log_file; do
        if [[ -f "$log_file" ]]; then
            local file_size
            file_size=$(stat -c%s "$log_file")
            
            if [[ $file_size -gt $threshold_bytes ]]; then
                local base_name="${log_file%.log}"
                local timestamp=$(date +%Y%m%d_%H%M%S)
                local rotated_name="${base_name}_${timestamp}.log"
                
                log_message "Rotating large log file: $log_file ($(numfmt --to=iec $file_size))"
                
                # Move current log to rotated name
                mv "$log_file" "$rotated_name"
                
                # Create new empty log file with same permissions
                touch "$log_file"
                chmod --reference="$rotated_name" "$log_file" 2>/dev/null || true
                chown --reference="$rotated_name" "$log_file" 2>/dev/null || true
                
                # Compress rotated log if enabled
                if [[ "$COMPRESS_ROTATED" == "true" ]]; then
                    gzip "$rotated_name"
                    log_message "Compressed rotated log: ${rotated_name}.gz"
                fi
                
                ((rotated_count++))
                
                # Send HUP signal to processes using the log file
                local processes
                processes=$(fuser "$log_file" 2>/dev/null | awk '{print $1}' || true)
                if [[ -n "$processes" ]]; then
                    for pid in $processes; do
                        kill -HUP "$pid" 2>/dev/null || true
                    done
                fi
            fi
        fi
    done
    
    log_message "${GREEN}Log rotation completed. Rotated $rotated_count files${NC}"
}

# Analyze logs for errors and patterns
analyze_logs() {
    log_message "${BLUE}Starting log analysis...${NC}"
    
    local analysis_report="/tmp/log_analysis_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Log Analysis Report"
        echo "==================="
        echo "Generated: $(date)"
        echo "Log Path: $LOG_PATH"
        echo ""
        
        # Find log files
        local log_files
        log_files=$(find "$LOG_PATH" -name "*.log" -type f | head -20)
        
        if [[ -z "$log_files" ]]; then
            echo "No log files found in $LOG_PATH"
            return
        fi
        
        # Error analysis
        echo "Error Analysis:"
        echo "==============="
        
        local total_errors=0
        while read -r log_file; do
            if [[ -f "$log_file" ]]; then
                local error_count
                error_count=$(grep -ci "error\|exception\|fail\|critical" "$log_file" 2>/dev/null || echo "0")
                
                if [[ $error_count -gt 0 ]]; then
                    echo "  $log_file: $error_count errors"
                    total_errors=$((total_errors + error_count))
                    
                    # Show recent errors
                    echo "    Recent errors:"
                    grep -i "error\|exception\|fail\|critical" "$log_file" | tail -3 | sed 's/^/      /'
                    echo ""
                fi
            fi
        done <<< "$log_files"
        
        echo "Total errors found: $total_errors"
        echo ""
        
        # Warning analysis
        echo "Warning Analysis:"
        echo "================"
        
        local total_warnings=0
        while read -r log_file; do
            if [[ -f "$log_file" ]]; then
                local warning_count
                warning_count=$(grep -ci "warn\|warning" "$log_file" 2>/dev/null || echo "0")
                
                if [[ $warning_count -gt 0 ]]; then
                    echo "  $log_file: $warning_count warnings"
                    total_warnings=$((total_warnings + warning_count))
                fi
            fi
        done <<< "$log_files"
        
        echo "Total warnings found: $total_warnings"
        echo ""
        
        # Size analysis
        echo "Size Analysis:"
        echo "=============="
        
        while read -r log_file; do
            if [[ -f "$log_file" ]]; then
                local file_size
                file_size=$(stat -c%s "$log_file")
                local human_size
                human_size=$(numfmt --to=iec "$file_size")
                echo "  $log_file: $human_size"
            fi
        done <<< "$log_files"
        
        echo ""
        
        # Top error patterns
        echo "Top Error Patterns:"
        echo "=================="
        
        grep -hi "error\|exception\|fail\|critical" $log_files 2>/dev/null | \
            sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//g' | \
            sed 's/[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}//g' | \
            sort | uniq -c | sort -nr | head -10 | \
            awk '{for(i=2;i<=NF;i++) printf "%s ", $i; printf "(%d occurrences)\n", $1}'
        
    } > "$analysis_report"
    
    # Display summary
    log_message "Analysis complete. Report saved to: $analysis_report"
    
    # Check if errors exceed threshold
    local total_errors
    total_errors=$(grep "Total errors found:" "$analysis_report" | awk '{print $4}')
    
    if [[ $total_errors -gt $ERROR_THRESHOLD ]]; then
        local alert_msg="High error count detected: $total_errors errors (threshold: $ERROR_THRESHOLD)"
        log_message "${RED}$alert_msg${NC}"
        send_alert "Log Analysis Alert" "$alert_msg"
    fi
    
    # Show summary
    echo ""
    echo "Analysis Summary:"
    grep -E "Total (errors|warnings) found:" "$analysis_report"
}

# Clean up old log files
cleanup_logs() {
    log_message "${BLUE}Starting log cleanup...${NC}"
    
    local cleaned_count=0
    local freed_space=0
    
    # Find and remove old log files
    while IFS= read -r -d '' old_file; do
        local file_size
        file_size=$(stat -c%s "$old_file")
        
        log_message "Removing old log file: $old_file ($(numfmt --to=iec $file_size))"
        rm "$old_file"
        
        ((cleaned_count++))
        freed_space=$((freed_space + file_size))
    done < <(find "$LOG_PATH" \( -name "*.log.*" -o -name "*.log.gz" \) -type f -mtime +$RETENTION_DAYS -print0)
    
    # Clean up empty directories
    find "$LOG_PATH" -type d -empty -delete 2>/dev/null || true
    
    local human_freed
    human_freed=$(numfmt --to=iec $freed_space)
    
    log_message "${GREEN}Cleanup completed. Removed $cleaned_count files, freed $human_freed${NC}"
}

# Monitor logs in real-time
monitor_logs() {
    log_message "${BLUE}Starting real-time log monitoring...${NC}"
    log_message "Monitoring path: $LOG_PATH"
    log_message "Press Ctrl+C to stop monitoring"
    
    # Find active log files
    local log_files
    log_files=$(find "$LOG_PATH" -name "*.log" -type f | head -10)
    
    if [[ -z "$log_files" ]]; then
        log_message "${YELLOW}No log files found to monitor${NC}"
        return
    fi
    
    # Start monitoring with tail
    # shellcheck disable=SC2086
    tail -f $log_files | while read -r line; do
        local timestamp=$(date '+%H:%M:%S')
        
        # Highlight errors and warnings
        if echo "$line" | grep -qi "error\|exception\|fail\|critical"; then
            echo -e "$timestamp ${RED}[ERROR]${NC} $line"
        elif echo "$line" | grep -qi "warn\|warning"; then
            echo -e "$timestamp ${YELLOW}[WARN]${NC} $line"
        else
            echo -e "$timestamp [INFO] $line"
        fi
    done
}

# Generate log statistics
generate_stats() {
    log_message "${BLUE}Generating log statistics...${NC}"
    
    local stats_file="/tmp/log_stats_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Log Statistics Report"
        echo "===================="
        echo "Generated: $(date)"
        echo "Log Path: $LOG_PATH"
        echo ""
        
        # Count files by type
        echo "File Count by Type:"
        echo "=================="
        find "$LOG_PATH" -type f | sed 's/.*\.//' | sort | uniq -c | sort -nr
        echo ""
        
        # Size distribution
        echo "Size Distribution:"
        echo "=================="
        find "$LOG_PATH" -name "*.log" -type f -exec stat -c%s {} \; | \
            awk '{
                if ($1 < 1024*1024) print "< 1MB"
                else if ($1 < 10*1024*1024) print "1-10MB" 
                else if ($1 < 100*1024*1024) print "10-100MB"
                else print "> 100MB"
            }' | sort | uniq -c
        echo ""
        
        # Age distribution
        echo "Age Distribution:"
        echo "================"
        find "$LOG_PATH" -name "*.log*" -type f -mtime +1 | wc -l | xargs echo "Older than 1 day:"
        find "$LOG_PATH" -name "*.log*" -type f -mtime +7 | wc -l | xargs echo "Older than 7 days:"
        find "$LOG_PATH" -name "*.log*" -type f -mtime +30 | wc -l | xargs echo "Older than 30 days:"
        
    } > "$stats_file"
    
    log_message "Statistics report saved to: $stats_file"
    cat "$stats_file"
}

# Main execution
main() {
    log_message "${GREEN}Log Manager Started${NC}"
    log_message "Log Path: $LOG_PATH"
    log_message "Retention: $RETENTION_DAYS days"
    log_message "Size Threshold: $SIZE_THRESHOLD"
    
    # Validate log path
    if [[ ! -d "$LOG_PATH" ]]; then
        log_message "${RED}Error: Log path does not exist: $LOG_PATH${NC}"
        exit 1
    fi
    
    # Execute requested operations
    if [[ "$ROTATE_LOGS" == "true" ]]; then
        rotate_logs
    fi
    
    if [[ "$ANALYZE_LOGS" == "true" ]]; then
        analyze_logs
    fi
    
    if [[ "$CLEANUP_LOGS" == "true" ]]; then
        cleanup_logs
    fi
    
    if [[ "$MONITOR_LOGS" == "true" ]]; then
        monitor_logs
    fi
    
    # If no specific action requested, show statistics
    if [[ "$ROTATE_LOGS" == "false" && "$ANALYZE_LOGS" == "false" && "$CLEANUP_LOGS" == "false" && "$MONITOR_LOGS" == "false" ]]; then
        generate_stats
    fi
    
    log_message "${GREEN}Log management operations completed${NC}"
}

main "$@"
