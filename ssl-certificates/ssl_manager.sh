#!/bin/bash

# SSL Certificate Manager
# Comprehensive SSL/TLS certificate management tool
# Version: 1.0
# Author: System Engineering Team

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
DEFAULT_KEY_SIZE=2048
DEFAULT_DAYS=365
DEFAULT_COUNTRY="US"
DEFAULT_STATE="State"
DEFAULT_CITY="City"
DEFAULT_ORG="Organization"
DEFAULT_OU="IT Department"

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to print usage
usage() {
    cat << EOF
SSL Certificate Manager - Comprehensive SSL/TLS certificate management tool

Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    generate-key        Generate a private key
    generate-csr        Generate a Certificate Signing Request
    generate-cert       Generate a self-signed certificate
    generate-ca         Generate Certificate Authority
    sign-cert           Sign a certificate with CA
    validate            Validate certificate files
    info                Display certificate information
    convert             Convert certificate formats
    check-expiry        Check certificate expiration
    test-ssl            Test SSL/TLS configuration
    bundle              Create certificate bundle
    revoke              Generate Certificate Revocation List

OPTIONS:
    --domain DOMAIN         Domain name (required for most operations)
    --key-file FILE         Private key file path
    --csr-file FILE         CSR file path
    --cert-file FILE        Certificate file path
    --ca-cert FILE          CA certificate file
    --ca-key FILE           CA private key file
    --key-size SIZE         Key size in bits (default: $DEFAULT_KEY_SIZE)
    --days DAYS             Certificate validity in days (default: $DEFAULT_DAYS)
    --country CODE          Country code (default: $DEFAULT_COUNTRY)
    --state STATE           State/Province (default: $DEFAULT_STATE)
    --city CITY             City (default: $DEFAULT_CITY)
    --org ORGANIZATION      Organization (default: $DEFAULT_ORG)
    --ou UNIT               Organizational Unit (default: $DEFAULT_OU)
    --email EMAIL           Email address
    --san DOMAINS           Subject Alternative Names (comma-separated)
    --password PASSWORD     Private key password
    --output-dir DIR        Output directory (default: current directory)
    --format FORMAT         Output format (PEM, DER, PKCS12)
    --host HOST             Remote host for SSL testing
    --port PORT             Port for SSL testing (default: 443)
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    # Generate private key
    $0 generate-key --domain example.com --key-size 4096

    # Generate CSR
    $0 generate-csr --domain example.com --key-file example.com.key

    # Generate self-signed certificate
    $0 generate-cert --domain example.com --days 365

    # Generate CA certificate
    $0 generate-ca --domain "My CA" --days 3650

    # Sign certificate with CA
    $0 sign-cert --csr-file server.csr --ca-cert ca.crt --ca-key ca.key

    # Validate certificate
    $0 validate --cert-file example.com.crt --key-file example.com.key

    # Check certificate info
    $0 info --cert-file example.com.crt

    # Test remote SSL
    $0 test-ssl --host example.com --port 443

    # Check expiration
    $0 check-expiry --cert-file example.com.crt

EOF
}

# Function to generate private key
generate_key() {
    local domain="$1"
    local key_size="$2"
    local output_dir="$3"
    local password="$4"
    
    local key_file="${output_dir}/${domain}.key"
    
    print_color $BLUE "Generating private key for $domain..."
    
    if [[ -n "$password" ]]; then
        openssl genrsa -aes256 -passout pass:"$password" -out "$key_file" "$key_size"
    else
        openssl genrsa -out "$key_file" "$key_size"
    fi
    
    chmod 600 "$key_file"
    print_color $GREEN "Private key generated: $key_file"
}

