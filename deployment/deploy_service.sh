#!/bin/bash

# Service Deployment Script with Health Checks and Rollback
# Usage: ./deploy_service.sh --service myapp --version 1.2.3 [options]

set -euo pipefail

# Default values
SERVICE_NAME=""
SERVICE_VERSION=""
DEPLOYMENT_DIR="/opt/deployments"
BACKUP_DIR="/opt/backups"
HEALTH_CHECK_URL=""
HEALTH_CHECK_TIMEOUT=30
MAX_RETRIES=5
ROLLBACK_ON_FAILURE=true
ZERO_DOWNTIME=true
CONFIG_FILE=""
ENVIRONMENT="production"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --version)
            SERVICE_VERSION="$2"
            shift 2
            ;;
        --deployment-dir)
            DEPLOYMENT_DIR="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --health-check)
            HEALTH_CHECK_URL="$2"
            shift 2
            ;;
        --timeout)
            HEALTH_CHECK_TIMEOUT="$2"
            shift 2
            ;;
        --retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --no-rollback)
            ROLLBACK_ON_FAILURE=false
            shift
            ;;
        --no-zero-downtime)
            ZERO_DOWNTIME=false
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Usage: $0 --service SERVICE --version VERSION [options]

Required:
  --service NAME       Service name to deploy
  --version VERSION    Version to deploy

Options:
  --deployment-dir DIR    Deployment directory (default: /opt/deployments)
  --backup-dir DIR        Backup directory (default: /opt/backups)
  --health-check URL      Health check URL
  --timeout SECONDS       Health check timeout (default: 30)
  --retries COUNT         Max retry attempts (default: 5)
  --no-rollback           Disable automatic rollback on failure
  --no-zero-downtime     Disable zero-downtime deployment
  --config FILE           Configuration file path
  --environment ENV       Environment (default: production)
  -h, --help             Show this help message

Examples:
  $0 --service myapp --version 1.2.3
  $0 --service api --version 2.0.0 --health-check http://localhost:8080/health
  $0 --service frontend --version 1.5.1 --environment staging --no-rollback
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" || -z "$SERVICE_VERSION" ]]; then
    echo "Error: --service and --version are required"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables
CURRENT_DIR="$DEPLOYMENT_DIR/$SERVICE_NAME/current"
NEW_DIR="$DEPLOYMENT_DIR/$SERVICE_NAME/$SERVICE_VERSION"
BACKUP_FILE="$BACKUP_DIR/${SERVICE_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
ROLLBACK_PERFORMED=false

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    if [[ "$ROLLBACK_ON_FAILURE" == "true" && "$ROLLBACK_PERFORMED" == "false" ]]; then
        log "${YELLOW}Attempting automatic rollback...${NC}"
        perform_rollback
    fi
    exit 1
}

# Check if service is running
is_service_running() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Health check function
perform_health_check() {
    local url="$1"
    local max_attempts="$2"
    local timeout="$3"
    
    log "${BLUE}Performing health check: $url${NC}"
    
    for ((i=1; i<=max_attempts; i++)); do
        log "Health check attempt $i/$max_attempts"
        
        if curl -f -s --max-time "$timeout" "$url" >/dev/null 2>&1; then
            log "${GREEN}Health check passed${NC}"
            return 0
        else
            log "${YELLOW}Health check failed, retrying...${NC}"
            sleep 5
        fi
    done
    
    log "${RED}Health check failed after $max_attempts attempts${NC}"
    return 1
}

