#!/bin/bash

# Network Diagnostics Script
# Usage: ./network_diagnostics.sh [--host hostname] [--port port] [--scan] [--trace] [--dns]

set -euo pipefail

# Default values
TARGET_HOST=""
TARGET_PORT=""
SCAN_PORTS=false
TRACE_ROUTE=false
DNS_CHECK=false
INTERFACE=""
VERBOSE=false
OUTPUT_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            TARGET_HOST="$2"
            shift 2
            ;;
        --port)
            TARGET_PORT="$2"
            shift 2
            ;;
        --scan)
            SCAN_PORTS=true
            shift
            ;;
        --trace)
            TRACE_ROUTE=true
            shift
            ;;
        --dns)
            DNS_CHECK=true
            shift
            ;;
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [options]

Options:
  --host HOSTNAME      Target hostname or IP address
  --port PORT         Target port number
  --scan              Perform port scan on target host
  --trace             Perform traceroute to target host
  --dns               Perform DNS diagnostics
  --interface IFACE   Specific network interface to use
  --verbose           Enable verbose output
  --output FILE       Save output to file
  -h, --help          Show this help message

Examples:
  $0 --host google.com --port 80
  $0 --host 192.168.1.1 --scan --trace
  $0 --dns --verbose
  $0 --host example.com --output network_report.txt
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

# Output function (to file and/or stdout)
output() {
    local message="$1"
    echo -e "$message"
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"
    fi
}

