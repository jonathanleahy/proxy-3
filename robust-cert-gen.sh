#!/bin/bash
# robust-cert-gen.sh - Robust certificate generation with multiple fallback methods

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 Robust Certificate Generation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Clean up everything
echo -e "${YELLOW}Step 1: Complete cleanup...${NC}"
docker compose -f docker-compose-transparent.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down -v 2>/dev/null || true
docker compose -f docker-compose-simple.yml down -v 2>/dev/null || true
docker compose -f docker-compose-with-certs.yml down -v 2>/dev/null || true
docker compose -f docker-compose-cert-gen.yml down -v 2>/dev/null || true
docker stop app transparent-proxy mock-viewer cert-generator 2>/dev/null || true
docker rm app transparent-proxy mock-viewer cert-generator 2>/dev/null || true
rm -rf ./certs ./temp-certs 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 2: Create certificate directory
echo -e "${YELLOW}Step 2: Creating certificate directory...${NC}"
mkdir -p ./certs
chmod 777 ./certs  # Temporarily make it writable by anyone
echo -e "${GREEN}✅ Directory created: ./certs${NC}"
echo ""

# METHOD 1: Direct container run with explicit commands
echo -e "${YELLOW}Method 1: Direct certificate generation...${NC}"
docker run --rm \
    -v "$(pwd)/certs:/certs" \
    --entrypoint sh \
    mitmproxy/mitmproxy:latest \
    -c "
    echo 'Starting certificate generation...'
    cd /home/mitmproxy
    
    # Method 1a: Run mitmdump
    echo 'Running mitmdump...'
    timeout 5 mitmdump 2>/dev/null || true
    
    # Method 1b: Run mitmproxy
    echo 'Running mitmproxy...'
    timeout 5 mitmproxy --no-server 2>/dev/null || true
    
    # Check if certificates exist
    echo 'Checking for certificates...'
    if [ -d /home/mitmproxy/.mitmproxy ]; then
        echo 'Directory exists. Contents:'
        ls -la /home/mitmproxy/.mitmproxy/
        
        # Copy any pem files found
        if ls /home/mitmproxy/.mitmproxy/*.pem 1>/dev/null 2>&1; then
            echo 'Copying certificates to /certs...'
            cp /home/mitmproxy/.mitmproxy/*.pem /certs/ || true
            cp /home/mitmproxy/.mitmproxy/*.p12 /certs/ 2>/dev/null || true
            chmod 644 /certs/* 2>/dev/null || true
            echo 'Files copied to /certs:'
            ls -la /certs/
        else
            echo 'No .pem files found'
        fi
    else
        echo 'Directory /home/mitmproxy/.mitmproxy does not exist'
    fi
    "

# Check if Method 1 worked
if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Method 1 successful!${NC}"
else
    echo -e "${YELLOW}Method 1 failed, trying Method 2...${NC}"
    echo ""
    
    # METHOD 2: Run container in background and copy files
    echo -e "${YELLOW}Method 2: Background container generation...${NC}"
    
    # Start a mitmproxy container
    docker run -d --name cert-gen mitmproxy/mitmproxy:latest mitmdump
    
    # Wait for it to initialize
    echo "Waiting for container to generate certificates..."
    sleep 5
    
    # Try to copy certificates from the running container
    echo "Attempting to copy certificates from container..."
    docker exec cert-gen sh -c "ls -la /home/mitmproxy/.mitmproxy/" || echo "Failed to list directory"
    
    # Copy certificates
    docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ./certs/ 2>/dev/null || echo "Failed to copy mitmproxy-ca-cert.pem"
    docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.cer ./certs/ 2>/dev/null || echo "Failed to copy mitmproxy-ca-cert.cer"
    docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca.pem ./certs/ 2>/dev/null || echo "Failed to copy mitmproxy-ca.pem"
    docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.p12 ./certs/ 2>/dev/null || echo "Failed to copy mitmproxy-ca-cert.p12"
    
    # Stop and remove container
    docker stop cert-gen 2>/dev/null
    docker rm cert-gen 2>/dev/null
    
    if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
        echo -e "${GREEN}✅ Method 2 successful!${NC}"
    else
        echo -e "${YELLOW}Method 2 failed, trying Method 3...${NC}"
        echo ""
        
        # METHOD 3: Create certificates manually with openssl
        echo -e "${YELLOW}Method 3: Manual certificate generation with OpenSSL...${NC}"
        
        # Generate a self-signed CA certificate
        openssl req -new -x509 -days 365 -nodes \
            -keyout ./certs/mitmproxy-ca.key \
            -out ./certs/mitmproxy-ca-cert.pem \
            -subj "/C=US/ST=State/L=City/O=Mitmproxy/CN=mitmproxy" 2>/dev/null
        
        if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
            echo -e "${GREEN}✅ Method 3 successful (manual generation)!${NC}"
            # Also create the combined file that mitmproxy expects
            cat ./certs/mitmproxy-ca.key ./certs/mitmproxy-ca-cert.pem > ./certs/mitmproxy-ca.pem
        else
            echo -e "${RED}❌ All methods failed${NC}"
        fi
    fi
fi

# Final check
echo ""
echo -e "${YELLOW}Final verification...${NC}"
if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificate exists!${NC}"
    
    # Fix permissions
    chmod 755 ./certs
    chmod 644 ./certs/* 2>/dev/null || true
    
    echo ""
    echo "Certificate files in ./certs:"
    ls -la ./certs/
    echo ""
    
    # Verify the certificate
    echo "Certificate verification:"
    if command -v openssl >/dev/null 2>&1; then
        openssl x509 -in ./certs/mitmproxy-ca-cert.pem -noout -text | head -10
    else
        echo "First few lines of certificate:"
        head -5 ./certs/mitmproxy-ca-cert.pem
    fi
else
    echo -e "${RED}❌ No certificate found after all attempts${NC}"
    echo ""
    echo "Manual fallback instructions:"
    echo "1. Install mitmproxy locally: pip install mitmproxy"
    echo "2. Run: mitmdump --version"
    echo "3. Copy certificates: cp ~/.mitmproxy/*.pem ./certs/"
    echo ""
    echo "OR download pre-generated certificates:"
    echo "1. Start any mitmproxy container on another machine"
    echo "2. Copy the certificates from ~/.mitmproxy/"
    echo "3. Place them in ./certs/ directory here"
    exit 1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Certificate Generation Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Certificates are in: ./certs/"
echo ""
echo "Now you can run the system with these certificates:"
echo "1. Use any docker-compose that mounts ./certs:/certs"
echo "2. Set SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem in your apps"
echo ""
echo "Quick test:"
echo "  docker run --rm -v \$(pwd)/certs:/certs alpine cat /certs/mitmproxy-ca-cert.pem | head -2"
echo ""