# Backup current version
backup_current_version() {
    log "${BLUE}Creating backup of current version...${NC}"
    
    if [[ -d "$CURRENT_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        
        if tar -czf "$BACKUP_FILE" -C "$(dirname "$CURRENT_DIR")" "$(basename "$CURRENT_DIR")"; then
            log "${GREEN}Backup created: $BACKUP_FILE${NC}"
        else
            error_exit "Failed to create backup"
        fi
    else
        log "${YELLOW}No current version found, skipping backup${NC}"
    fi
}

# Download and prepare new version
prepare_new_version() {
    log "${BLUE}Preparing new version: $SERVICE_VERSION${NC}"
    
    mkdir -p "$NEW_DIR"
    
    # Simulate downloading/copying new version
    # In real scenarios, this would download from artifact repository
    log "Downloading $SERVICE_NAME version $SERVICE_VERSION..."
    
    # Example: Copy from build directory or download from repository
    # wget "https://artifacts.company.com/$SERVICE_NAME/$SERVICE_VERSION.tar.gz" -O "$NEW_DIR/app.tar.gz"
    # tar -xzf "$NEW_DIR/app.tar.gz" -C "$NEW_DIR"
    
    # For demo purposes, create a mock application
    cat > "$NEW_DIR/app.sh" << 'EOF'
#!/bin/bash
echo "Application $SERVICE_NAME version $SERVICE_VERSION is running"
sleep infinity
EOF
    chmod +x "$NEW_DIR/app.sh"
    
    # Copy configuration if provided
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$NEW_DIR/config.conf"
        log "Configuration file copied"
    fi
    
    log "${GREEN}New version prepared in $NEW_DIR${NC}"
}

# Start new version
start_new_version() {
    log "${BLUE}Starting new version...${NC}"
    
    # Create systemd service file if it doesn't exist
    if [[ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        create_systemd_service
    fi
    
    # Update symlink to new version
    if [[ -L "$CURRENT_DIR" ]]; then
        rm "$CURRENT_DIR"
    elif [[ -d "$CURRENT_DIR" ]]; then
        mv "$CURRENT_DIR" "${CURRENT_DIR}.old"
    fi
    
    ln -sf "$NEW_DIR" "$CURRENT_DIR"
    
    # Reload systemd and start service
    systemctl daemon-reload
    
    if [[ "$ZERO_DOWNTIME" == "true" ]]; then
        # For zero-downtime, start new instance on different port first
        log "Starting new instance for zero-downtime deployment..."
        # Implementation would depend on application architecture
    fi
    
    if systemctl start "$SERVICE_NAME"; then
        log "${GREEN}Service started successfully${NC}"
    else
        error_exit "Failed to start service"
    fi
    
    # Wait for service to be ready
    sleep 5
    
    if is_service_running; then
        log "${GREEN}Service is running${NC}"
    else
        error_exit "Service failed to start properly"
    fi
}

# Create systemd service file
create_systemd_service() {
    log "Creating systemd service file..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=$SERVICE_NAME Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nobody
WorkingDirectory=$CURRENT_DIR
ExecStart=$CURRENT_DIR/app.sh
Restart=always
RestartSec=3
Environment=ENV=$ENVIRONMENT

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    log "Systemd service created and enabled"
}

# Perform rollback
perform_rollback() {
    ROLLBACK_PERFORMED=true
    log "${YELLOW}Performing rollback...${NC}"
    
    # Stop current service
    if is_service_running; then
        systemctl stop "$SERVICE_NAME"
    fi
    
    # Restore from backup
    if [[ -f "$BACKUP_FILE" ]]; then
        rm -rf "$CURRENT_DIR"
        tar -xzf "$BACKUP_FILE" -C "$(dirname "$CURRENT_DIR")"
        
        # Start previous version
        if systemctl start "$SERVICE_NAME"; then
            log "${GREEN}Rollback completed successfully${NC}"
        else
            log "${RED}Rollback failed - manual intervention required${NC}"
        fi
    else
        log "${RED}No backup found - cannot rollback automatically${NC}"
    fi
}

# Post-deployment verification
post_deployment_verification() {
    log "${BLUE}Performing post-deployment verification...${NC}"
    
    # Check service status
    if ! is_service_running; then
        error_exit "Service is not running after deployment"
    fi
    
    # Health check if URL provided
    if [[ -n "$HEALTH_CHECK_URL" ]]; then
        if ! perform_health_check "$HEALTH_CHECK_URL" "$MAX_RETRIES" "$HEALTH_CHECK_TIMEOUT"; then
            error_exit "Health check failed"
        fi
    fi
    
    # Check logs for errors
    log "Checking service logs for errors..."
    if journalctl -u "$SERVICE_NAME" --since "5 minutes ago" | grep -i error; then
        log "${YELLOW}Errors found in logs, please review${NC}"
    else
        log "${GREEN}No recent errors found in logs${NC}"
    fi
    
    log "${GREEN}Post-deployment verification completed${NC}"
}

# Cleanup old versions
cleanup_old_versions() {
    log "${BLUE}Cleaning up old versions...${NC}"
    
    # Keep last 5 versions
    local versions_to_keep=5
    local version_dirs=()
    
    while IFS= read -r -d '' dir; do
        version_dirs+=("$dir")
    done < <(find "$DEPLOYMENT_DIR/$SERVICE_NAME" -maxdepth 1 -type d -name "*.*.*" -print0 | sort -z)
    
    if [[ ${#version_dirs[@]} -gt $versions_to_keep ]]; then
        local dirs_to_remove=$((${#version_dirs[@]} - versions_to_keep))
        
        for ((i=0; i<dirs_to_remove; i++)); do
            rm -rf "${version_dirs[i]}"
            log "Removed old version: $(basename "${version_dirs[i]}")"
        done
    fi
    
    # Cleanup old backups (keep last 10)
    find "$BACKUP_DIR" -name "${SERVICE_NAME}_*.tar.gz" -type f | sort -r | tail -n +11 | xargs rm -f
    
    log "${GREEN}Cleanup completed${NC}"
}

# Generate deployment report
generate_deployment_report() {
    log "${BLUE}Generating deployment report...${NC}"
    
    local report_file="/tmp/${SERVICE_NAME}_deployment_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Deployment Report
=================
Service: $SERVICE_NAME
Version: $SERVICE_VERSION
Environment: $ENVIRONMENT
Deployment Time: $(date)
Deployment Directory: $NEW_DIR
Backup File: $BACKUP_FILE

Service Status:
$(systemctl status "$SERVICE_NAME" --no-pager)

Recent Logs:
$(journalctl -u "$SERVICE_NAME" --since "10 minutes ago" --no-pager)
EOF
    
    log "Deployment report saved to: $report_file"
}

# Main deployment process
main() {
    log "${GREEN}Starting deployment of $SERVICE_NAME version $SERVICE_VERSION${NC}"
    log "Environment: $ENVIRONMENT"
    log "Zero-downtime: $ZERO_DOWNTIME"
    log "Auto-rollback: $ROLLBACK_ON_FAILURE"
    
    # Pre-deployment checks
    if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
        mkdir -p "$DEPLOYMENT_DIR"
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Deployment steps
    backup_current_version
    prepare_new_version
    start_new_version
    post_deployment_verification
    cleanup_old_versions
    generate_deployment_report
    
    log "${GREEN}Deployment completed successfully!${NC}"
    log "Service $SERVICE_NAME version $SERVICE_VERSION is now running"
}

# Trap errors
trap 'error_exit "Script interrupted"' ERR INT TERM

main "$@"
