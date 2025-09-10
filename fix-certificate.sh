#!/bin/bash
# fix-certificate.sh - Fix bad or unreadable mitmproxy certificate

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 Fixing Certificate Issues${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Stop containers but keep them for inspection
echo -e "${YELLOW}Step 1: Stopping containers...${NC}"
docker stop app transparent-proxy mock-viewer 2>/dev/null || true
echo -e "${GREEN}✅ Containers stopped${NC}"
echo ""

# Step 2: Remove ALL certificate volumes (different docker versions create different names)
echo -e "${YELLOW}Step 2: Removing ALL old certificate volumes...${NC}"
docker volume ls | grep cert | awk '{print $2}' | while read vol; do
    echo "  Removing volume: $vol"
    docker volume rm "$vol" 2>/dev/null || true
done
# Also try specific names
docker volume rm proxy-3_certs 2>/dev/null || true
docker volume rm proxy3_certs 2>/dev/null || true
docker volume rm certs 2>/dev/null || true
echo -e "${GREEN}✅ Certificate volumes cleaned${NC}"
echo ""

# Step 3: Remove containers to ensure clean state
echo -e "${YELLOW}Step 3: Removing old containers...${NC}"
docker rm app transparent-proxy mock-viewer 2>/dev/null || true
docker compose -f docker-compose-transparent.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down -v 2>/dev/null || true
echo -e "${GREEN}✅ Containers removed${NC}"
echo ""

# Step 4: Create fresh certificate directory on host
echo -e "${YELLOW}Step 4: Creating fresh certificate directory...${NC}"
rm -rf ./temp-certs 2>/dev/null || true
mkdir -p ./temp-certs
echo -e "${GREEN}✅ Certificate directory created${NC}"
echo ""

# Step 5: Generate certificate manually using mitmproxy
echo -e "${YELLOW}Step 5: Generating fresh certificate using mitmproxy...${NC}"
docker run --rm -v "$(pwd)/temp-certs:/home/mitmproxy/.mitmproxy" mitmproxy/mitmproxy mitmdump --version >/dev/null 2>&1 || true

# Check if certificate was generated
if [ -f "./temp-certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificate generated successfully${NC}"
    echo "  Location: ./temp-certs/mitmproxy-ca-cert.pem"
    
    # Verify certificate
    openssl x509 -in ./temp-certs/mitmproxy-ca-cert.pem -noout -text | head -5
else
    echo -e "${YELLOW}⚠️  Manual generation failed, will let container generate it${NC}"
fi
echo ""

# Step 6: Update docker-compose to use bind mount for certificates
echo -e "${YELLOW}Step 6: Creating fixed docker-compose configuration...${NC}"
cat > docker-compose-transparent-fixed.yml << 'EOF'
services:
  # Transparent MITM proxy with fixed certificate handling
  transparent-proxy:
    build:
      context: .
      dockerfile: docker/Dockerfile.mitmproxy
    container_name: transparent-proxy
    privileged: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./captured:/captured
      - ./scripts:/scripts:ro
      # Use bind mount for certificates to avoid permission issues
      - ./temp-certs:/certs
    networks:
      capture-net:
        ipv4_address: 10.5.0.2
    ports:
      - "8080:8080"
      - "8084:8084"
    environment:
      # Force mitmproxy to generate certs in /certs
      MITMPROXY_PATH: /certs
    # Ensure certificate is generated and has correct permissions
    entrypoint: |
      sh -c "
      # Create certificate directory if it doesn't exist
      mkdir -p /certs
      
      # If no certificate exists, generate it
      if [ ! -f /certs/mitmproxy-ca-cert.pem ]; then
          echo 'Generating new certificate...'
          # Run mitmdump once to generate certificates
          mitmdump --version
          # Copy generated certificates to /certs
          cp -f /home/mitmproxy/.mitmproxy/mitmproxy-ca*.pem /certs/ 2>/dev/null || true
      fi
      
      # Ensure certificates have correct permissions
      chmod 644 /certs/*.pem 2>/dev/null || true
      
      # Verify certificate
      if [ -f /certs/mitmproxy-ca-cert.pem ]; then
          echo '✅ Certificate ready'
          openssl x509 -in /certs/mitmproxy-ca-cert.pem -noout -subject || echo 'Certificate validation failed'
      else
          echo '❌ Certificate not found!'
      fi
      
      # Continue with normal startup
      /scripts/transparent-entrypoint.sh
      "

  # Application container with fixed certificate mount
  app:
    build:
      context: .
      dockerfile: docker/Dockerfile.app
    container_name: app
    depends_on:
      - transparent-proxy
    network_mode: "service:transparent-proxy"
    volumes:
      - ./:/proxy
      # Use same bind mount for certificates
      - ./temp-certs:/certs:ro
    working_dir: /proxy
    environment:
      TARGET_API: "https://api.github.com"
      # Explicitly set certificate paths
      SSL_CERT_FILE: /certs/mitmproxy-ca-cert.pem
      REQUESTS_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
      NODE_EXTRA_CA_CERTS: /certs/mitmproxy-ca-cert.pem
      CURL_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
    command: |
      sh -c "
      # Wait for certificate
      echo 'Waiting for certificate...'
      while [ ! -f /certs/mitmproxy-ca-cert.pem ]; do
          sleep 1
      done
      
      # Verify certificate is readable
      if openssl x509 -in /certs/mitmproxy-ca-cert.pem -noout -subject >/dev/null 2>&1; then
          echo '✅ Certificate is valid and readable'
      else
          echo '❌ Certificate is invalid or unreadable'
          ls -la /certs/
      fi
      
      echo '🚀 App container ready...'
      tail -f /dev/null
      "

  # Mock viewer remains the same
  mock-viewer:
    build:
      context: .
      dockerfile: docker/Dockerfile.viewer
    container_name: mock-viewer
    volumes:
      - ./configs:/configs:ro
      - ./captured:/captured:ro
    networks:
      capture-net:
        ipv4_address: 10.5.0.3
    ports:
      - "8090:8090"

networks:
  capture-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24

# No volume needed - using bind mount
EOF
echo -e "${GREEN}✅ Fixed configuration created${NC}"
echo ""

# Step 7: Start with fixed configuration
echo -e "${YELLOW}Step 7: Starting system with fixed configuration...${NC}"
docker compose -f docker-compose-transparent-fixed.yml up -d
echo ""

# Step 8: Wait and verify
echo -e "${YELLOW}Step 8: Waiting for certificate generation...${NC}"
sleep 5

# Check certificate from host
if [ -f "./temp-certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificate exists on host${NC}"
    
    # Verify it's valid
    if openssl x509 -in ./temp-certs/mitmproxy-ca-cert.pem -noout -subject 2>/dev/null; then
        echo -e "${GREEN}✅ Certificate is valid${NC}"
        openssl x509 -in ./temp-certs/mitmproxy-ca-cert.pem -noout -subject -dates
    else
        echo -e "${RED}❌ Certificate is invalid${NC}"
    fi
else
    echo -e "${RED}❌ Certificate not found on host${NC}"
fi
echo ""

# Check certificate in container
echo -e "${YELLOW}Checking certificate in container...${NC}"
docker exec app sh -c "
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    echo '✅ Certificate found in container'
    if openssl x509 -in /certs/mitmproxy-ca-cert.pem -noout -subject 2>/dev/null; then
        echo '✅ Certificate is valid in container'
    else
        echo '❌ Certificate is invalid in container'
        echo 'File details:'
        ls -la /certs/mitmproxy-ca-cert.pem
        echo 'First few bytes:'
        head -c 100 /certs/mitmproxy-ca-cert.pem
    fi
else
    echo '❌ Certificate not found in container'
    echo 'Contents of /certs:'
    ls -la /certs/
fi
"
echo ""

# Step 9: Test HTTPS
echo -e "${YELLOW}Step 9: Testing HTTPS capture...${NC}"
docker exec -u appuser app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    cd /proxy
    if [ -f test-https-debug.go ]; then
        go run test-https-debug.go 2>&1 | grep -E '✅|❌|SUMMARY' | head -10
    else
        echo 'Creating simple test...'
        cat > /tmp/test.go << 'EOTEST'
package main
import (
    \"fmt\"
    \"net/http\"
    \"os\"
)
func main() {
    fmt.Println(\"Certificate:\", os.Getenv(\"SSL_CERT_FILE\"))
    resp, err := http.Get(\"https://httpbin.org/get\")
    if err != nil {
        fmt.Printf(\"❌ Error: %v\\n\", err)
    } else {
        fmt.Printf(\"✅ Success: %s\\n\", resp.Status)
        resp.Body.Close()
    }
}
EOTEST
        go run /tmp/test.go
    fi
"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  📋 Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Certificate location: ./temp-certs/mitmproxy-ca-cert.pem"
echo ""
echo "To use the fixed system:"
echo -e "  ${YELLOW}docker compose -f docker-compose-transparent-fixed.yml up -d${NC}"
echo ""
echo "To test:"
echo -e "  ${YELLOW}./run-app.sh 'go run /proxy/test-dns-fixed.go'${NC}"
echo ""
echo "If still having issues:"
echo "  1. Check Docker permissions: ls -la /var/run/docker.sock"
echo "  2. Restart Docker: sudo systemctl restart docker"
echo "  3. Try running as root: sudo ./fix-certificate.sh"
echo ""