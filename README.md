# System Engineering Scripts Collection

A comprehensive collection of shell scripts designed for system engineers to manage, monitor, and maintain Linux systems effectively.

## Directory Structure

```
syseng-scripts/
├── monitoring/          # System monitoring scripts
├── backup/             # Backup and restore scripts
├── network/            # Network diagnostic tools
├── security/           # Security audit scripts
├── deployment/         # Service deployment scripts
├── logs/               # Log management utilities
├── maintenance/        # System maintenance scripts
└── README.md          # This file
```

## Scripts Overview

### 1. Monitoring Scripts (`monitoring/`)

#### `system_health.sh`
Comprehensive system health monitoring with alerting capabilities.

**Features:**
- CPU, memory, disk, and load monitoring
- Service status checking
- Email alerts for critical issues
- Configurable thresholds
- Color-coded output

**Usage:**
```bash
./system_health.sh [--email recipient@domain.com] [--threshold 80]
```

#### `process_monitor.sh`
Process monitoring and management with resource usage tracking.

**Features:**
- High CPU/memory process detection
- Automatic process termination (optional)
- Process whitelisting
- Top processes summary

**Usage:**
```bash
./process_monitor.sh [--cpu-limit 90] [--memory-limit 90] [--kill] [--whitelist "process1,process2"]
```

### 2. Backup Scripts (`backup/`)

#### `backup_system.sh`
Advanced backup solution with compression, encryption, and rotation.

**Features:**
- Compression with tar/gzip
- AES-256 encryption support
- Automatic rotation and cleanup
- Exclude patterns support
- Backup verification
- Dry-run mode

**Usage:**
```bash
./backup_system.sh --source /path/to/source --dest /path/to/dest [options]
```

**Examples:**
```bash
# Basic backup
./backup_system.sh --source /home/user --dest /backup/location

# Encrypted backup with custom retention
./backup_system.sh --source /var/www --dest /backup --encrypt mykey123 --retention 7

# Verbose backup with exclude file
./backup_system.sh --source /etc --dest /backup --exclude /tmp/exclude.txt --verbose
```

### 3. Network Scripts (`network/`)

#### `network_diagnostics.sh`
Comprehensive network diagnostic and monitoring tool.

**Features:**
- Connectivity testing
- DNS diagnostics
- Port scanning
- Traceroute analysis
- Network statistics
- Bandwidth testing
- Report generation

**Usage:**
```bash
./network_diagnostics.sh [--host hostname] [--port port] [--scan] [--trace] [--dns]
```

**Examples:**
```bash
# Test specific host and port
./network_diagnostics.sh --host google.com --port 80

# Full network diagnostic with port scan
./network_diagnostics.sh --host 192.168.1.1 --scan --trace

# DNS diagnostics only
./network_diagnostics.sh --dns --verbose
```

### 4. Security Scripts (`security/`)

#### `security_audit.sh`
Security audit and compliance checking tool.

**Features:**
- Package update checking
- Firewall status verification
- Rootkit scanning (with rkhunter)
- Weak password detection
- Security compliance reporting

**Usage:**
```bash
./security_audit.sh [--check-updates] [--firewall-status] [--scan-rootkits] [--weak-passwords]
```

### 5. Deployment Scripts (`deployment/`)

#### `deploy_service.sh`
Zero-downtime service deployment with health checks and rollback.

**Features:**
- Blue-green deployment support
- Health check validation
- Automatic rollback on failure
- Configuration management
- Deployment reporting
- Version management

**Usage:**
```bash
./deploy_service.sh --service SERVICE --version VERSION [options]
```

**Examples:**
```bash
# Basic deployment
./deploy_service.sh --service myapp --version 1.2.3

# Deployment with health checks
./deploy_service.sh --service api --version 2.0.0 --health-check http://localhost:8080/health

# Staging deployment without rollback
./deploy_service.sh --service frontend --version 1.5.1 --environment staging --no-rollback
```

### 6. Log Management Scripts (`logs/`)

#### `log_manager.sh`
Comprehensive log management with analysis and monitoring.