# Function to generate CSR
generate_csr() {
    local domain="$1"
    local key_file="$2"
    local output_dir="$3"
    local country="$4"
    local state="$5"
    local city="$6"
    local org="$7"
    local ou="$8"
    local email="$9"
    local san="${10}"
    local password="${11}"
    
    local csr_file="${output_dir}/${domain}.csr"
    local config_file="${output_dir}/${domain}_csr.conf"
    
    # Create CSR configuration file
    cat > "$config_file" << EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = $country
ST = $state
L = $city
O = $org
OU = $ou
CN = $domain
EOF

    if [[ -n "$email" ]]; then
        echo "emailAddress = $email" >> "$config_file"
    fi

    if [[ -n "$san" ]]; then
        cat >> "$config_file" << EOF

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
EOF
        IFS=',' read -ra DOMAINS <<< "$san"
        local i=1
        for domain_name in "${DOMAINS[@]}"; do
            echo "DNS.$i = $(echo "$domain_name" | xargs)" >> "$config_file"
            ((i++))
        done
    fi
    
    print_color $BLUE "Generating CSR for $domain..."
    
    if [[ -n "$password" ]]; then
        openssl req -new -key "$key_file" -out "$csr_file" -config "$config_file" -passin pass:"$password"
    else
        openssl req -new -key "$key_file" -out "$csr_file" -config "$config_file"
    fi
    
    print_color $GREEN "CSR generated: $csr_file"
    print_color $YELLOW "Configuration file: $config_file"
}

# Function to generate self-signed certificate
generate_cert() {
    local domain="$1"
    local days="$2"
    local output_dir="$3"
    local key_size="$4"
    local country="$5"
    local state="$6"
    local city="$7"
    local org="$8"
    local ou="$9"
    local email="${10}"
    local san="${11}"
    local password="${12}"
    
    local key_file="${output_dir}/${domain}.key"
    local cert_file="${output_dir}/${domain}.crt"
    local config_file="${output_dir}/${domain}_cert.conf"
    
    # Generate key if it doesn't exist
    if [[ ! -f "$key_file" ]]; then
        generate_key "$domain" "$key_size" "$output_dir" "$password"
    fi
    
    # Create certificate configuration file
    cat > "$config_file" << EOF
[req]
default_bits = $key_size
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[req_distinguished_name]
C = $country
ST = $state
L = $city
O = $org
OU = $ou
CN = $domain
EOF

    if [[ -n "$email" ]]; then
        echo "emailAddress = $email" >> "$config_file"
    fi

    if [[ -n "$san" ]]; then
        cat >> "$config_file" << EOF

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
EOF
        IFS=',' read -ra DOMAINS <<< "$san"
        local i=1
        for domain_name in "${DOMAINS[@]}"; do
            echo "DNS.$i = $(echo "$domain_name" | xargs)" >> "$config_file"
            ((i++))
        done
    fi
    
    print_color $BLUE "Generating self-signed certificate for $domain..."
    
    if [[ -n "$password" ]]; then
        openssl req -new -x509 -key "$key_file" -out "$cert_file" -days "$days" -config "$config_file" -passin pass:"$password"
    else
        openssl req -new -x509 -key "$key_file" -out "$cert_file" -days "$days" -config "$config_file"
    fi
    
    print_color $GREEN "Self-signed certificate generated: $cert_file"
}

# Function to generate CA certificate
generate_ca() {
    local ca_name="$1"
    local days="$2"
    local output_dir="$3"
    local key_size="$4"
    local country="$5"
    local state="$6"
    local city="$7"
    local org="$8"
    local password="$9"
    
    local ca_key="${output_dir}/ca.key"
    local ca_cert="${output_dir}/ca.crt"
    local config_file="${output_dir}/ca.conf"
    
    # Create CA configuration
    cat > "$config_file" << EOF
[req]
default_bits = $key_size
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[req_distinguished_name]
C = $country
ST = $state
L = $city
O = $org
OU = Certificate Authority
CN = $ca_name

[v3_ca]
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
    
    print_color $BLUE "Generating CA private key..."
    if [[ -n "$password" ]]; then
        openssl genrsa -aes256 -passout pass:"$password" -out "$ca_key" "$key_size"
    else
        openssl genrsa -out "$ca_key" "$key_size"
    fi
    chmod 600 "$ca_key"
    
    print_color $BLUE "Generating CA certificate..."
    if [[ -n "$password" ]]; then
        openssl req -new -x509 -key "$ca_key" -out "$ca_cert" -days "$days" -config "$config_file" -passin pass:"$password"
    else
        openssl req -new -x509 -key "$ca_key" -out "$ca_cert" -days "$days" -config "$config_file"
    fi
    
    print_color $GREEN "CA certificate generated: $ca_cert"
    print_color $GREEN "CA private key: $ca_key"
}

