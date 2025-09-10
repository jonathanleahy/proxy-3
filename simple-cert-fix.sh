#!/bin/bash
# simple-cert-fix.sh - Simple and reliable certificate fix

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 Simple Certificate Fix${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Clean everything
echo -e "${YELLOW}Step 1: Cleaning up old system...${NC}"
docker compose -f docker-compose-transparent.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-fixed.yml down -v 2>/dev/null || true
docker stop app transparent-proxy mock-viewer 2>/dev/null || true
docker rm app transparent-proxy mock-viewer 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
rm -rf ./temp-certs 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 2: Create local certificate directory
echo -e "${YELLOW}Step 2: Creating local certificate directory...${NC}"
mkdir -p ./certs
chmod 755 ./certs
echo -e "${GREEN}✅ Directory created: ./certs${NC}"
echo ""

# Step 3: Generate certificate using mitmproxy container
echo -e "${YELLOW}Step 3: Generating certificate with mitmproxy...${NC}"
docker run --rm \
    -v "$(pwd)/certs:/home/mitmproxy/.mitmproxy" \
    --user $(id -u):$(id -g) \
    mitmproxy/mitmproxy \
    sh -c "mitmdump --version && sleep 2"

# Check if certificate was generated
if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificate generated successfully!${NC}"
    ls -la ./certs/mitmproxy-ca-cert.pem
else
    echo -e "${YELLOW}Trying alternative generation method...${NC}"
    
    # Alternative: Run container briefly to generate certs
    docker run -d --name temp-mitm \
        -v "$(pwd)/certs:/certs" \
        mitmproxy/mitmproxy \
        sh -c "
            mitmdump --version
            cp /home/mitmproxy/.mitmproxy/*.pem /certs/ 2>/dev/null
            chmod 644 /certs/*.pem 2>/dev/null
            sleep 5
        "
    
    sleep 6
    docker stop temp-mitm 2>/dev/null
    docker rm temp-mitm 2>/dev/null
    
    if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
        echo -e "${GREEN}✅ Certificate generated with alternative method${NC}"
    else
        echo -e "${RED}❌ Certificate generation failed${NC}"
        echo "Trying one more method..."
        
        # Last resort: Create temporary container and copy
        docker run -d --name cert-gen mitmproxy/mitmproxy mitmdump
        sleep 3
        docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ./certs/ 2>/dev/null || true
        docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.cer ./certs/ 2>/dev/null || true
        docker cp cert-gen:/home/mitmproxy/.mitmproxy/mitmproxy-ca.pem ./certs/ 2>/dev/null || true
        docker stop cert-gen 2>/dev/null
        docker rm cert-gen 2>/dev/null
        
        if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
            echo -e "${GREEN}✅ Certificate extracted from container${NC}"
        fi
    fi
fi

# Verify certificate exists
if [ ! -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${RED}❌ Failed to generate certificate${NC}"
    echo ""
    echo "Manual steps to try:"
    echo "1. Run: docker run -it --rm -v \$(pwd)/certs:/certs mitmproxy/mitmproxy bash"
    echo "2. Inside container: mitmdump --version"
    echo "3. Inside container: cp /home/mitmproxy/.mitmproxy/*.pem /certs/"
    echo "4. Exit container and check ./certs/"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Certificate exists at: ./certs/mitmproxy-ca-cert.pem${NC}"
echo ""

# Step 4: Set permissions
echo -e "${YELLOW}Step 4: Setting certificate permissions...${NC}"
chmod 644 ./certs/*.pem 2>/dev/null || true
chmod 755 ./certs
echo -e "${GREEN}✅ Permissions set${NC}"
echo ""

# Step 5: Create simple docker-compose that uses local certs
echo -e "${YELLOW}Step 5: Creating docker-compose with local certificates...${NC}"
cat > docker-compose-simple.yml << 'EOF'
services:
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
      - ./certs:/certs:rw
    networks:
      capture-net:
        ipv4_address: 10.5.0.2
    ports:
      - "8080:8080"
      - "8084:8084"
    command: |
      sh -c "
      echo 'Using certificates from /certs'
      ls -la /certs/
      if [ -f /certs/mitmproxy-ca-cert.pem ]; then
          echo '✅ Certificate found'
      else
          echo '❌ Certificate not found, generating...'
          mitmdump --version
          cp /home/mitmproxy/.mitmproxy/*.pem /certs/ 2>/dev/null || true
      fi
      /scripts/transparent-entrypoint.sh
      "

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
      - ./certs:/certs:ro
    working_dir: /proxy
    environment:
      TARGET_API: "https://api.github.com"
      SSL_CERT_FILE: /certs/mitmproxy-ca-cert.pem
      REQUESTS_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
      NODE_EXTRA_CA_CERTS: /certs/mitmproxy-ca-cert.pem
    command: tail -f /dev/null

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
EOF
echo -e "${GREEN}✅ Docker-compose created${NC}"
echo ""

# Step 6: Start the system
echo -e "${YELLOW}Step 6: Starting system with local certificates...${NC}"
docker compose -f docker-compose-simple.yml up -d
echo ""

# Step 7: Wait and verify
echo -e "${YELLOW}Step 7: Verifying setup...${NC}"
sleep 5

# Check certificate in container
echo "Checking certificate in container..."
docker exec app sh -c "
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    echo '✅ Certificate found in container at /certs/mitmproxy-ca-cert.pem'
    head -2 /certs/mitmproxy-ca-cert.pem
else
    echo '❌ Certificate not found in container'
    ls -la /certs/
fi
"
echo ""

# Step 8: Quick test
echo -e "${YELLOW}Step 8: Testing HTTPS...${NC}"
docker exec -u appuser app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    cd /proxy
    cat > /tmp/quick-test.go << 'EOTEST'
package main
import (
    \"log\"
    \"net/http\"
    \"os\"
)
func main() {
    log.Println(\"SSL_CERT_FILE:\", os.Getenv(\"SSL_CERT_FILE\"))
    resp, err := http.Get(\"https://httpbin.org/get\")
    if err != nil {
        log.Printf(\"❌ Failed: %v\", err)
    } else {
        log.Printf(\"✅ Success: %s\", resp.Status)
        resp.Body.Close()
    }
}
EOTEST
    go run /tmp/quick-test.go
"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Certificate location: ./certs/mitmproxy-ca-cert.pem"
echo ""
echo "To use this setup:"
echo "1. System is running with: docker-compose-simple.yml"
echo "2. Test with: ./run-app.sh 'go run /proxy/test-dns-fixed.go'"
echo "3. Stop with: docker compose -f docker-compose-simple.yml down"
echo ""
echo "The certificate is now in ./certs/ directory and mounted to containers."
echo ""