**Features:**
- Log rotation based on size
- Error pattern analysis
- Real-time log monitoring
- Automatic cleanup
- Compression support
- Email alerts for high error rates

**Usage:**
```bash
./log_manager.sh [--rotate] [--analyze] [--cleanup] [--monitor] [--path /path/to/logs]
```

**Examples:**
```bash
# Analyze logs for errors
./log_manager.sh --analyze --path /var/log/myapp

# Rotate and cleanup with custom retention
./log_manager.sh --rotate --cleanup --retention 7

# Real-time monitoring with alerts
./log_manager.sh --monitor --email admin@company.com
```

### 7. Maintenance Scripts (`maintenance/`)

#### `system_maintenance.sh`
Automated system maintenance and optimization.

**Features:**
- Package updates
- System cleanup
- Performance optimization
- Automatic rebooting
- Maintenance reporting
- Dry-run mode

**Usage:**
```bash
./system_maintenance.sh [--update] [--cleanup] [--optimize] [--reboot-if-needed]
```

**Examples:**
```bash
# Update and cleanup
./system_maintenance.sh --update --cleanup

# Full maintenance with reboot
./system_maintenance.sh --update --cleanup --optimize --reboot-if-needed

# Dry run to see what would be done
./system_maintenance.sh --update --cleanup --dry-run
```

### 8. SSL Certificate Management Scripts (`ssl-certificates/`)

#### `ssl_manager.sh`
Comprehensive SSL certificate management with key, CSR generation, and validation.

**Features:**
- Private key generation (RSA, various key sizes)
- Certificate Signing Request (CSR) creation
- Self-signed certificate generation
- Certificate Authority (CA) setup
- Certificate signing with CA
- Certificate validation and verification
- Certificate information display
- Expiration checking
- SSL/TLS configuration testing
- Certificate format conversion (PEM, DER, PKCS12)
- Certificate bundle creation

**Usage:**
```bash
./ssl_manager.sh [COMMAND] [OPTIONS]
```

**Examples:**
```bash
# Generate private key
./ssl_manager.sh generate-key --domain example.com --key-size 4096

# Generate CSR with SAN
./ssl_manager.sh generate-csr --domain example.com --key-file example.com.key --san "www.example.com,api.example.com"

# Generate self-signed certificate
./ssl_manager.sh generate-cert --domain example.com --days 365

# Validate certificate and key
./ssl_manager.sh validate --cert-file example.com.crt --key-file example.com.key

# Test remote SSL
./ssl_manager.sh test-ssl --host example.com --port 443
```

#### `cert_monitor.sh`
Monitors SSL certificates for expiration with comprehensive alerting.

**Features:**
- Local certificate file monitoring
- Remote host certificate checking
- Configurable warning and critical thresholds
- Multiple output formats (text, JSON, CSV)
- Email alerts for expiring certificates
- Configuration file support
- Detailed logging

**Usage:**
```bash
./cert_monitor.sh [OPTIONS]
```

**Examples:**
```bash
# Check specific certificate file
./cert_monitor.sh --check-file /etc/ssl/certs/example.com.crt --warn-days 60

# Check remote host
./cert_monitor.sh --check-host example.com --email admin@example.com

# Generate JSON report
./cert_monitor.sh --check-hosts --output-format json

# Use configuration file
./cert_monitor.sh --config /etc/ssl/cert_monitor.conf
```

#### `letsencrypt_manager.sh`
Automates Let's Encrypt certificate management with multiple validation methods.

**Features:**
- Certificate obtaining with webroot, standalone, or DNS validation
- Automatic certificate renewal
- Multiple domain support (SAN certificates)
- Web server integration (Nginx, Apache)
- Staging environment support
- Automatic renewal setup with cron
- Certificate backup and restore
- Hooks for custom actions

**Usage:**
```bash
./letsencrypt_manager.sh [COMMAND] [OPTIONS]
```