# Function to sign certificate with CA
sign_cert() {
    local csr_file="$1"
    local ca_cert="$2"
    local ca_key="$3"
    local days="$4"
    local output_dir="$5"
    local password="$6"
    
    local basename=$(basename "$csr_file" .csr)
    local cert_file="${output_dir}/${basename}.crt"
    
    print_color $BLUE "Signing certificate with CA..."
    
    if [[ -n "$password" ]]; then
        openssl x509 -req -in "$csr_file" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$cert_file" -days "$days" -passin pass:"$password"
    else
        openssl x509 -req -in "$csr_file" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$cert_file" -days "$days"
    fi
    
    print_color $GREEN "Certificate signed: $cert_file"
}

# Function to validate certificate files
validate_cert() {
    local cert_file="$1"
    local key_file="$2"
    local ca_cert="$3"
    
    print_color $BLUE "Validating certificate files..."
    
    # Check certificate file
    if [[ -f "$cert_file" ]]; then
        if openssl x509 -in "$cert_file" -text -noout > /dev/null 2>&1; then
            print_color $GREEN "✓ Certificate file is valid"
        else
            print_color $RED "✗ Certificate file is invalid"
            return 1
        fi
    fi
    
    # Check private key
    if [[ -f "$key_file" ]]; then
        if openssl rsa -in "$key_file" -check -noout > /dev/null 2>&1; then
            print_color $GREEN "✓ Private key is valid"
        else
            print_color $RED "✗ Private key is invalid"
            return 1
        fi
    fi
    
    # Check if certificate and key match
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
        local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" | openssl md5)
        
        if [[ "$cert_modulus" == "$key_modulus" ]]; then
            print_color $GREEN "✓ Certificate and private key match"
        else
            print_color $RED "✗ Certificate and private key do not match"
            return 1
        fi
    fi
    
    # Verify with CA if provided
    if [[ -f "$ca_cert" && -f "$cert_file" ]]; then
        if openssl verify -CAfile "$ca_cert" "$cert_file" > /dev/null 2>&1; then
            print_color $GREEN "✓ Certificate is valid with CA"
        else
            print_color $RED "✗ Certificate verification failed with CA"
            return 1
        fi
    fi
    
    print_color $GREEN "Certificate validation completed successfully"
}

# Function to display certificate information
cert_info() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        print_color $RED "Certificate file not found: $cert_file"
        return 1
    fi
    
    print_color $BLUE "Certificate Information:"
    echo "========================"
    
    # Basic certificate info
    openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Subject:"
    openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Issuer:"
    openssl x509 -in "$cert_file" -text -noout | grep -A 2 "Validity"
    openssl x509 -in "$cert_file" -text -noout | grep -A 10 "Subject Alternative Name" || true
    
    # Certificate fingerprints
    echo ""
    print_color $CYAN "Fingerprints:"
    echo "SHA256: $(openssl x509 -in "$cert_file" -fingerprint -sha256 -noout | cut -d= -f2)"
    echo "SHA1:   $(openssl x509 -in "$cert_file" -fingerprint -sha1 -noout | cut -d= -f2)"
    echo "MD5:    $(openssl x509 -in "$cert_file" -fingerprint -md5 -noout | cut -d= -f2)"
}

# Function to check certificate expiration
check_expiry() {
    local cert_file="$1"
    local warn_days="${2:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        print_color $RED "Certificate file not found: $cert_file"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    print_color $BLUE "Certificate Expiration Check:"
    echo "Expires: $expiry_date"
    echo "Days until expiry: $days_until_expiry"
    
    if [[ $days_until_expiry -lt 0 ]]; then
        print_color $RED "⚠️  Certificate has EXPIRED!"
        return 1
    elif [[ $days_until_expiry -lt $warn_days ]]; then
        print_color $YELLOW "⚠️  Certificate expires soon (within $warn_days days)"
        return 1
    else
        print_color $GREEN "✓ Certificate is valid for $days_until_expiry more days"
    fi
}

