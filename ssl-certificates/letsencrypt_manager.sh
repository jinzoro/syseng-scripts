#!/bin/bash

# Let's Encrypt Certificate Manager
# Automated certificate generation, renewal, and management with Let's Encrypt
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
DEFAULT_WEBROOT="/var/www/html"
DEFAULT_EMAIL=""
DEFAULT_STAGING=false
DEFAULT_FORCE_RENEWAL=false
DEFAULT_NGINX_RELOAD=true
DEFAULT_APACHE_RELOAD=false

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
    echo "[$timestamp] [$level] $message"
}

# Function to print usage
usage() {
    cat << EOF
Let's Encrypt Certificate Manager - Automated certificate management with Let's Encrypt

Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    obtain              Obtain a new certificate
    renew               Renew existing certificates
    revoke              Revoke a certificate
    list                List certificates
    status              Check certificate status
    auto-renew          Set up automatic renewal
    install             Install certificate to web server
    backup              Backup certificates
    restore             Restore certificates from backup

OPTIONS:
    --domain DOMAIN         Domain name (required for most operations)
    --domains DOMAINS       Multiple domains (comma-separated)
    --email EMAIL           Email for Let's Encrypt account
    --webroot PATH          Webroot path for domain validation (default: $DEFAULT_WEBROOT)
    --cert-path PATH        Certificate installation path
    --key-path PATH         Private key installation path
    --chain-path PATH       Certificate chain installation path
    --fullchain-path PATH   Full chain certificate path
    --nginx                 Configure for Nginx (default: enabled)
    --apache                Configure for Apache
    --standalone            Use standalone mode (requires port 80)
    --dns-challenge         Use DNS challenge
    --dns-provider PROVIDER DNS provider for DNS challenge
    --staging               Use Let's Encrypt staging environment
    --force-renewal         Force certificate renewal
    --dry-run               Perform a test run without making changes
    --quiet                 Suppress non-error output
    --verbose               Enable verbose output
    --config-dir DIR        Configuration directory (default: /etc/letsencrypt)
    --work-dir DIR          Working directory (default: /var/lib/letsencrypt)
    --logs-dir DIR          Logs directory (default: /var/log/letsencrypt)
    --backup-dir DIR        Backup directory
    --pre-hook COMMAND      Command to run before renewal
    --post-hook COMMAND     Command to run after renewal
    --deploy-hook COMMAND   Command to run after successful renewal
    --help                  Show this help message

EXAMPLES:
    # Obtain certificate for single domain
    $0 obtain --domain example.com --email admin@example.com

    # Obtain certificate for multiple domains
    $0 obtain --domains "example.com,www.example.com,api.example.com" --email admin@example.com

    # Obtain certificate using standalone mode
    $0 obtain --domain example.com --email admin@example.com --standalone

    # Obtain certificate using DNS challenge
    $0 obtain --domain example.com --email admin@example.com --dns-challenge --dns-provider cloudflare

    # Renew all certificates
    $0 renew

    # Force renew specific domain
    $0 renew --domain example.com --force-renewal

    # Test renewal (dry run)
    $0 renew --dry-run

    # Set up auto-renewal cron job
    $0 auto-renew

    # Check certificate status
    $0 status --domain example.com

    # List all certificates
    $0 list

    # Backup certificates
    $0 backup --backup-dir /backup/letsencrypt

EOF
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for certbot
    if ! command -v certbot > /dev/null; then
        missing_deps+=("certbot")
    fi
    
    # Check for openssl
    if ! command -v openssl > /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_color $RED "Missing dependencies: ${missing_deps[*]}"
        print_color $YELLOW "Please install missing dependencies:"
        print_color $CYAN "  Fedora: sudo dnf install certbot python3-certbot-nginx python3-certbot-apache"
        print_color $CYAN "  Ubuntu: sudo apt install certbot python3-certbot-nginx python3-certbot-apache"
        exit 1
    fi
}

