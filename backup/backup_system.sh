#!/bin/bash

# System Backup Script with Compression and Encryption
# Usage: ./backup_system.sh --source /path/to/source --dest /path/to/dest [options]

set -euo pipefail

# Default values
SOURCE_DIR=""
DEST_DIR=""
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
COMPRESSION=true
ENCRYPTION=false
ENCRYPTION_KEY=""
RETENTION_DAYS=30
EXCLUDE_FILE=""
DRY_RUN=false
VERBOSE=false
LOG_FILE="/var/log/backup.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --dest)
            DEST_DIR="$2"
            shift 2
            ;;
        --name)
            BACKUP_NAME="$2"
            shift 2
            ;;
        --no-compression)
            COMPRESSION=false
            shift
            ;;
        --encrypt)
            ENCRYPTION=true
            ENCRYPTION_KEY="$2"
            shift 2
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --exclude)
            EXCLUDE_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 --source /path/to/source --dest /path/to/dest [options]

Required:
  --source DIR          Source directory to backup
  --dest DIR           Destination directory for backups

Options:
  --name NAME          Backup name (default: backup_YYYYMMDD_HHMMSS)
  --no-compression     Disable compression
  --encrypt KEY        Enable encryption with provided key
  --retention DAYS     Retention period in days (default: 30)
  --exclude FILE       File containing exclude patterns
  --dry-run           Show what would be done without executing
  --verbose           Enable verbose output
  -h, --help          Show this help message

Examples:
  $0 --source /home/user --dest /backup/location
  $0 --source /var/www --dest /backup --encrypt mykey123 --retention 7
  $0 --source /etc --dest /backup --exclude /tmp/exclude.txt --verbose
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
if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
    echo "Error: --source and --dest are required"
    exit 1
fi

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
    echo "$timestamp - $message" | tee -a "$LOG_FILE"
}

# Verbose output function
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if [[ "$COMPRESSION" == "true" ]] && ! command -v tar >/dev/null 2>&1; then
        missing_deps+=("tar")
    fi
    
    if [[ "$ENCRYPTION" == "true" ]] && ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing dependencies: ${missing_deps[*]}${NC}"
        exit 1
    fi
}

# Create destination directory if it doesn't exist
create_dest_dir() {
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$DEST_DIR"
    else
        echo "[DRY RUN] Would create directory: $DEST_DIR"
    fi
}

# Calculate source directory size
calculate_source_size() {
    local size
    size=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)
    echo "Source directory size: $size"
    verbose_log "Calculating size of $SOURCE_DIR"
}

# Build exclude options for tar
build_exclude_options() {
    local exclude_opts=""
    
    # Default excludes
    exclude_opts+=" --exclude='*.tmp' --exclude='*.swp' --exclude='*~'"
    exclude_opts+=" --exclude='.git' --exclude='.svn' --exclude='node_modules'"
    exclude_opts+=" --exclude='__pycache__' --exclude='*.pyc'"
    
    # Custom exclude file
    if [[ -n "$EXCLUDE_FILE" && -f "$EXCLUDE_FILE" ]]; then
        exclude_opts+=" --exclude-from='$EXCLUDE_FILE'"
        verbose_log "Using exclude file: $EXCLUDE_FILE"
    fi
    
    echo "$exclude_opts"
}

# Perform backup
perform_backup() {
    local backup_path="$DEST_DIR/$BACKUP_NAME"
    local exclude_opts
    exclude_opts=$(build_exclude_options)
    
    echo -e "${BLUE}Starting backup...${NC}"
    log_message "Starting backup of $SOURCE_DIR to $backup_path"
    
    if [[ "$COMPRESSION" == "true" ]]; then
        backup_path="${backup_path}.tar.gz"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            verbose_log "Creating compressed archive: $backup_path"
            
            # Create tar command with progress if verbose
            if [[ "$VERBOSE" == "true" ]]; then
                eval "tar -czf '$backup_path' -C '$(dirname "$SOURCE_DIR")' $exclude_opts --verbose '$(basename "$SOURCE_DIR")'" 2>&1 | tee -a "$LOG_FILE"
            else
                eval "tar -czf '$backup_path' -C '$(dirname "$SOURCE_DIR")' $exclude_opts '$(basename "$SOURCE_DIR")'" 2>&1 | tee -a "$LOG_FILE"
            fi
        else
            echo "[DRY RUN] Would create compressed archive: $backup_path"
        fi
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            verbose_log "Creating uncompressed backup: $backup_path"
            eval "rsync -av $exclude_opts '$SOURCE_DIR/' '$backup_path/'" 2>&1 | tee -a "$LOG_FILE"
        else
            echo "[DRY RUN] Would create uncompressed backup: $backup_path"
        fi
    fi
    
    # Encrypt if requested
    if [[ "$ENCRYPTION" == "true" ]]; then
        encrypt_backup "$backup_path"
    fi
    
    # Verify backup
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_backup "$backup_path"
    fi
    
    echo "$backup_path"
}

