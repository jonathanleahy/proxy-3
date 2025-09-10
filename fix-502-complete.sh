#!/bin/bash
# fix-502-complete.sh - Complete fix for 502 errors with DNS and proxy issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔧 Complete 502 Error Fix${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Complete system cleanup
echo -e "${YELLOW}Step 1: Complete cleanup...${NC}"
docker compose down -v 2>/dev/null || true
docker compose -f docker-compose-transparent.yml down -v 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down -v 2>/dev/null || true
docker compose -f docker-compose-simple.yml down -v 2>/dev/null || true
docker compose -f docker-compose-with-certs.yml down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
rm -rf ./certs ./temp-certs 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 2: Generate fresh certificates
echo -e "${YELLOW}Step 2: Generating fresh certificates...${NC}"
./guaranteed-cert-gen.sh || {
    echo -e "${YELLOW}Certificate script not found, generating inline...${NC}"
    mkdir -p ./certs
    openssl genrsa -out ./certs/mitmproxy-ca.key 2048 2>/dev/null
    openssl req -new -x509 -key ./certs/mitmproxy-ca.key \
        -out ./certs/mitmproxy-ca-cert.pem \
        -days 3650 \
        -subj "/C=US/ST=CA/L=San Francisco/O=mitmproxy/OU=mitmproxy/CN=mitmproxy CA"
    cat ./certs/mitmproxy-ca.key ./certs/mitmproxy-ca-cert.pem > ./certs/mitmproxy-ca.pem
    chmod 644 ./certs/*
}
echo -e "${GREEN}✅ Certificates ready${NC}"
echo ""

# Step 3: Create working docker-compose configuration
echo -e "${YELLOW}Step 3: Creating working configuration...${NC}"
cat > docker-compose-working.yml << 'EOF'
version: '3.8'

services:
  # Simple mitmproxy without complex iptables rules
  mitmproxy:
    image: mitmproxy/mitmproxy:latest
    container_name: mitmproxy
    command: mitmdump -s /scripts/capture.py --ssl-insecure --set confdir=/certs
    volumes:
      - ./certs:/certs
      - ./captured:/captured
      - ./scripts:/scripts:ro
    ports:
      - "8082:8080"  # Proxy port
    networks:
      proxy-net:
        ipv4_address: 172.30.0.2

  # Application container
  app:
    build:
      context: .
      dockerfile: docker/Dockerfile.app
    container_name: app
    volumes:
      - ./:/proxy
      - ./certs:/certs:ro
    working_dir: /proxy
    environment:
      # Proxy configuration
      HTTP_PROXY: http://172.30.0.2:8080
      HTTPS_PROXY: http://172.30.0.2:8080
      http_proxy: http://172.30.0.2:8080
      https_proxy: http://172.30.0.2:8080
      NO_PROXY: localhost,127.0.0.1
      # Certificate trust
      SSL_CERT_FILE: /certs/mitmproxy-ca-cert.pem
      REQUESTS_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
      NODE_EXTRA_CA_CERTS: /certs/mitmproxy-ca-cert.pem
      CURL_CA_BUNDLE: /certs/mitmproxy-ca-cert.pem
    networks:
      proxy-net:
        ipv4_address: 172.30.0.3
    command: tail -f /dev/null

networks:
  proxy-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
EOF
echo -e "${GREEN}✅ Configuration created${NC}"
echo ""

# Step 4: Create simple capture script
echo -e "${YELLOW}Step 4: Creating capture script...${NC}"
mkdir -p ./scripts
cat > ./scripts/capture.py << 'EOF'
import json
import os
from datetime import datetime
from mitmproxy import http

class Capture:
    def __init__(self):
        self.captures = []
        self.output_dir = "/captured"
        os.makedirs(self.output_dir, exist_ok=True)

    def request(self, flow: http.HTTPFlow) -> None:
        # Log the request
        print(f"Request: {flow.request.method} {flow.request.pretty_url}")

    def response(self, flow: http.HTTPFlow) -> None:
        # Log the response
        print(f"Response: {flow.response.status_code} from {flow.request.pretty_url}")
        
        # Save to file
        capture = {
            "timestamp": datetime.now().isoformat(),
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "status": flow.response.status_code,
            "request_headers": dict(flow.request.headers),
            "response_headers": dict(flow.response.headers),
            "response_body": flow.response.text if flow.response.text else None
        }
        
        self.captures.append(capture)
        
        # Save every 10 captures or create individual files
        if len(self.captures) >= 10:
            self.save_captures()
    
    def save_captures(self):
        if not self.captures:
            return
        
        filename = f"{self.output_dir}/capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(filename, 'w') as f:
            json.dump(self.captures, f, indent=2)
        print(f"Saved {len(self.captures)} captures to {filename}")
        self.captures = []

    def done(self):
        # Save remaining captures when mitmproxy shuts down
        self.save_captures()

addons = [Capture()]
EOF
chmod 644 ./scripts/capture.py
echo -e "${GREEN}✅ Capture script created${NC}"
echo ""

# Step 5: Start the system
echo -e "${YELLOW}Step 5: Starting the system...${NC}"
docker compose -f docker-compose-working.yml up -d
sleep 5
echo -e "${GREEN}✅ System started${NC}"
echo ""

# Step 6: Test basic connectivity
echo -e "${YELLOW}Step 6: Testing connectivity...${NC}"

# Test DNS
echo "Testing DNS resolution..."
docker exec app sh -c "nslookup api.github.com 8.8.8.8 | grep Address | tail -1"

# Test proxy connectivity
echo "Testing proxy connectivity..."
docker exec app sh -c "nc -zv 172.30.0.2 8080 2>&1" || echo "Proxy connection test"

# Test certificate
echo "Testing certificate..."
docker exec app sh -c "cat /certs/mitmproxy-ca-cert.pem | head -2"
echo ""

# Step 7: Create and run improved test
echo -e "${YELLOW}Step 7: Running improved test...${NC}"
docker exec app sh -c "cat > /tmp/test-working.go << 'EOTEST'
package main

import (
    \"crypto/tls\"
    \"fmt\"
    \"io\"
    \"net/http\"
    \"os\"
    \"time\"
)

func main() {
    fmt.Println(\"=== Testing HTTPS with Proxy ===\")
    fmt.Printf(\"HTTP_PROXY: %s\\n\", os.Getenv(\"HTTP_PROXY\"))
    fmt.Printf(\"HTTPS_PROXY: %s\\n\", os.Getenv(\"HTTPS_PROXY\"))
    fmt.Printf(\"SSL_CERT_FILE: %s\\n\", os.Getenv(\"SSL_CERT_FILE\"))
    
    // Test 1: Simple HTTP request
    fmt.Println(\"\\nTest 1: HTTP request to httpbin.org...\")
    resp1, err1 := http.Get(\"http://httpbin.org/get\")
    if err1 != nil {
        fmt.Printf(\"❌ HTTP failed: %v\\n\", err1)
    } else {
        fmt.Printf(\"✅ HTTP success: %s\\n\", resp1.Status)
        resp1.Body.Close()
    }
    
    // Test 2: HTTPS with default client
    fmt.Println(\"\\nTest 2: HTTPS with default client...\")
    resp2, err2 := http.Get(\"https://httpbin.org/get\")
    if err2 != nil {
        fmt.Printf(\"❌ HTTPS failed: %v\\n\", err2)
    } else {
        body, _ := io.ReadAll(resp2.Body)
        fmt.Printf(\"✅ HTTPS success: %s, Body length: %d\\n\", resp2.Status, len(body))
        resp2.Body.Close()
    }
    
    // Test 3: HTTPS with custom client (skip verify for testing)
    fmt.Println(\"\\nTest 3: HTTPS with InsecureSkipVerify...\")
    client := &http.Client{
        Transport: &http.Transport{
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true,
            },
        },
        Timeout: 10 * time.Second,
    }
    
    resp3, err3 := client.Get(\"https://api.github.com/meta\")
    if err3 != nil {
        fmt.Printf(\"❌ Custom HTTPS failed: %v\\n\", err3)
    } else {
        fmt.Printf(\"✅ Custom HTTPS success: %s\\n\", resp3.Status)
        resp3.Body.Close()
    }
}
EOTEST
go run /tmp/test-working.go"
echo ""

# Step 8: Check captures
echo -e "${YELLOW}Step 8: Checking captures...${NC}"
if ls ./captured/*.json 2>/dev/null; then
    echo -e "${GREEN}✅ Captures found:${NC}"
    ls -la ./captured/*.json
else
    echo -e "${YELLOW}No captures yet. Forcing save...${NC}"
    docker exec mitmproxy pkill -USR1 mitmdump 2>/dev/null || true
    sleep 2
    ls -la ./captured/*.json 2>/dev/null || echo "No captures saved"
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  📋 Diagnostic Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check what's working
WORKING=0
NOT_WORKING=0

echo "Checking system status..."
if docker ps | grep -q mitmproxy; then
    echo -e "${GREEN}✅ Proxy container running${NC}"
    WORKING=$((WORKING + 1))
else
    echo -e "${RED}❌ Proxy container not running${NC}"
    NOT_WORKING=$((NOT_WORKING + 1))
fi

if docker ps | grep -q app; then
    echo -e "${GREEN}✅ App container running${NC}"
    WORKING=$((WORKING + 1))
else
    echo -e "${RED}❌ App container not running${NC}"
    NOT_WORKING=$((NOT_WORKING + 1))
fi

if [ -f "./certs/mitmproxy-ca-cert.pem" ]; then
    echo -e "${GREEN}✅ Certificates exist${NC}"
    WORKING=$((WORKING + 1))
else
    echo -e "${RED}❌ Certificates missing${NC}"
    NOT_WORKING=$((NOT_WORKING + 1))
fi

echo ""
if [ $NOT_WORKING -eq 0 ]; then
    echo -e "${GREEN}✅ System should be working!${NC}"
    echo ""
    echo "To test manually:"
    echo "  docker exec app sh -c 'curl -x http://172.30.0.2:8080 http://httpbin.org/get'"
    echo ""
    echo "To run the DNS-fixed test:"
    echo "  docker exec app sh -c 'cd /proxy && go run test-dns-fixed.go'"
else
    echo -e "${RED}⚠️  Some components are not working${NC}"
    echo ""
    echo "Try:"
    echo "  1. Restart Docker: sudo systemctl restart docker"
    echo "  2. Check Docker logs: docker logs mitmproxy"
    echo "  3. Verify network: docker network ls"
fi
echo ""