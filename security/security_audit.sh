#!/bin/bash

# Security Audit Script
# Usage: ./security_audit.sh [--check-updates] [--firewall-status] [--scan-rootkits] [--weak-passwords]

set -euo pipefail

# Default options
display_updates=false
firewall_status=false
scan_rootkits=false
check_weak_passwords=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-updates)
            display_updates=true
            shift
            ;;
        --firewall-status)
            firewall_status=true
            shift
            ;;
        --scan-rootkits)
            scan_rootkits=true
            shift
            ;;
        --weak-passwords)
            check_weak_passwords=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--check-updates] [--firewall-status] [--scan-rootkits] [--weak-passwords]"
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

# Security checks
# Check for package updates
check_updates() {
    echo -e "${GREEN}Checking for package updates...${NC}"

    dnf check-update -q 

    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}System packages are up to date.${NC}"
    else
        echo -e "${RED}Updates available. Run 'sudo dnf update'.${NC}"
    fi
}

# Check firewall status
check_firewall() {
    echo -e "${GREEN}Checking firewall status...${NC}"

    if systemctl is-active --quiet firewalld; then
        echo -e "${GREEN}Firewall is active.${NC}"
    else
        echo -e "${RED}Firewall is inactive.${NC}"
    fi
}

# Scan for rootkits
scan_for_rootkits() {
    echo -e "${GREEN}Scanning for rootkits...${NC}"

    if command -v rkhunter > /dev/null 2>&1; then
        sudo rkhunter --check --sk
    else
        echo -e "${YELLOW}rkhunter not installed. Consider running 'sudo dnf install rkhunter'.${NC}"
    fi
}

# Check for weak passwords
check_weak_passwords() {
    echo -e "${GREEN}Checking for weak passwords...${NC}"

    if command -v john > /dev/null 2>&1; then
        sudo john --show /etc/shadow
    else
        echo -e "${YELLOW}John the Ripper not installed. Consider running 'sudo dnf install john'.${NC}"
    fi
}

# Execute selected functions
$display_updates && check_updates
$firewall_status && check_firewall
$scan_rootkits && scan_for_rootkits
$check_weak_passwords && check_weak_passwords