# Verbose output
verbose_output() {
    if [[ "$VERBOSE" == "true" ]]; then
        output "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check network connectivity
check_connectivity() {
    output "${BLUE}=== Network Connectivity Check ===${NC}"
    
    # Check local network interface
    if [[ -n "$INTERFACE" ]]; then
        output "Checking interface: $INTERFACE"
        if ip addr show "$INTERFACE" >/dev/null 2>&1; then
            local ip_addr
            ip_addr=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+' | head -1)
            output "Interface $INTERFACE IP: ${GREEN}$ip_addr${NC}"
        else
            output "Interface $INTERFACE: ${RED}Not found${NC}"
        fi
    else
        output "Active network interfaces:"
        ip -brief addr show | grep UP | while read -r iface state addrs; do
            output "  $iface: ${GREEN}$state${NC} ($addrs)"
        done
    fi
    
    # Check default gateway
    local gateway
    gateway=$(ip route show default | grep -oP 'via \K[\d.]+' | head -1)
    if [[ -n "$gateway" ]]; then
        output "Default gateway: $gateway"
        if ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
            output "Gateway connectivity: ${GREEN}OK${NC}"
        else
            output "Gateway connectivity: ${RED}FAILED${NC}"
        fi
    else
        output "Default gateway: ${RED}Not found${NC}"
    fi
    
    # Check internet connectivity
    output "Testing internet connectivity..."
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            output "  $host: ${GREEN}OK${NC}"
        else
            output "  $host: ${RED}FAILED${NC}"
        fi
    done
}

# DNS diagnostics
dns_diagnostics() {
    output "${BLUE}=== DNS Diagnostics ===${NC}"
    
    # Show DNS servers
    output "DNS servers:"
    if [[ -f /etc/resolv.conf ]]; then
        grep -E '^nameserver' /etc/resolv.conf | while read -r _ dns_server; do
            output "  $dns_server"
        done
    fi
    
    # Test DNS resolution
    local test_domains=("google.com" "github.com" "stackoverflow.com")
    for domain in "${test_domains[@]}"; do
        verbose_output "Testing DNS resolution for $domain"
        if nslookup "$domain" >/dev/null 2>&1; then
            local ip_addr
            ip_addr=$(nslookup "$domain" | grep -A1 "Name:" | grep "Address:" | cut -d' ' -f2 | head -1)
            output "  $domain: ${GREEN}$ip_addr${NC}"
        else
            output "  $domain: ${RED}FAILED${NC}"
        fi
    done
    
    # Reverse DNS lookup
    if [[ -n "$TARGET_HOST" ]] && [[ "$TARGET_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        verbose_output "Performing reverse DNS lookup for $TARGET_HOST"
        local hostname
        hostname=$(nslookup "$TARGET_HOST" 2>/dev/null | grep "name =" | cut -d'=' -f2 | tr -d ' ')
        if [[ -n "$hostname" ]]; then
            output "Reverse DNS for $TARGET_HOST: ${GREEN}$hostname${NC}"
        else
            output "Reverse DNS for $TARGET_HOST: ${YELLOW}No PTR record${NC}"
        fi
    fi
}

# Port connectivity test
test_port_connectivity() {
    local host="$1"
    local port="$2"
    
    verbose_output "Testing connectivity to $host:$port"
    
    if command_exists nc; then
        if nc -zv "$host" "$port" 2>&1 | grep -q "succeeded"; then
            return 0
        else
            return 1
        fi
    elif command_exists telnet; then
        if timeout 5 telnet "$host" "$port" 2>&1 | grep -q "Connected"; then
            return 0
        else
            return 1
        fi
    else
        # Fallback using /dev/tcp
        if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

# Port scan
port_scan() {
    local host="$1"
    output "${BLUE}=== Port Scan for $host ===${NC}"
    
    if ! command_exists nc; then
        output "${YELLOW}Warning: netcat not found, using basic connectivity test${NC}"
    fi
    
    # Common ports to scan
    local common_ports=(21 22 23 25 53 80 110 143 443 993 995 3389 5432 3306)
    
    if [[ -n "$TARGET_PORT" ]]; then
        # Scan specific port
        if test_port_connectivity "$host" "$TARGET_PORT"; then
            output "Port $TARGET_PORT: ${GREEN}OPEN${NC}"
        else
            output "Port $TARGET_PORT: ${RED}CLOSED${NC}"
        fi
    else
        # Scan common ports
        output "Scanning common ports..."
        local open_ports=()
        
        for port in "${common_ports[@]}"; do
            if test_port_connectivity "$host" "$port"; then
                output "Port $port: ${GREEN}OPEN${NC}"
                open_ports+=("$port")
            else
                verbose_output "Port $port: CLOSED"
            fi
        done
        
        if [[ ${#open_ports[@]} -eq 0 ]]; then
            output "No open ports found in common port range"
        else
            output "Open ports: ${open_ports[*]}"
        fi
    fi
}

# Traceroute
perform_traceroute() {
    local host="$1"
    output "${BLUE}=== Traceroute to $host ===${NC}"
    
    if command_exists traceroute; then
        traceroute "$host" 2>&1 | while read -r line; do
            output "$line"
        done
    elif command_exists tracepath; then
        tracepath "$host" 2>&1 | while read -r line; do
            output "$line"
        done
    else
        output "${RED}Error: traceroute/tracepath not found${NC}"
    fi
}

# Network statistics
show_network_stats() {
    output "${BLUE}=== Network Statistics ===${NC}"
    
    # Network interface statistics
    output "Network interface statistics:"
    cat /proc/net/dev | tail -n +3 | while read -r line; do
        local interface=$(echo "$line" | cut -d':' -f1 | tr -d ' ')
        local rx_bytes=$(echo "$line" | awk '{print $2}')
        local tx_bytes=$(echo "$line" | awk '{print $10}')
        
        if [[ "$rx_bytes" -gt 0 || "$tx_bytes" -gt 0 ]]; then
            local rx_mb=$((rx_bytes / 1024 / 1024))
            local tx_mb=$((tx_bytes / 1024 / 1024))
            output "  $interface: RX ${rx_mb}MB, TX ${tx_mb}MB"
        fi
    done
    
    # Connection statistics
    if command_exists ss; then
        output "Connection statistics:"
        local tcp_connections
        tcp_connections=$(ss -t -a | grep -c ESTAB)
        output "  Established TCP connections: $tcp_connections"
        
        local listening_ports
        listening_ports=$(ss -t -l | grep -c LISTEN)
        output "  Listening TCP ports: $listening_ports"
    fi
    
    # ARP table
    output "ARP table (recent entries):"
    arp -a 2>/dev/null | head -10 | while read -r line; do
        output "  $line"
    done
}

# Bandwidth test (simple)
bandwidth_test() {
    output "${BLUE}=== Bandwidth Test ===${NC}"
    
    if command_exists curl; then
        output "Testing download speed..."
        local speed
        speed=$(curl -o /dev/null -s -w '%{speed_download}\n' http://speedtest.wdc01.softlayer.com/downloads/test10.zip)
        local speed_mbps
        speed_mbps=$(echo "$speed / 1024 / 1024 * 8" | bc -l 2>/dev/null | cut -d'.' -f1)
        output "Approximate download speed: ${speed_mbps:-N/A} Mbps"
    else
        output "${YELLOW}curl not available for bandwidth test${NC}"
    fi
}

# Main execution
main() {
    output "${GREEN}Network Diagnostics Tool${NC}"
    output "Started at: $(date)"
    output "Target Host: ${TARGET_HOST:-'Not specified'}"
    output "Target Port: ${TARGET_PORT:-'Not specified'}"
    output ""
    
    # Initialize output file
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "Network Diagnostics Report - $(date)" > "$OUTPUT_FILE"
        echo "===========================================" >> "$OUTPUT_FILE"
    fi
    
    # Basic connectivity check
    check_connectivity
    output ""
    
    # DNS diagnostics
    if [[ "$DNS_CHECK" == "true" ]] || [[ -z "$TARGET_HOST" ]]; then
        dns_diagnostics
        output ""
    fi
    
    # Target host specific tests
    if [[ -n "$TARGET_HOST" ]]; then
        # Ping test
        output "${BLUE}=== Ping Test to $TARGET_HOST ===${NC}"
        if ping -c 4 "$TARGET_HOST" 2>&1; then
            output "Ping test: ${GREEN}SUCCESS${NC}"
        else
            output "Ping test: ${RED}FAILED${NC}"
        fi
        output ""
        
        # Port scan
        if [[ "$SCAN_PORTS" == "true" ]]; then
            port_scan "$TARGET_HOST"
            output ""
        fi
        
        # Specific port test
        if [[ -n "$TARGET_PORT" ]]; then
            output "${BLUE}=== Port Connectivity Test ===${NC}"
            if test_port_connectivity "$TARGET_HOST" "$TARGET_PORT"; then
                output "$TARGET_HOST:$TARGET_PORT: ${GREEN}REACHABLE${NC}"
            else
                output "$TARGET_HOST:$TARGET_PORT: ${RED}UNREACHABLE${NC}"
            fi
            output ""
        fi
        
        # Traceroute
        if [[ "$TRACE_ROUTE" == "true" ]]; then
            perform_traceroute "$TARGET_HOST"
            output ""
        fi
    fi
    
    # Network statistics
    show_network_stats
    output ""
    
    # Bandwidth test
    if [[ "$VERBOSE" == "true" ]]; then
        bandwidth_test
        output ""
    fi
    
    output "${GREEN}Network diagnostics completed${NC}"
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        output "Report saved to: $OUTPUT_FILE"
    fi
}

main "$@"