**Examples:**
```bash
# Obtain certificate for single domain
./letsencrypt_manager.sh obtain --domain example.com --email admin@example.com

# Obtain certificate for multiple domains
./letsencrypt_manager.sh obtain --domains "example.com,www.example.com,api.example.com" --email admin@example.com

# Obtain using standalone mode
./letsencrypt_manager.sh obtain --domain example.com --email admin@example.com --standalone

# Renew all certificates
./letsencrypt_manager.sh renew

# Set up auto-renewal
./letsencrypt_manager.sh auto-renew

# Backup certificates
./letsencrypt_manager.sh backup --backup-dir /backup/letsencrypt
```

## Installation and Setup

1. **Clone or download the scripts:**
   ```bash
   git clone <repository-url> /home/izabari/syseng-scripts
   cd /home/izabari/syseng-scripts
   ```

2. **Make scripts executable:**
   ```bash
   find . -name "*.sh" -type f -exec chmod +x {} \;
   ```

3. **Add to PATH (optional):**
   ```bash
   echo 'export PATH="$PATH:/home/izabari/syseng-scripts"' >> ~/.bashrc
   source ~/.bashrc
   ```

## Dependencies

Most scripts are designed to work with standard Linux utilities. Some optional dependencies include:

- **Email alerts:** `mailutils` or `postfix`
- **Network tools:** `netcat`, `traceroute`, `nslookup`
- **Security tools:** `rkhunter`, `john`
- **Compression:** `gzip`, `tar`
- **Encryption:** `openssl`

Install dependencies on Fedora:
```bash
sudo dnf install mailx netcat-openbsd traceroute bind-utils rkhunter john gzip tar openssl
```

## Configuration

### Environment Variables

Some scripts support environment variables for default configuration:

```bash
export BACKUP_DEFAULT_DEST="/backup"
export MONITORING_EMAIL="admin@company.com"
export LOG_RETENTION_DAYS="30"
```

### Cron Jobs

Set up automated execution with cron:

```bash
# Daily system health check at 6 AM
0 6 * * * /home/izabari/syseng-scripts/monitoring/system_health.sh --email admin@company.com

# Weekly system maintenance on Sunday at 2 AM
0 2 * * 0 /home/izabari/syseng-scripts/maintenance/system_maintenance.sh --update --cleanup --optimize

# Daily log rotation at midnight
0 0 * * * /home/izabari/syseng-scripts/logs/log_manager.sh --rotate --cleanup

# Hourly backup during business hours
0 9-17 * * 1-5 /home/izabari/syseng-scripts/backup/backup_system.sh --source /important/data --dest /backup/hourly
```

## Security Considerations

1. **Script Permissions:** Ensure scripts have appropriate permissions and are not writable by others.
2. **Sensitive Data:** Never hard-code passwords or keys in scripts. Use environment variables or secure key management.
3. **Root Access:** Some scripts require root privileges. Use sudo judiciously.
4. **Log Files:** Ensure log files are properly secured and rotated.

## Troubleshooting

### Common Issues

1. **Permission Denied:**
   ```bash
   chmod +x script_name.sh
   ```

2. **Command Not Found:**
   - Check if required dependencies are installed
   - Verify PATH includes script directory

3. **Email Alerts Not Working:**
   - Install and configure mail utilities
   - Test mail configuration: `echo "test" | mail -s "test" user@domain.com`

4. **Log File Access:**
   - Ensure proper permissions on log directories
   - Check SELinux/AppArmor policies if applicable

### Debug Mode

Most scripts support verbose output for troubleshooting:
```bash
./script_name.sh --verbose
```

## Contributing

When adding new scripts or modifying existing ones:

1. Follow the established coding style
2. Include comprehensive help text (`--help`)
3. Add proper error handling
4. Use consistent logging format
5. Update this README

## Script Standards

All scripts follow these standards:

- **Shebang:** `#!/bin/bash`
- **Error handling:** `set -euo pipefail`
- **Help option:** `--help` or `-h`
- **Logging:** Timestamped log messages
- **Colors:** Consistent color scheme for output
- **Arguments:** Long-form arguments preferred (`--option` vs `-o`)

## License

These scripts are provided as-is for educational and operational use. Please review and test thoroughly before use in production environments.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review script help text (`script_name.sh --help`)
3. Check system logs for detailed error messages

---

**Last Updated:** $(date)
**Version:** 1.0
**Maintainer:** System Engineering Team