# Function to test SSL/TLS configuration
test_ssl() {
    local host="$1"
    local port="$2"
    
    print_color $BLUE "Testing SSL/TLS configuration for $host:$port..."
    
    # Test connection
    if timeout 10 openssl s_client -connect "$host:$port" -servername "$host" < /dev/null > /dev/null 2>&1; then
        print_color $GREEN "✓ SSL/TLS connection successful"
    else
        print_color $RED "✗ SSL/TLS connection failed"
        return 1
    fi
    
    # Get certificate info
    local cert_info=$(echo | timeout 10 openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null)
    
    if [[ -n "$cert_info" ]]; then
        echo "$cert_info" | grep -A 2 "Subject:"
        echo "$cert_info" | grep -A 2 "Issuer:"
        echo "$cert_info" | grep -A 2 "Validity"
        
        # Check expiration
        local expiry_date=$(echo | timeout 10 openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            local expiry_epoch=$(date -d "$expiry_date" +%s)
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 ]]; then
                print_color $YELLOW "⚠️  Certificate expires in $days_until_expiry days"
            else
                print_color $GREEN "✓ Certificate valid for $days_until_expiry days"
            fi
        fi
    fi
    
    # Test supported protocols and ciphers
    print_color $CYAN "Testing supported protocols..."
    for protocol in ssl3 tls1 tls1_1 tls1_2 tls1_3; do
        if timeout 5 openssl s_client -connect "$host:$port" -$protocol < /dev/null > /dev/null 2>&1; then
            print_color $GREEN "✓ $protocol supported"
        else
            print_color $RED "✗ $protocol not supported"
        fi
    done
}

# Function to convert certificate formats
convert_cert() {
    local input_file="$1"
    local output_file="$2"
    local format="$3"
    local password="$4"
    
    print_color $BLUE "Converting certificate format to $format..."
    
    case "$format" in
        "PEM")
            if [[ "$input_file" == *.p12 ]] || [[ "$input_file" == *.pfx ]]; then
                if [[ -n "$password" ]]; then
                    openssl pkcs12 -in "$input_file" -out "$output_file" -nodes -passin pass:"$password"
                else
                    openssl pkcs12 -in "$input_file" -out "$output_file" -nodes
                fi
            else
                cp "$input_file" "$output_file"
            fi
            ;;
        "DER")
            openssl x509 -in "$input_file" -outform DER -out "$output_file"
            ;;
        "PKCS12"|"P12")
            if [[ -n "$password" ]]; then
                openssl pkcs12 -export -out "$output_file" -in "$input_file" -passout pass:"$password"
            else
                openssl pkcs12 -export -out "$output_file" -in "$input_file" -passout pass:
            fi
            ;;
        *)
            print_color $RED "Unsupported format: $format"
            return 1
            ;;
    esac
    
    print_color $GREEN "Certificate converted: $output_file"
}

# Function to create certificate bundle
create_bundle() {
    local cert_file="$1"
    local intermediate_file="$2"
    local ca_file="$3"
    local output_file="$4"
    
    print_color $BLUE "Creating certificate bundle..."
    
    # Start with the server certificate
    cat "$cert_file" > "$output_file"
    
    # Add intermediate certificate if provided
    if [[ -n "$intermediate_file" && -f "$intermediate_file" ]]; then
        echo "" >> "$output_file"
        cat "$intermediate_file" >> "$output_file"
    fi
    
    # Add CA certificate if provided
    if [[ -n "$ca_file" && -f "$ca_file" ]]; then
        echo "" >> "$output_file"
        cat "$ca_file" >> "$output_file"
    fi
    
    print_color $GREEN "Certificate bundle created: $output_file"
}