# Function to obtain certificate
obtain_cert() {
    local domains="$1"
    local email="$2"
    local webroot="$3"
    local staging="$4"
    local standalone="$5"
    local dns_challenge="$6"
    local dns_provider="$7"
    local nginx="$8"
    local apache="$9"
    local dry_run="${10}"
    local config_dir="${11}"
    local work_dir="${12}"
    local logs_dir="${13}"
    
    print_color $BLUE "Obtaining certificate for: $domains"
    
    # Build certbot command
    local cmd="certbot certonly"
    
    # Add directories
    [[ -n "$config_dir" ]] && cmd+=" --config-dir $config_dir"
    [[ -n "$work_dir" ]] && cmd+=" --work-dir $work_dir"
    [[ -n "$logs_dir" ]] && cmd+=" --logs-dir $logs_dir"
    
    # Add domains
    IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        cmd+=" -d $(echo "$domain" | xargs)"
    done
    
    # Add email
    if [[ -n "$email" ]]; then
        cmd+=" --email $email --agree-tos"
    else
        cmd+=" --register-unsafely-without-email --agree-tos"
    fi
    
    # Add validation method
    if [[ "$standalone" == "true" ]]; then
        cmd+=" --standalone"
    elif [[ "$dns_challenge" == "true" ]]; then
        cmd+=" --manual --preferred-challenges dns"
        [[ -n "$dns_provider" ]] && cmd+=" --dns-$dns_provider"
    else
        cmd+=" --webroot --webroot-path $webroot"
    fi
    
    # Add staging if requested
    [[ "$staging" == "true" ]] && cmd+=" --staging"
    
    # Add dry run if requested
    [[ "$dry_run" == "true" ]] && cmd+=" --dry-run"
    
    # Add non-interactive flag
    cmd+=" --non-interactive"
    
    # Execute command
    log_message "INFO" "Executing: $cmd"
    if eval "$cmd"; then
        print_color $GREEN "Certificate obtained successfully"
        
        # Configure web server if requested
        if [[ "$nginx" == "true" ]]; then
            configure_nginx "$domains"
        elif [[ "$apache" == "true" ]]; then
            configure_apache "$domains"
        fi
        
        return 0
    else
        print_color $RED "Failed to obtain certificate"
        return 1
    fi
}

# Function to renew certificates
renew_certs() {
    local domain="$1"
    local force_renewal="$2"
    local dry_run="$3"
    local pre_hook="$4"
    local post_hook="$5"
    local deploy_hook="$6"
    local config_dir="$7"
    local work_dir="$8"
    local logs_dir="$9"
    
    print_color $BLUE "Renewing certificates..."
    
    local cmd="certbot renew"
    
    # Add directories
    [[ -n "$config_dir" ]] && cmd+=" --config-dir $config_dir"
    [[ -n "$work_dir" ]] && cmd+=" --work-dir $work_dir"
    [[ -n "$logs_dir" ]] && cmd+=" --logs-dir $logs_dir"
    
    # Add specific domain if provided
    [[ -n "$domain" ]] && cmd+=" --cert-name $domain"
    
    # Add force renewal if requested
    [[ "$force_renewal" == "true" ]] && cmd+=" --force-renewal"
    
    # Add dry run if requested
    [[ "$dry_run" == "true" ]] && cmd+=" --dry-run"
    
    # Add hooks
    [[ -n "$pre_hook" ]] && cmd+=" --pre-hook '$pre_hook'"
    [[ -n "$post_hook" ]] && cmd+=" --post-hook '$post_hook'"
    [[ -n "$deploy_hook" ]] && cmd+=" --deploy-hook '$deploy_hook'"
    
    # Add non-interactive flag
    cmd+=" --non-interactive"
    
    # Execute command
    log_message "INFO" "Executing: $cmd"
    if eval "$cmd"; then
        print_color $GREEN "Certificate renewal completed successfully"
        return 0
    else
        print_color $RED "Certificate renewal failed"
        return 1
    fi
}

