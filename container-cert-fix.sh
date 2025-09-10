#!/bin/bash
# container-cert-fix.sh - Generate certificates properly inside containers

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 Container-Based Certificate Fix${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Clean up
echo -e "${YELLOW}Step 1: Cleaning up old system...${NC}"
docker compose -f docker-compose-transparent.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down -v 2>/dev/null || true
docker compose -f docker-compose-simple.yml down -v 2>/dev/null || true
docker stop app transparent-proxy mock-viewer 2>/dev/null || true
docker rm app transparent-proxy mock-viewer 2>/dev/null || true
rm -rf ./certs 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 2: Create local certificate directory with proper permissions
echo -e "${YELLOW}Step 2: Creating certificate directory...${NC}"
mkdir -p ./certs
# Make it world-writable temporarily so container can write to it
chmod 777 ./certs
echo -e "${GREEN}✅ Directory created: ./certs (with write permissions)${NC}"
echo ""

# Step 3: Create a minimal docker-compose just for certificate generation
echo -e "${YELLOW}Step 3: Creating certificate generation setup...${NC}"
cat > docker-compose-cert-gen.yml << 'EOF'
services:
  cert-generator:
    image: mitmproxy/mitmproxy:latest
    container_name: cert-generator
    volumes:
      - ./certs:/output
    user: root
    command: |
      sh -c "
      echo 'Generating mitmproxy certificates...'
      
      # Run mitmproxy to generate certificates in its home directory
      mitmdump --version > /dev/null 2>&1
      sleep 1
      
      # Check if certificates were generated
      if [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
          echo '✅ Certificates generated'
          
          # Copy all certificate files to output
          cp /home/mitmproxy/.mitmproxy/*.pem /output/ 2>/dev/null || true
          cp /home/mitmproxy/.mitmproxy/*.p12 /output/ 2>/dev/null || true
          cp /home/mitmproxy/.mitmproxy/*.cer /output/ 2>/dev/null || true
          
          # Set proper permissions
          chmod 644 /output/*.pem 2>/dev/null || true
          chmod 644 /output/*.p12 2>/dev/null || true
          chmod 644 /output/*.cer 2>/dev/null || true
          
          echo 'Certificate files copied to /output'
          ls -la /output/
      else
          echo '❌ Certificate generation failed'
          echo 'Contents of mitmproxy directory:'
          ls -la /home/mitmproxy/.mitmproxy/ || echo 'Directory not found'
      fi
      "
EOF
echo -e "${GREEN}✅ Certificate generator configured${NC}"
echo ""

# Step 4: Run certificate generation
echo -e "${YELLOW}Step 4: Generating certificates inside container...${NC}"
docker compose -f docker-compose-cert-gen.yml run --rm cert-generator
echo ""

# Step 5: Verify certificates were created
echo -e "${YELLOW}Step 5: Verifying certificates...${NC}"
if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificate generated successfully!${NC}"
    
    # Fix permissions back to normal
    chmod 755 ./certs
    chmod 644 ./certs/*.pem 2>/dev/null || true
    
    echo "Certificate files:"
    ls -la ./certs/
    echo ""
    
    # Show certificate info
    echo "Certificate details:"
    openssl x509 -in ./certs/mitmproxy-ca-cert.pem -noout -subject -dates 2>/dev/null || echo "OpenSSL not available for verification"
else
    echo -e "${RED}❌ Certificate generation failed${NC}"
    echo "Contents of certs directory:"
    ls -la ./certs/
    exit 1
fi
echo ""

# Step 6: Create the main docker-compose with certificates
echo -e "${YELLOW}Step 6: Creating main docker-compose configuration...${NC}"
cat > docker-compose-with-certs.yml << 'EOF'
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
      - ./certs:/certs:ro
    networks:
      capture-net:
        ipv4_address: 10.5.0.2
    ports:
      - "8080:8080"
      - "8084:8084"
    environment:
      # Tell mitmproxy to use our certificates
      MITMPROXY_OPTIONS: "--certs /certs/mitmproxy-ca.pem"

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
      CURL_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
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
echo -e "${GREEN}✅ Main configuration created${NC}"
echo ""

# Step 7: Start the main system
echo -e "${YELLOW}Step 7: Starting the proxy system...${NC}"
docker compose -f docker-compose-with-certs.yml up -d
echo ""

# Step 8: Wait and verify
echo -e "${YELLOW}Step 8: Verifying system...${NC}"
sleep 5

# Check certificate in app container
echo "Checking certificate access in app container..."
docker exec app sh -c "
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    echo '✅ Certificate accessible in app container'
    echo 'Certificate first line:'
    head -1 /certs/mitmproxy-ca-cert.pem
else
    echo '❌ Certificate not accessible in app container'
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
    cat > /tmp/test.go << 'EOTEST'
package main
import (
    \"fmt\"
    \"net/http\"
    \"os\"
)
func main() {
    fmt.Println(\"Testing with certificate:\", os.Getenv(\"SSL_CERT_FILE\"))
    
    client := &http.Client{}
    resp, err := client.Get(\"https://httpbin.org/get\")
    if err != nil {
        fmt.Printf(\"❌ Error: %v\\n\", err)
        fmt.Println(\"This likely means the certificate isn't trusted\")
    } else {
        fmt.Printf(\"✅ Success: Status %s\\n\", resp.Status)
        resp.Body.Close()
    }
}
EOTEST
    go run /tmp/test.go
"
echo ""

# Step 10: Clean up temp files
echo -e "${YELLOW}Step 10: Cleaning up temporary files...${NC}"
rm -f docker-compose-cert-gen.yml
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Certificate Fix Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Certificates location: ./certs/"
echo "Main certificate: ./certs/mitmproxy-ca-cert.pem"
echo ""
echo "System is running with: docker-compose-with-certs.yml"
echo ""
echo "To test the system:"
echo "  ./run-app.sh 'go run /proxy/test-dns-fixed.go'"
echo ""
echo "To stop:"
echo "  docker compose -f docker-compose-with-certs.yml down"
echo ""
echo "If you still have issues, check:"
echo "  1. Docker permissions: groups | grep docker"
echo "  2. SELinux/AppArmor: Add :Z to volume mounts (./certs:/certs:ro,Z)"
echo ""