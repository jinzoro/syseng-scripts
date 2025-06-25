#!/bin/bash

# Certificate Expiration Monitor
# Monitors SSL/TLS certificates for expiration and sends alerts
# Version: 1.0
# Author: System Engineering Team

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
DEFAULT_WARN_DAYS=30
DEFAULT_CRITICAL_DAYS=7
DEFAULT_CONFIG_FILE="/etc/ssl/cert_monitor.conf"
DEFAULT_LOG_FILE="/var/log/cert_monitor.log"

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to log messages
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
}

# Function to print usage
usage() {
    cat << EOF
Certificate Expiration Monitor - Monitor SSL/TLS certificates for expiration

Usage: $0 [OPTIONS]

OPTIONS:
    --config FILE           Configuration file (default: $DEFAULT_CONFIG_FILE)
    --log-file FILE         Log file path (default: $DEFAULT_LOG_FILE)
    --warn-days DAYS        Warning threshold in days (default: $DEFAULT_WARN_DAYS)
    --critical-days DAYS    Critical threshold in days (default: $DEFAULT_CRITICAL_DAYS)
    --email EMAIL           Email address for alerts
    --smtp-server SERVER    SMTP server for email alerts
    --check-files           Check local certificate files
    --check-hosts           Check remote hosts
    --check-file FILE       Check specific certificate file
    --check-host HOST       Check specific host
    --port PORT             Port for host checking (default: 443)
    --output-format FORMAT  Output format: text, json, csv (default: text)
    --quiet                 Suppress non-critical output
    --verbose               Enable verbose output
    --dry-run               Show what would be done without sending alerts
    --help                  Show this help message

CONFIGURATION FILE FORMAT:
    # Certificate files to monitor
    [files]
    /path/to/cert1.crt
    /path/to/cert2.pem
    
    # Remote hosts to monitor
    [hosts]
    example.com:443
    api.example.com:8443
    mail.example.com:993
    
    # Email settings
    [email]
    smtp_server=smtp.example.com
    smtp_port=587
    smtp_user=alerts@example.com
    smtp_password=password
    recipients=admin@example.com,security@example.com

EXAMPLES:
    # Monitor using configuration file
    $0 --config /etc/ssl/cert_monitor.conf

    # Check specific certificate file
    $0 --check-file /etc/ssl/certs/example.com.crt --warn-days 60

    # Check specific host
    $0 --check-host example.com --port 443 --email admin@example.com

    # Generate JSON report
    $0 --check-hosts --output-format json

EOF
}

# Function to check certificate file
check_cert_file() {
    local cert_file="$1"
    local warn_days="$2"
    local critical_days="$3"
    
    if [[ ! -f "$cert_file" ]]; then
        log_message "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate information
    local subject=$(openssl x509 -in "$cert_file" -subject -noout 2>/dev/null | sed 's/subject=//' || echo "Unknown")
    local issuer=$(openssl x509 -in "$cert_file" -issuer -noout 2>/dev/null | sed 's/issuer=//' || echo "Unknown")
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout 2>/dev/null | cut -d= -f2 || echo "")
    
    if [[ -z "$expiry_date" ]]; then
        log_message "ERROR" "Could not read expiry date from $cert_file"
        return 1
    fi
    
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    # Determine status
    local status="OK"
    local color=$GREEN
    
    if [[ $days_until_expiry -lt 0 ]]; then
        status="EXPIRED"
        color=$RED
    elif [[ $days_until_expiry -lt $critical_days ]]; then
        status="CRITICAL"
        color=$RED
    elif [[ $days_until_expiry -lt $warn_days ]]; then
        status="WARNING"
        color=$YELLOW
    fi
    
    # Output result
    case "$output_format" in
        "json")
            cat << EOF
{
  "type": "file",
  "path": "$cert_file",
  "subject": "$subject",
  "issuer": "$issuer",
  "expiry_date": "$expiry_date",
  "days_until_expiry": $days_until_expiry,
  "status": "$status"
}
EOF
            ;;
        "csv")
            echo "file,$cert_file,$subject,$expiry_date,$days_until_expiry,$status"
            ;;
        *)
            if [[ "$quiet" != "true" ]] || [[ "$status" != "OK" ]]; then
                print_color $color "[$status] $cert_file - Expires: $expiry_date ($days_until_expiry days)"
                if [[ "$verbose" == "true" ]]; then
                    echo "  Subject: $subject"
                    echo "  Issuer: $issuer"
                fi
            fi
            ;;
    esac
    
    log_message "INFO" "$status: $cert_file expires in $days_until_expiry days"
    
    # Return status code based on severity
    case "$status" in
        "EXPIRED"|"CRITICAL") return 2 ;;
        "WARNING") return 1 ;;
        *) return 0 ;;
    esac
}

