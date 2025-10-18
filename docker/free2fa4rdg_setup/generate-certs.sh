#!/bin/bash

# generate-certs.sh
# Copyright (C) 2025 Voloskov Aleksandr Nikolaevich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

set -Eeuo pipefail

# Create directories for CA root certificate
mkdir -p /certs/rootca /certs/rootpca

# CA root certificate parameters
CA_KEY="/certs/rootpca/ca.key" # Path for the private key
CA_CERT="/certs/rootca/ca.crt" # Path for the public key (certificate)
CA_SUBJECT="/CN=free2fa4rdg"
CA_EXPIRY_DAYS=${CA_EXPIRY_DAYS:-5475} # Default to 15 years if not set

# Function for logging
log() {
    # Date and time format: YYYY-MM-DD HH:MM:SS
    local level=${1:-INFO}
    local message=${2:-}
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - free2fa4rdg_setup - $level - $message"
    return 0
}

# Check certificate expiry (returns 0 if the certificate is valid for more than 30 days)
check_cert_expiry() {
    local cert=$1
    log "INFO" "Checking expiry for certificate: $cert"

    if [[ -f "$cert" ]]; then
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)
        # Convert the expiry date to a format acceptable by the date command
        local formatted_expiry_date
        if ! formatted_expiry_date=$(date -d "${expiry_date// GMT/}" +%s 2>/dev/null); then
            log "INFO" "Error processing expiry date: $expiry_date"
            return 1
        fi

        local current_seconds diff_seconds days_left
        current_seconds=$(date +%s)
        diff_seconds=$((formatted_expiry_date - current_seconds))
        days_left=$((diff_seconds / 86400))
        log "INFO" "Days until expiry: $days_left"

        if (( days_left > 30 )); then
            log "INFO" "Certificate is valid for more than 30 days."
            return 0
        else
            log "INFO" "Certificate is valid for less than 30 days."
            return 1
        fi
    else
        log "INFO" "Certificate not found: $cert"
        return 1
    fi
}

# Function to generate certificates for microservices
generate_service_cert() {
    local service=$1
    local service_expiry_days=${2:-365} # Default to 1 year if not set
    SERVICE_DIR="/certs/${service}"
    mkdir -p "$SERVICE_DIR"
    SERVICE_KEY="${SERVICE_DIR}/${service}.key"
    SERVICE_CSR="${SERVICE_DIR}/${service}.csr"
    SERVICE_CERT="${SERVICE_DIR}/${service}.crt"
    SERVICE_CONFIG="${SERVICE_DIR}/${service}.cnf"

    # Create a config for the certificate with SAN (Subject Alternative Name)
    echo "[req]" >"$SERVICE_CONFIG"
    echo "distinguished_name = req_distinguished_name" >>"$SERVICE_CONFIG"
    echo "req_extensions = v3_req" >>"$SERVICE_CONFIG"
    echo "prompt = no" >>"$SERVICE_CONFIG"
    echo "" >>"$SERVICE_CONFIG"
    echo "[req_distinguished_name]" >>"$SERVICE_CONFIG"
    echo "CN = $service" >>"$SERVICE_CONFIG"
    echo "" >>"$SERVICE_CONFIG"
    echo "[v3_req]" >>"$SERVICE_CONFIG"
    echo "keyUsage = digitalSignature, keyEncipherment, keyAgreement" >>"$SERVICE_CONFIG"
    echo "extendedKeyUsage = serverAuth, clientAuth" >>"$SERVICE_CONFIG"
    echo "subjectAltName = @alt_names" >>"$SERVICE_CONFIG"
    echo "" >>"$SERVICE_CONFIG"
    echo "[alt_names]" >>"$SERVICE_CONFIG"
    echo "DNS.1 = $service" >>"$SERVICE_CONFIG"
    if [[ -n ${ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML:-} ]]; then
        echo "DNS.2 = $ADDITIONAL_DNS_NAME_FOR_ADMIN_HTML" >>"$SERVICE_CONFIG"
    fi

    if check_cert_expiry "$SERVICE_CERT"; then
        log "INFO" "Certificate for $service is valid for more than 30 days and does not require renewal."
    else
        log "INFO" "Generating/updating certificate for $service."
        # Generate a key
        openssl genrsa -out "$SERVICE_KEY" 2048
        # Generate a CSR using the configuration
        openssl req -new -key "$SERVICE_KEY" -out "$SERVICE_CSR" -config "$SERVICE_CONFIG"
        # Sign the certificate using the CA root
        openssl x509 -req -in "$SERVICE_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$SERVICE_CERT" -days "$service_expiry_days" -sha256 -extfile "$SERVICE_CONFIG" -extensions v3_req
    fi
    return 0
}

# Generate/update the CA root certificate if it does not exist or is expired
if ! check_cert_expiry "$CA_CERT"; then
    log "INFO" "Generating/updating the CA root certificate."
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -x509 -new -key "$CA_KEY" -sha256 -days "$CA_EXPIRY_DAYS" -out "$CA_CERT" -subj "$CA_SUBJECT"
    # Convert the CA root public certificate to DER format for Windows
    openssl x509 -inform PEM -in "$CA_CERT" -outform DER -out /certs/rootca/ca.der
fi

# Generate/update certificates for each microservice
for service in free2fa4rdg_admin_api free2fa4rdg_api; do
    generate_service_cert "$service" "$CA_EXPIRY_DAYS"
done
generate_service_cert "free2fa4rdg_admin_html" "$CA_EXPIRY_DAYS"

log "INFO" "Waiting for admin api availability"
until curl -s --cacert /certs/rootca/ca.crt -o /dev/null -w '%{http_code}' https://free2fa4rdg_admin_api:8000/health | grep -q "200"; do
    sleep 5
done

log "INFO" "All done! Quit."
