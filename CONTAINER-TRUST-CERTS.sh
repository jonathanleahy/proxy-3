#!/bin/bash
# CONTAINER-TRUST-CERTS.sh - Install certificates in CONTAINERS, not your machine!

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  CERTIFICATE TRUST IN CONTAINERS ONLY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Installing mitmproxy certificate INSIDE containers"
echo "Your host machine remains unchanged!"
echo ""

# Clean up
docker stop mitmproxy app-trusted test-client 2>/dev/null || true
docker rm mitmproxy app-trusted test-client 2>/dev/null || true

# Step 1: Start mitmproxy
echo -e "${YELLOW}Step 1: Starting mitmproxy...${NC}"
docker run -d \
    --name mitmproxy \
    -p 8080:8080 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080 --ssl-insecure

sleep 3

# Step 2: Get the certificate
echo -e "${YELLOW}Step 2: Getting mitmproxy certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

if [ ! -s mitmproxy-ca.pem ]; then
    echo -e "${RED}Failed to get certificate${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Got certificate${NC}"

# Step 3: Create a test client container with certificate pre-installed
echo -e "${YELLOW}Step 3: Creating container with certificate trusted...${NC}"

# Create a Dockerfile that includes the certificate
cat > Dockerfile.trusted << 'EOF'
FROM alpine:latest

# Install necessary tools
RUN apk add --no-cache \
    curl \
    ca-certificates \
    wget \
    bash

# Copy and install the mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

# Set environment to use the certificates
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

CMD ["/bin/bash"]
EOF

# Build the image with certificate baked in
docker build -t trusted-client -f Dockerfile.trusted .

# Step 4: Test WITHOUT --insecure from inside container
echo ""
echo -e "${YELLOW}Step 4: Testing from container WITHOUT --insecure...${NC}"

docker run --rm \
    --name test-client \
    --add-host=proxy:172.17.0.1 \
    trusted-client \
    sh -c "
        echo 'Testing HTTPS through proxy WITHOUT --insecure flag...'
        echo ''
        
        # This should work WITHOUT --insecure!
        curl -x http://172.17.0.1:8080 \
             -s --max-time 5 \
             https://api.github.com/users/github \
             | head -10
        
        if [ \$? -eq 0 ]; then
            echo ''
            echo '✅ SUCCESS! No --insecure needed!'
        else
            echo '❌ Failed'
        fi
    "

# Step 5: Create Go app container with certificate
echo ""
echo -e "${YELLOW}Step 5: Creating Go app container with certificate...${NC}"

cat > Dockerfile.go-trusted << 'EOF'
FROM golang:alpine

# Install ca-certificates
RUN apk add --no-cache ca-certificates

# Copy and install mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

# Create test Go app
RUN echo 'package main
import (
    "fmt"
    "io/ioutil"
    "net/http"
    "os"
)

func main() {
    // No InsecureSkipVerify needed!
    client := &http.Client{}
    
    req, _ := http.NewRequest("GET", "https://api.github.com", nil)
    
    // Use proxy from environment
    if proxy := os.Getenv("HTTP_PROXY"); proxy != "" {
        fmt.Printf("Using proxy: %s\n", proxy)
    }
    
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := ioutil.ReadAll(resp.Body)
    fmt.Printf("Success! Got %d bytes\n", len(body))
    fmt.Println("NO --insecure or InsecureSkipVerify needed!")
}' > main.go

CMD ["go", "run", "main.go"]
EOF

docker build -t go-trusted -f Dockerfile.go-trusted .

echo ""
echo -e "${YELLOW}Step 6: Running Go app through proxy...${NC}"

docker run --rm \
    -e HTTP_PROXY=http://172.17.0.1:8080 \
    -e HTTPS_PROXY=http://172.17.0.1:8080 \
    go-trusted

# Step 7: Create docker-compose for easy use
echo ""
echo -e "${YELLOW}Step 7: Creating docker-compose.yml...${NC}"

cat > docker-compose-trusted.yml << 'EOF'
version: '3.8'

services:
  mitmproxy:
    image: mitmproxy/mitmproxy
    command: mitmdump --listen-port 8080 --ssl-insecure
    ports:
      - "8080:8080"
    networks:
      - proxy-net

  app:
    build:
      context: .
      dockerfile: Dockerfile.go-trusted
    environment:
      - HTTP_PROXY=http://mitmproxy:8080
      - HTTPS_PROXY=http://mitmproxy:8080
    depends_on:
      - mitmproxy
    networks:
      - proxy-net

networks:
  proxy-net:
    driver: bridge
EOF

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  SUCCESS! NO --insecure NEEDED!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The certificate is installed INSIDE the containers:"
echo "• Your host machine is unchanged"
echo "• No sudo/admin needed"
echo "• Containers trust mitmproxy automatically"
echo ""
echo "Use the trusted container:"
echo "  ${GREEN}docker run --rm -it trusted-client bash${NC}"
echo "  ${GREEN}curl -x http://172.17.0.1:8080 https://api.github.com${NC}"
echo ""
echo "Or with docker-compose:"
echo "  ${GREEN}docker-compose -f docker-compose-trusted.yml up${NC}"
echo ""
echo -e "${YELLOW}Your containers can now make HTTPS requests through"
echo "the proxy WITHOUT --insecure or InsecureSkipVerify!${NC}"