# Function to check remote host certificate
check_host_cert() {
    local host="$1"
    local port="$2"
    local warn_days="$3"
    local critical_days="$4"
    
    # Extract certificate information
    local cert_info=$(echo | timeout 10 openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null)
    
    if [[ -z "$cert_info" ]]; then
        log_message "ERROR" "Could not retrieve certificate from $host:$port"
        return 1
    fi
    
    local subject=$(echo "$cert_info" | grep "Subject:" | sed 's/.*Subject: //' || echo "Unknown")
    local issuer=$(echo "$cert_info" | grep "Issuer:" | sed 's/.*Issuer: //' || echo "Unknown")
    local expiry_date=$(echo | timeout 10 openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2 || echo "")
    
    if [[ -z "$expiry_date" ]]; then
        log_message "ERROR" "Could not read expiry date from $host:$port"
        return 1
    fi
    
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    # Determine status
    local status="OK"
    local color=$GREEN
    
    if [[ $days_until_expiry -lt 0 ]]; then
        status="EXPIRED"
        color=$RED
    elif [[ $days_until_expiry -lt $critical_days ]]; then
        status="CRITICAL"
        color=$RED
    elif [[ $days_until_expiry -lt $warn_days ]]; then
        status="WARNING"
        color=$YELLOW
    fi
    
    # Output result
    case "$output_format" in
        "json")
            cat << EOF
{
  "type": "host",
  "host": "$host",
  "port": $port,
  "subject": "$subject",
  "issuer": "$issuer",
  "expiry_date": "$expiry_date",
  "days_until_expiry": $days_until_expiry,
  "status": "$status"
}
EOF
            ;;
        "csv")
            echo "host,$host:$port,$subject,$expiry_date,$days_until_expiry,$status"
            ;;
        *)
            if [[ "$quiet" != "true" ]] || [[ "$status" != "OK" ]]; then
                print_color $color "[$status] $host:$port - Expires: $expiry_date ($days_until_expiry days)"
                if [[ "$verbose" == "true" ]]; then
                    echo "  Subject: $subject"
                    echo "  Issuer: $issuer"
                fi
            fi
            ;;
    esac
    
    log_message "INFO" "$status: $host:$port expires in $days_until_expiry days"
    
    # Return status code based on severity
    case "$status" in
        "EXPIRED"|"CRITICAL") return 2 ;;
        "WARNING") return 1 ;;
        *) return 0 ;;
    esac
}

# Function to send email alert
send_email_alert() {
    local subject="$1"
    local body="$2"
    local recipients="$3"
    local smtp_server="$4"
    local smtp_port="$5"
    local smtp_user="$6"
    local smtp_password="$7"
    
    if [[ "$dry_run" == "true" ]]; then
        log_message "INFO" "DRY RUN: Would send email to $recipients"
        log_message "INFO" "Subject: $subject"
        return 0
    fi
    
    # Create temporary email file
    local email_file=$(mktemp)
    cat > "$email_file" << EOF
To: $recipients
Subject: $subject
Content-Type: text/html

<html>
<body>
<h2>SSL Certificate Monitoring Alert</h2>
<pre>$body</pre>
<p><i>Generated on $(date)</i></p>
</body>
</html>
EOF
    
    # Send email using available mail command
    if command -v sendmail > /dev/null; then
        sendmail "$recipients" < "$email_file"
    elif command -v mail > /dev/null; then
        mail -s "$subject" "$recipients" < "$email_file"
    elif command -v mutt > /dev/null; then
        mutt -s "$subject" "$recipients" < "$email_file"
    else
        log_message "ERROR" "No mail command available for sending alerts"
        rm -f "$email_file"
        return 1
    fi
    
    rm -f "$email_file"
    log_message "INFO" "Email alert sent to $recipients"
}

# Function to parse configuration file
parse_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_message "WARNING" "Configuration file not found: $config_file"
        return 1
    fi
    
    local section=""
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check for section headers
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Process based on current section
        case "$section" in
            "files")
                cert_files+=("$line")
                ;;
            "hosts")
                if [[ "$line" == *":"* ]]; then
                    hosts+=("$line")
                else
                    hosts+=("$line:443")
                fi
                ;;
            "email")
                if [[ "$line" == smtp_server=* ]]; then
                    smtp_server="${line#*=}"
                elif [[ "$line" == smtp_port=* ]]; then
                    smtp_port="${line#*=}"
                elif [[ "$line" == smtp_user=* ]]; then
                    smtp_user="${line#*=}"
                elif [[ "$line" == smtp_password=* ]]; then
                    smtp_password="${line#*=}"
                elif [[ "$line" == recipients=* ]]; then
                    email_recipients="${line#*=}"
                fi
                ;;
        esac
    done < "$config_file"
}