# Main function
main() {
    local command=""
    local domain=""
    local key_file=""
    local csr_file=""
    local cert_file=""
    local ca_cert=""
    local ca_key=""
    local key_size="$DEFAULT_KEY_SIZE"
    local days="$DEFAULT_DAYS"
    local country="$DEFAULT_COUNTRY"
    local state="$DEFAULT_STATE"
    local city="$DEFAULT_CITY"
    local org="$DEFAULT_ORG"
    local ou="$DEFAULT_OU"
    local email=""
    local san=""
    local password=""
    local output_dir="."
    local format="PEM"
    local host=""
    local port="443"
    local verbose=false
    local warn_days="30"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            generate-key|generate-csr|generate-cert|generate-ca|sign-cert|validate|info|convert|check-expiry|test-ssl|bundle|revoke)
                command="$1"
                ;;
            --domain)
                domain="$2"
                shift
                ;;
            --key-file)
                key_file="$2"
                shift
                ;;
            --csr-file)
                csr_file="$2"
                shift
                ;;
            --cert-file)
                cert_file="$2"
                shift
                ;;
            --ca-cert)
                ca_cert="$2"
                shift
                ;;
            --ca-key)
                ca_key="$2"
                shift
                ;;
            --key-size)
                key_size="$2"
                shift
                ;;
            --days)
                days="$2"
                shift
                ;;
            --country)
                country="$2"
                shift
                ;;
            --state)
                state="$2"
                shift
                ;;
            --city)
                city="$2"
                shift
                ;;
            --org)
                org="$2"
                shift
                ;;
            --ou)
                ou="$2"
                shift
                ;;
            --email)
                email="$2"
                shift
                ;;
            --san)
                san="$2"
                shift
                ;;
            --password)
                password="$2"
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift
                ;;
            --format)
                format="$2"
                shift
                ;;
            --host)
                host="$2"
                shift
                ;;
            --port)
                port="$2"
                shift
                ;;
            --warn-days)
                warn_days="$2"
                shift
                ;;
            --verbose)
                verbose=true
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
    
    # Validate command
    if [[ -z "$command" ]]; then
        print_color $RED "Error: No command specified"
        usage
        exit 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Execute command
    case "$command" in
        "generate-key")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required"; exit 1; }
            generate_key "$domain" "$key_size" "$output_dir" "$password"
            ;;
        "generate-csr")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required"; exit 1; }
            [[ -z "$key_file" ]] && key_file="${output_dir}/${domain}.key"
            [[ ! -f "$key_file" ]] && { print_color $RED "Error: Key file not found: $key_file"; exit 1; }
            generate_csr "$domain" "$key_file" "$output_dir" "$country" "$state" "$city" "$org" "$ou" "$email" "$san" "$password"
            ;;
        "generate-cert")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required"; exit 1; }
            generate_cert "$domain" "$days" "$output_dir" "$key_size" "$country" "$state" "$city" "$org" "$ou" "$email" "$san" "$password"
            ;;
        "generate-ca")
            [[ -z "$domain" ]] && { print_color $RED "Error: --domain is required for CA name"; exit 1; }
            generate_ca "$domain" "$days" "$output_dir" "$key_size" "$country" "$state" "$city" "$org" "$password"
            ;;
        "sign-cert")
            [[ -z "$csr_file" ]] && { print_color $RED "Error: --csr-file is required"; exit 1; }
            [[ -z "$ca_cert" ]] && { print_color $RED "Error: --ca-cert is required"; exit 1; }
            [[ -z "$ca_key" ]] && { print_color $RED "Error: --ca-key is required"; exit 1; }
            sign_cert "$csr_file" "$ca_cert" "$ca_key" "$days" "$output_dir" "$password"
            ;;
        "validate")
            validate_cert "$cert_file" "$key_file" "$ca_cert"
            ;;
        "info")
            [[ -z "$cert_file" ]] && { print_color $RED "Error: --cert-file is required"; exit 1; }
            cert_info "$cert_file"
            ;;
        "check-expiry")
            [[ -z "$cert_file" ]] && { print_color $RED "Error: --cert-file is required"; exit 1; }
            check_expiry "$cert_file" "$warn_days"
            ;;
        "test-ssl")
            [[ -z "$host" ]] && { print_color $RED "Error: --host is required"; exit 1; }
            test_ssl "$host" "$port"
            ;;
        "convert")
            [[ -z "$cert_file" ]] && { print_color $RED "Error: --cert-file is required"; exit 1; }
            [[ -z "$output_dir" ]] && { print_color $RED "Error: --output-dir is required"; exit 1; }
            local output_file="${output_dir}/converted_cert"
            convert_cert "$cert_file" "$output_file" "$format" "$password"
            ;;
        "bundle")
            [[ -z "$cert_file" ]] && { print_color $RED "Error: --cert-file is required"; exit 1; }
            local bundle_file="${output_dir}/bundle.crt"
            create_bundle "$cert_file" "" "$ca_cert" "$bundle_file"
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
