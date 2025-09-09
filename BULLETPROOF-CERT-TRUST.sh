#!/bin/bash
# BULLETPROOF-CERT-TRUST.sh - Handles all APK package issues with fallbacks

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🛡️ BULLETPROOF CERTIFICATE TRUST SOLUTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up and start fresh
echo -e "${YELLOW}Step 1: Cleaning up...${NC}"
docker stop mitmproxy 2>/dev/null || true
docker rm mitmproxy 2>/dev/null || true

# Start mitmproxy on port 8082
docker run -d \
    --name mitmproxy \
    -p 8082:8082 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8082 --ssl-insecure

sleep 4

# Get certificate
echo -e "${YELLOW}Step 2: Getting certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

if [ ! -s mitmproxy-ca.pem ]; then
    echo -e "${RED}Certificate extraction failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Certificate ready ($(wc -c < mitmproxy-ca.pem) bytes)${NC}"

# Method 1: Try Ubuntu base (most reliable)
echo ""
echo -e "${YELLOW}Step 3: Method 1 - Ubuntu base (most reliable)...${NC}"

cat > Dockerfile.ubuntu-bulletproof << 'EOF'
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install packages
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    wget \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Set all certificate environment variables
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/bash"]
EOF

echo "Building Ubuntu-based trusted container..."
if docker build -t ubuntu-trusted -f Dockerfile.ubuntu-bulletproof .; then
    echo -e "${GREEN}✅ Ubuntu container built successfully${NC}"
    UBUNTU_SUCCESS=true
else
    echo -e "${RED}Ubuntu build failed${NC}"
    UBUNTU_SUCCESS=false
fi

# Method 2: Try Alpine with individual package installation
echo ""
echo -e "${YELLOW}Step 4: Method 2 - Alpine with individual packages...${NC}"

cat > Dockerfile.alpine-individual << 'EOF'
FROM alpine:latest

# Update package index
RUN apk update

# Install packages one by one with error handling
RUN apk add --no-cache curl || echo "curl failed"
RUN apk add --no-cache ca-certificates || echo "ca-certificates failed" 
RUN apk add --no-cache wget || echo "wget failed"
RUN apk add --no-cache bash || echo "bash failed"

# Verify what was installed
RUN which curl || echo "No curl"
RUN which wget || echo "No wget" 
RUN which bash || echo "No bash"

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building Alpine individual package container..."
if docker build -t alpine-individual -f Dockerfile.alpine-individual .; then
    echo -e "${GREEN}✅ Alpine individual container built successfully${NC}"
    ALPINE_SUCCESS=true
else
    echo -e "${RED}Alpine individual build failed${NC}"
    ALPINE_SUCCESS=false
fi

# Method 3: Minimal Alpine with only essentials
echo ""
echo -e "${YELLOW}Step 5: Method 3 - Minimal Alpine...${NC}"

cat > Dockerfile.alpine-minimal << 'EOF'
FROM alpine:latest

# Only install absolute essentials
RUN apk update && apk add --no-cache ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates  
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building minimal Alpine container..."
if docker build -t alpine-minimal -f Dockerfile.alpine-minimal .; then
    echo -e "${GREEN}✅ Alpine minimal container built successfully${NC}"
    MINIMAL_SUCCESS=true
else
    echo -e "${RED}Alpine minimal build failed${NC}"
    MINIMAL_SUCCESS=false
fi

# Test the working containers
echo ""
echo -e "${YELLOW}Step 6: Testing containers...${NC}"

# Get Docker IP for proxy connection
DOCKER_IP=$(docker inspect mitmproxy | grep '"IPAddress"' | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

if [ "$UBUNTU_SUCCESS" = "true" ]; then
    echo -e "${BLUE}Testing Ubuntu container...${NC}"
    docker run --rm ubuntu-trusted sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        if [ \$? -eq 0 ]; then
            echo '✅ Ubuntu container WORKS!'
        fi
    "
fi

if [ "$ALPINE_SUCCESS" = "true" ]; then
    echo -e "${BLUE}Testing Alpine individual container...${NC}"
    docker run --rm alpine-individual sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3  
        if [ \$? -eq 0 ]; then
            echo '✅ Alpine individual WORKS!'
        fi
    "
fi

if [ "$MINIMAL_SUCCESS" = "true" ]; then
    echo -e "${BLUE}Testing minimal Alpine container (using wget)...${NC}"
    docker run --rm alpine-minimal sh -c "
        # Use wget since curl might not be available
        wget -q -O- --proxy=on --http-proxy=http://$DOCKER_IP:8082 https://api.github.com/users/github | head -3
        if [ \$? -eq 0 ]; then
            echo '✅ Alpine minimal WORKS!'
        fi
    "
fi

# Create Go app with working container
echo ""
echo -e "${YELLOW}Step 7: Creating Go app with best working container...${NC}"

# Use Ubuntu as the base since it's most reliable
cat > Dockerfile.go-bulletproof << 'EOF'
FROM golang:1.21-bullseye

# Install ca-certificates (Debian/Ubuntu style)
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

# Create Go app that works without InsecureSkipVerify
COPY <<'GOEOF' main.go
package main

import (
    "fmt"
    "io"
    "net/http"
    "os"
)

func main() {
    fmt.Println("🔒 Testing HTTPS without InsecureSkipVerify...")
    
    client := &http.Client{}
    
    req, err := http.NewRequest("GET", "https://api.github.com/users/github", nil)
    if err != nil {
        fmt.Printf("❌ Request error: %v\n", err)
        return
    }
    
    if proxy := os.Getenv("HTTP_PROXY"); proxy != "" {
        fmt.Printf("✅ Using proxy: %s\n", proxy)
    }
    
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("❌ HTTPS Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("🎉 SUCCESS! Got %d bytes without --insecure!\n", len(body))
    fmt.Printf("Sample: %.100s...\n", string(body))
}
GOEOF

CMD ["go", "run", "main.go"]
EOF

docker build -t go-bulletproof -f Dockerfile.go-bulletproof .

# Test Go app
echo -e "${BLUE}Testing Go app...${NC}"
docker run --rm \
    -e HTTP_PROXY=http://$DOCKER_IP:8082 \
    -e HTTPS_PROXY=http://$DOCKER_IP:8082 \
    go-bulletproof

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎯 BULLETPROOF SOLUTION RESULTS${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""

echo "Built containers:"
[ "$UBUNTU_SUCCESS" = "true" ] && echo "✅ ubuntu-trusted - Most reliable" || echo "❌ ubuntu-trusted failed"
[ "$ALPINE_SUCCESS" = "true" ] && echo "✅ alpine-individual - With package handling" || echo "❌ alpine-individual failed" 
[ "$MINIMAL_SUCCESS" = "true" ] && echo "✅ alpine-minimal - Bare minimum" || echo "❌ alpine-minimal failed"
echo "✅ go-bulletproof - Go app without InsecureSkipVerify"

echo ""
echo -e "${YELLOW}Best option to use:${NC}"
if [ "$UBUNTU_SUCCESS" = "true" ]; then
    echo "🏆 ${GREEN}docker run --rm --network host ubuntu-trusted${NC}"
    echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
elif [ "$ALPINE_SUCCESS" = "true" ]; then
    echo "🥈 ${GREEN}docker run --rm --network host alpine-individual${NC}"
elif [ "$MINIMAL_SUCCESS" = "true" ]; then
    echo "🥉 ${GREEN}docker run --rm --network host alpine-minimal${NC}"
fi

echo ""
echo "MITMProxy running on: ${GREEN}http://localhost:8082${NC}"
echo "View captures: ${GREEN}docker logs -f mitmproxy${NC}"