# Function to configure Nginx
configure_nginx() {
    local domains="$1"
    local primary_domain="${domains%%,*}"
    
    print_color $BLUE "Configuring Nginx for $primary_domain..."
    
    # Check if Nginx is installed
    if ! command -v nginx > /dev/null; then
        print_color $YELLOW "Nginx not found, skipping configuration"
        return 0
    fi
    
    # Use certbot nginx plugin if available
    if certbot --help 2>/dev/null | grep -q "nginx"; then
        local cmd="certbot install --nginx"
        cmd+=" --cert-name $primary_domain"
        cmd+=" --non-interactive"
        
        log_message "INFO" "Installing certificate to Nginx: $cmd"
        if eval "$cmd"; then
            print_color $GREEN "Nginx configured successfully"
        else
            print_color $YELLOW "Automatic Nginx configuration failed, manual configuration may be required"
        fi
    else
        print_color $YELLOW "Certbot Nginx plugin not available, manual configuration required"
    fi
}

# Function to configure Apache
configure_apache() {
    local domains="$1"
    local primary_domain="${domains%%,*}"
    
    print_color $BLUE "Configuring Apache for $primary_domain..."
    
    # Check if Apache is installed
    if ! command -v apache2 > /dev/null && ! command -v httpd > /dev/null; then
        print_color $YELLOW "Apache not found, skipping configuration"
        return 0
    fi
    
    # Use certbot apache plugin if available
    if certbot --help 2>/dev/null | grep -q "apache"; then
        local cmd="certbot install --apache"
        cmd+=" --cert-name $primary_domain"
        cmd+=" --non-interactive"
        
        log_message "INFO" "Installing certificate to Apache: $cmd"
        if eval "$cmd"; then
            print_color $GREEN "Apache configured successfully"
        else
            print_color $YELLOW "Automatic Apache configuration failed, manual configuration may be required"
        fi
    else
        print_color $YELLOW "Certbot Apache plugin not available, manual configuration required"
    fi
}

# Function to list certificates
list_certs() {
    local config_dir="$1"
    
    local cmd="certbot certificates"
    [[ -n "$config_dir" ]] && cmd+=" --config-dir $config_dir"
    
    print_color $BLUE "Listing certificates..."
    eval "$cmd"
}

# Function to check certificate status
check_status() {
    local domain="$1"
    local config_dir="$2"
    
    print_color $BLUE "Checking status for: $domain"
    
    # Check if certificate exists
    local cert_dir="$config_dir/live/$domain"
    if [[ ! -d "$cert_dir" ]]; then
        print_color $RED "Certificate not found for $domain"
        return 1
    fi
    
    # Check certificate details
    local cert_file="$cert_dir/cert.pem"
    if [[ -f "$cert_file" ]]; then
        print_color $GREEN "Certificate found: $cert_file"
        
        # Display certificate information
        openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Subject:"
        openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Issuer:"
        openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Validity"
        
        # Check expiration
        local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -lt 30 ]]; then
            print_color $YELLOW "Certificate expires in $days_until_expiry days"
        else
            print_color $GREEN "Certificate valid for $days_until_expiry days"
        fi
    fi
}

# Function to set up auto-renewal
setup_auto_renewal() {
    local config_dir="$1"
    local pre_hook="$2"
    local post_hook="$3"
    local deploy_hook="$4"
    
    print_color $BLUE "Setting up automatic certificate renewal..."
    
    # Create renewal script
    local renewal_script="/usr/local/bin/letsencrypt-renew.sh"
    cat > "$renewal_script" << EOF
#!/bin/bash
# Let's Encrypt Auto-Renewal Script
# Generated by letsencrypt_manager.sh

set -euo pipefail

# Log file
LOG_FILE="/var/log/letsencrypt/auto-renew.log"

# Function to log messages
log_message() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"
}

# Create log directory
mkdir -p "\$(dirname "\$LOG_FILE")"

log_message "Starting automatic certificate renewal"