# Encrypt backup
encrypt_backup() {
    local backup_path="$1"
    local encrypted_path="${backup_path}.enc"
    
    echo -e "${YELLOW}Encrypting backup...${NC}"
    verbose_log "Encrypting $backup_path to $encrypted_path"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        openssl aes-256-cbc -salt -in "$backup_path" -out "$encrypted_path" -k "$ENCRYPTION_KEY"
        rm "$backup_path"
        log_message "Backup encrypted: $encrypted_path"
    else
        echo "[DRY RUN] Would encrypt backup to: $encrypted_path"
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_path="$1"
    
    echo -e "${YELLOW}Verifying backup integrity...${NC}"
    verbose_log "Verifying backup: $backup_path"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        if tar -tzf "$backup_path" >/dev/null 2>&1; then
            echo -e "${GREEN}Backup verification successful${NC}"
            log_message "Backup verification successful: $backup_path"
        else
            echo -e "${RED}Backup verification failed${NC}"
            log_message "ERROR: Backup verification failed: $backup_path"
            return 1
        fi
    elif [[ "$backup_path" == *.enc ]]; then
        # For encrypted files, we can't easily verify without decrypting
        echo -e "${YELLOW}Encrypted backup created (verification skipped)${NC}"
        log_message "Encrypted backup created: $backup_path"
    else
        # For directory backups, check if directory exists and has content
        if [[ -d "$backup_path" && -n "$(ls -A "$backup_path")" ]]; then
            echo -e "${GREEN}Backup verification successful${NC}"
            log_message "Backup verification successful: $backup_path"
        else
            echo -e "${RED}Backup verification failed${NC}"
            log_message "ERROR: Backup verification failed: $backup_path"
            return 1
        fi
    fi
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    echo -e "${YELLOW}Cleaning up old backups (retention: ${RETENTION_DAYS} days)...${NC}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local deleted_count=0
        while IFS= read -r -d '' backup_file; do
            rm "$backup_file"
            ((deleted_count++))
            verbose_log "Deleted old backup: $backup_file"
        done < <(find "$DEST_DIR" -name "backup_*" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null)
        
        echo "Deleted $deleted_count old backup(s)"
        log_message "Cleanup completed: $deleted_count old backups deleted"
    else
        echo "[DRY RUN] Would delete old backups older than $RETENTION_DAYS days"
        find "$DEST_DIR" -name "backup_*" -type f -mtime +$RETENTION_DAYS 2>/dev/null | while read -r backup_file; do
            echo "[DRY RUN] Would delete: $backup_file"
        done
    fi
}

# Generate backup report
generate_report() {
    local backup_path="$1"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo "========================================="
    echo "Backup Report"
    echo "========================================="
    echo "Source: $SOURCE_DIR"
    echo "Destination: $backup_path"
    echo "Compression: $COMPRESSION"
    echo "Encryption: $ENCRYPTION"
    echo "Completed: $end_time"
    
    if [[ "$DRY_RUN" == "false" && -f "$backup_path" ]]; then
        local backup_size
        backup_size=$(du -sh "$backup_path" | cut -f1)
        echo "Backup size: $backup_size"
    fi
    
    echo "========================================="
}

# Main execution
main() {
    echo -e "${GREEN}System Backup Script${NC}"
    echo "Source: $SOURCE_DIR"
    echo "Destination: $DEST_DIR"
    echo "Backup name: $BACKUP_NAME"
    echo "Compression: $COMPRESSION"
    echo "Encryption: $ENCRYPTION"
    echo "Retention: $RETENTION_DAYS days"
    [[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}DRY RUN MODE${NC}"
    echo ""
    
    # Validate source directory
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo -e "${RED}Error: Source directory does not exist: $SOURCE_DIR${NC}"
        exit 1
    fi
    
    check_dependencies
    create_dest_dir
    calculate_source_size
    
    local backup_path
    backup_path=$(perform_backup)
    
    cleanup_old_backups
    generate_report "$backup_path"
    
    echo -e "${GREEN}Backup completed successfully!${NC}"
    log_message "Backup operation completed successfully"
}

main "$@"
