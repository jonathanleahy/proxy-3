#!/bin/bash

# Script to extract mitmproxy CA certificate for client trust

echo "🔐 mitmproxy CA Certificate Extractor"
echo "======================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Start mitmproxy if not running
echo "Starting mitmproxy container to generate certificates..."
docker-compose --profile mitm up -d mitm-proxy 2>/dev/null || docker compose --profile mitm up -d mitm-proxy

# Wait for certificates to be generated
echo "Waiting for certificate generation..."
sleep 5

# Create certs directory
mkdir -p certs

# Extract the CA certificate
echo "Extracting CA certificate..."

# First, check if container is running and exec into it
CONTAINER_ID=$(docker ps -q -f "name=mitm-proxy")
if [ -n "$CONTAINER_ID" ]; then
    echo "Found running mitmproxy container, extracting certificate..."
    docker cp ${CONTAINER_ID}:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem 2>/dev/null
else
    # Try extracting from volume
    echo "Container not running, trying to extract from volume..."
    docker run --rm -v proxy-3_mitmproxy-certs:/certs:ro -v $(pwd)/certs:/output busybox \
        sh -c "cp /certs/mitmproxy-ca-cert.pem /output/mitmproxy-ca.pem 2>/dev/null || echo 'Cert not found in volume'"
    
    # Try with different volume name
    if [ ! -f "certs/mitmproxy-ca.pem" ]; then
        docker run --rm -v $(basename $(pwd))_mitmproxy-certs:/certs:ro -v $(pwd)/certs:/output busybox \
            sh -c "cp /certs/mitmproxy-ca-cert.pem /output/mitmproxy-ca.pem 2>/dev/null"
    fi
fi

if [ -f "certs/mitmproxy-ca.pem" ]; then
    echo "✅ CA certificate extracted to: certs/mitmproxy-ca.pem"
    echo ""
    echo "📋 How to use this certificate:"
    echo ""
    echo "1. For curl (no admin required):"
    echo "   curl --cacert certs/mitmproxy-ca.pem -x http://localhost:8080 https://example.com"
    echo ""
    echo "2. For applications (no admin required):"
    echo "   export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem"
    echo "   export REQUESTS_CA_BUNDLE=$(pwd)/certs/mitmproxy-ca.pem"
    echo "   export NODE_EXTRA_CA_CERTS=$(pwd)/certs/mitmproxy-ca.pem"
    echo ""
    echo "3. For Go applications:"
    echo "   export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem"
    echo "   export HTTP_PROXY=http://localhost:8080"
    echo "   export HTTPS_PROXY=http://localhost:8080"
    echo ""
    echo "4. For system-wide trust (requires admin):"
    echo "   macOS:  security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain certs/mitmproxy-ca.pem"
    echo "   Linux:  sudo cp certs/mitmproxy-ca.pem /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
    echo "   Windows: certutil -addstore -user Root certs/mitmproxy-ca.pem"
else
    echo "❌ Failed to extract certificate. Make sure mitmproxy container is running."
    echo "Try: docker-compose --profile mitm up mitm-proxy"
fi