# Renew certificates
RENEW_CMD="certbot renew --non-interactive"
EOF

    # Add config directory if specified
    [[ -n "$config_dir" ]] && echo "RENEW_CMD+\" --config-dir $config_dir\"" >> "$renewal_script"
    
    # Add hooks if specified
    [[ -n "$pre_hook" ]] && echo "RENEW_CMD+=\" --pre-hook '$pre_hook'\"" >> "$renewal_script"
    [[ -n "$post_hook" ]] && echo "RENEW_CMD+=\" --post-hook '$post_hook'\"" >> "$renewal_script"
    [[ -n "$deploy_hook" ]] && echo "RENEW_CMD+=\" --deploy-hook '$deploy_hook'\"" >> "$renewal_script"
    
    cat >> "$renewal_script" << 'EOF'

if eval "$RENEW_CMD" >> "$LOG_FILE" 2>&1; then
    log_message "Certificate renewal completed successfully"
else
    log_message "Certificate renewal failed"
    exit 1
fi

log_message "Auto-renewal completed"
EOF

    chmod +x "$renewal_script"
    
    # Create cron job
    local cron_job="0 2 * * * $renewal_script"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$renewal_script"; then
        print_color $YELLOW "Auto-renewal cron job already exists"
    else
        # Add cron job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        print_color $GREEN "Auto-renewal cron job created: $cron_job"
    fi
    
    print_color $GREEN "Auto-renewal script created: $renewal_script"
}

# Function to backup certificates
backup_certs() {
    local backup_dir="$1"
    local config_dir="$2"
    
    print_color $BLUE "Backing up certificates to: $backup_dir"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create timestamped backup
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/letsencrypt_backup_$timestamp.tar.gz"
    
    # Backup Let's Encrypt directory
    if tar -czf "$backup_file" -C "$(dirname "$config_dir")" "$(basename "$config_dir")" 2>/dev/null; then
        print_color $GREEN "Backup created: $backup_file"
        
        # Keep only last 10 backups
        find "$backup_dir" -name "letsencrypt_backup_*.tar.gz" -type f | sort -r | tail -n +11 | xargs rm -f
        
        return 0
    else
        print_color $RED "Backup failed"
        return 1
    fi
}

# Function to restore certificates
restore_certs() {
    local backup_file="$1"
    local config_dir="$2"
    
    print_color $BLUE "Restoring certificates from: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        print_color $RED "Backup file not found: $backup_file"
        return 1
    fi
    
    # Create backup of current configuration
    local current_backup="/tmp/letsencrypt_current_$(date '+%Y%m%d_%H%M%S').tar.gz"
    tar -czf "$current_backup" -C "$(dirname "$config_dir")" "$(basename "$config_dir")" 2>/dev/null
    
    # Restore from backup
    if tar -xzf "$backup_file" -C "$(dirname "$config_dir")" 2>/dev/null; then
        print_color $GREEN "Certificates restored successfully"
        print_color $YELLOW "Current configuration backed up to: $current_backup"
        return 0
    else
        print_color $RED "Restore failed"
        return 1
    fi
}

# Function to revoke certificate
revoke_cert() {
    local domain="$1"
    local config_dir="$2"
    
    print_color $BLUE "Revoking certificate for: $domain"
    
    local cmd="certbot revoke"
    [[ -n "$config_dir" ]] && cmd+=" --config-dir $config_dir"
    cmd+=" --cert-name $domain"
    cmd+=" --non-interactive"
    
    log_message "INFO" "Executing: $cmd"
    if eval "$cmd"; then
        print_color $GREEN "Certificate revoked successfully"
        return 0
    else
        print_color $RED "Certificate revocation failed"
        return 1
    fi
}

