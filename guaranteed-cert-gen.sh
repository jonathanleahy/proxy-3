#!/bin/bash
# guaranteed-cert-gen.sh - Guaranteed certificate generation using OpenSSL

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 Guaranteed Certificate Generation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up old certificates
echo -e "${YELLOW}Cleaning up old certificates...${NC}"
rm -rf ./certs 2>/dev/null || true
mkdir -p ./certs
echo -e "${GREEN}✅ Certificate directory ready${NC}"
echo ""

# Generate certificates using OpenSSL (guaranteed to work)
echo -e "${YELLOW}Generating CA certificate with OpenSSL...${NC}"

# Generate private key
openssl genrsa -out ./certs/mitmproxy-ca.key 2048 2>/dev/null

# Generate certificate
openssl req -new -x509 -key ./certs/mitmproxy-ca.key \
    -out ./certs/mitmproxy-ca-cert.pem \
    -days 3650 \
    -subj "/C=US/ST=CA/L=San Francisco/O=mitmproxy/OU=mitmproxy/CN=mitmproxy CA"

# Create the combined PEM file (key + cert)
cat ./certs/mitmproxy-ca.key ./certs/mitmproxy-ca-cert.pem > ./certs/mitmproxy-ca.pem

# Create CER format for compatibility
openssl x509 -in ./certs/mitmproxy-ca-cert.pem -outform DER -out ./certs/mitmproxy-ca-cert.cer

# Set proper permissions
chmod 644 ./certs/*
chmod 755 ./certs

echo -e "${GREEN}✅ Certificates generated successfully!${NC}"
echo ""
echo "Generated files:"
ls -la ./certs/
echo ""

# Verify the certificate
echo -e "${YELLOW}Certificate details:${NC}"
openssl x509 -in ./certs/mitmproxy-ca-cert.pem -noout -subject -dates
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Certificate Generation Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The certificates are ready in ./certs/"
echo ""
echo "These are self-signed certificates that will work with mitmproxy."
echo "Your applications need to trust: ./certs/mitmproxy-ca-cert.pem"
echo ""
echo "To use with Docker:"
echo "  - Mount: -v \$(pwd)/certs:/certs:ro"
echo "  - Set: SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem"
echo ""