# Main function
main() {
    local config_file=""
    local log_file="$DEFAULT_LOG_FILE"
    local warn_days="$DEFAULT_WARN_DAYS"
    local critical_days="$DEFAULT_CRITICAL_DAYS"
    local email_recipients=""
    local smtp_server=""
    local smtp_port="587"
    local smtp_user=""
    local smtp_password=""
    local check_files=false
    local check_hosts=false
    local check_file=""
    local check_host=""
    local port="443"
    local output_format="text"
    local quiet=false
    local verbose=false
    local dry_run=false
    
    local cert_files=()
    local hosts=()
    local issues=()
    local exit_code=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                shift
                ;;
            --log-file)
                log_file="$2"
                shift
                ;;
            --warn-days)
                warn_days="$2"
                shift
                ;;
            --critical-days)
                critical_days="$2"
                shift
                ;;
            --email)
                email_recipients="$2"
                shift
                ;;
            --smtp-server)
                smtp_server="$2"
                shift
                ;;
            --check-files)
                check_files=true
                ;;
            --check-hosts)
                check_hosts=true
                ;;
            --check-file)
                check_file="$2"
                shift
                ;;
            --check-host)
                check_host="$2"
                shift
                ;;
            --port)
                port="$2"
                shift
                ;;
            --output-format)
                output_format="$2"
                shift
                ;;
            --quiet)
                quiet=true
                ;;
            --verbose)
                verbose=true
                ;;
            --dry-run)
                dry_run=true
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                print_color $RED "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Create log directory if needed
    mkdir -p "$(dirname "$log_file")"
    
    # Use default config file if none specified
    [[ -z "$config_file" ]] && config_file="$DEFAULT_CONFIG_FILE"
    
    # Parse configuration file if it exists
    if [[ -f "$config_file" ]]; then
        parse_config "$config_file"
        [[ ${#cert_files[@]} -gt 0 ]] && check_files=true
        [[ ${#hosts[@]} -gt 0 ]] && check_hosts=true
    fi
    
    # Handle single file/host checks
    if [[ -n "$check_file" ]]; then
        cert_files=("$check_file")
        check_files=true
    fi
    
    if [[ -n "$check_host" ]]; then
        hosts=("$check_host:$port")
        check_hosts=true
    fi
    
    # Initialize output format
    if [[ "$output_format" == "json" ]]; then
        echo "{"
        echo '  "timestamp": "'$(date -Iseconds)'",'
        echo '  "certificates": ['
    elif [[ "$output_format" == "csv" ]]; then
        echo "type,target,subject,expiry_date,days_until_expiry,status"
    fi
    
    log_message "INFO" "Certificate monitoring started"
    
    local first_json=true
    
    # Check certificate files
    if [[ "$check_files" == "true" ]]; then
        for cert_file in "${cert_files[@]}"; do
            if [[ "$output_format" == "json" ]]; then
                [[ "$first_json" == "false" ]] && echo ","
                check_cert_file "$cert_file" "$warn_days" "$critical_days"
                first_json=false
            else
                if ! check_cert_file "$cert_file" "$warn_days" "$critical_days"; then
                    case $? in
                        1) issues+=("WARNING: $cert_file expires soon") ;;
                        2) issues+=("CRITICAL: $cert_file expired or critical") ;;
                    esac
                    exit_code=1
                fi
            fi
        done
    fi
    
    # Check remote hosts
    if [[ "$check_hosts" == "true" ]]; then
        for host_port in "${hosts[@]}"; do
            local host="${host_port%:*}"
            local host_port_num="${host_port#*:}"
            
            if [[ "$output_format" == "json" ]]; then
                [[ "$first_json" == "false" ]] && echo ","
                check_host_cert "$host" "$host_port_num" "$warn_days" "$critical_days"
                first_json=false
            else
                if ! check_host_cert "$host" "$host_port_num" "$warn_days" "$critical_days"; then
                    case $? in
                        1) issues+=("WARNING: $host:$host_port_num expires soon") ;;
                        2) issues+=("CRITICAL: $host:$host_port_num expired or critical") ;;
                    esac
                    exit_code=1
                fi
            fi
        done
    fi
    
    # Close JSON output
    if [[ "$output_format" == "json" ]]; then
        echo ""
        echo '  ],'
        echo '  "summary": {'
        echo '    "total_issues": '${#issues[@]}','
        echo '    "exit_code": '$exit_code
        echo '  }'
        echo "}"
    fi
    
    # Send email alerts if there are issues
    if [[ ${#issues[@]} -gt 0 && -n "$email_recipients" ]]; then
        local alert_subject="SSL Certificate Alert - ${#issues[@]} issue(s) found"
        local alert_body=$(printf '%s\n' "${issues[@]}")
        
        send_email_alert "$alert_subject" "$alert_body" "$email_recipients" "$smtp_server" "$smtp_port" "$smtp_user" "$smtp_password"
    fi
    
    log_message "INFO" "Certificate monitoring completed with $exit_code exit code"
    
    if [[ ${#issues[@]} -eq 0 && "$quiet" != "true" ]]; then
        print_color $GREEN "All certificates are valid and not expiring soon"
    fi
    
    exit $exit_code
}

# Run main function with all arguments
main "$@"