# Main function
main() {
    local command=""
    local domain=""
    local domains=""
    local email="$DEFAULT_EMAIL"
    local webroot="$DEFAULT_WEBROOT"
    local staging="$DEFAULT_STAGING"
    local force_renewal="$DEFAULT_FORCE_RENEWAL"
    local standalone=false
    local dns_challenge=false
    local dns_provider=""
    local nginx="$DEFAULT_NGINX_RELOAD"
    local apache="$DEFAULT_APACHE_RELOAD"
    local dry_run=false
    local quiet=false
    local verbose=false
    local config_dir="/etc/letsencrypt"
    local work_dir="/var/lib/letsencrypt"
    local logs_dir="/var/log/letsencrypt"
    local backup_dir=""
    local pre_hook=""
    local post_hook=""
    local deploy_hook=""
    local cert_path=""
    local key_path=""
    local chain_path=""
    local fullchain_path=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            obtain|renew|revoke|list|status|auto-renew|install|backup|restore)
                command="$1"
                ;;
            --domain)
                domain="$2"
                domains="$2"
                shift
                ;;
            --domains)
                domains="$2"
                domain="${2%%,*}"  # First domain as primary
                shift
                ;;
            --email)
                email="$2"
                shift
                ;;
            --webroot)
                webroot="$2"
                shift
                ;;
            --staging)
                staging=true
                ;;
            --force-renewal)
                force_renewal=true
                ;;
            --standalone)
                standalone=true
                nginx=false
                apache=false
                ;;
            --dns-challenge)
                dns_challenge=true
                ;;
            --dns-provider)
                dns_provider="$2"
                shift
                ;;
            --nginx)
                nginx=true
                apache=false
                ;;
            --apache)
                apache=true
                nginx=false
                ;;
            --dry-run)
                dry_run=true
                ;;
            --quiet)
                quiet=true
                ;;
            --verbose)
                verbose=true
                ;;
            --config-dir)
                config_dir="$2"
                shift
                ;;
            --work-dir)
                work_dir="$2"
                shift
                ;;
            --logs-dir)
                logs_dir="$2"
                shift
                ;;
            --backup-dir)
                backup_dir="$2"
                shift
                ;;
            --pre-hook)
                pre_hook="$2"
                shift
                ;;
            --post-hook)
                post_hook="$2"
                shift
                ;;
            --deploy-hook)
                deploy_hook="$2"
                shift
                ;;
            --cert-path)
                cert_path="$2"
                shift
                ;;
            --key-path)
                key_path="$2"
                shift
                ;;
            --chain-path)
                chain_path="$2"
                shift
                ;;
            --fullchain-path)
                fullchain_path="$2"
                shift
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
    
    # Check dependencies
    check_dependencies
    
    # Validate command
    if [[ -z "$command" ]]; then
        print_color $RED "Error: No command specified"
        usage
        exit 1
    fi
    
    # Execute command
    case "$command" in
        "obtain")
            [[ -z "$domains" ]] && { print_color $RED "Error: --domain or --domains is required"; exit 1; }
            obtain_cert "$domains" "$email" "$webroot" "$staging" "$standalone" "$dns_challenge" "$dns_provider" "$nginx" "$apache" "$dry_run" "$config_dir" "$work_dir" "$logs_dir"
            ;;
        "renew")
            renew_certs "$domain" "$force_renewal" "$dry_run" "$pre_hook" "$post_hook" "$deploy_hook" "$config_dir" "$work_dir" "$logs_dir"
            ;;
        "revoke")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required"; exit 1; }
            revoke_cert "$domain" "$config_dir"
            ;;
        "list")
            list_certs "$config_dir"
            ;;
        "status")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required"; exit 1; }
            check_status "$domain" "$config_dir"
            ;;
        "auto-renew")
            setup_auto_renewal "$config_dir" "$pre_hook" "$post_hook" "$deploy_hook"
            ;;
        "backup")
            [[ -z "$backup_dir" ]] && { print_color $RED "Error: --backup-dir is required"; exit 1; }
            backup_certs "$backup_dir" "$config_dir"
            ;;
        "restore")
            [[ -z "$backup_dir" ]] && { print_color $RED "Error: --backup-dir with backup file is required"; exit 1; }
            restore_certs "$backup_dir" "$config_dir"
            ;;
        *)
            print_color $RED "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
