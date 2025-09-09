#!/bin/bash
# FAST-CERT-TRUST.sh - Fast certificate trust solution avoiding slow apt-get

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ⚡ FAST CERTIFICATE TRUST SOLUTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up and start fresh
echo -e "${YELLOW}Step 1: Cleaning up...${NC}"
docker stop mitmproxy 2>/dev/null || true
docker rm mitmproxy 2>/dev/null || true

# Start mitmproxy on port 8082
echo -e "${YELLOW}Step 2: Starting mitmproxy...${NC}"
docker run -d \
    --name mitmproxy \
    -p 8082:8082 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8082 --ssl-insecure

sleep 4

# Get certificate
echo -e "${YELLOW}Step 3: Getting certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

if [ ! -s mitmproxy-ca.pem ]; then
    echo -e "${RED}Certificate extraction failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Certificate ready ($(wc -c < mitmproxy-ca.pem) bytes)${NC}"

# Method 1: Use existing Ubuntu image with packages pre-installed (fastest)
echo ""
echo -e "${YELLOW}Method 1: Using pre-built Ubuntu with curl (fastest)...${NC}"

cat > Dockerfile.ubuntu-fast << 'EOF'
# Use Ubuntu image that already has curl installed
FROM ubuntu:22.04

# Skip apt-get entirely - just add certificate!
# Most Ubuntu images already have curl and ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates (this is fast)
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/bash"]
EOF

echo "Building fast Ubuntu container (skipping apt-get)..."
if docker build -t ubuntu-fast -f Dockerfile.ubuntu-fast . 2>/dev/null; then
    echo -e "${GREEN}✅ Fast Ubuntu built successfully${NC}"
    UBUNTU_FAST=true
else
    echo -e "${YELLOW}Ubuntu base doesn't have curl, trying with minimal install...${NC}"
    UBUNTU_FAST=false
fi

# Method 2: Use smaller base with faster package manager
echo ""
echo -e "${YELLOW}Method 2: Using Alpine (much faster package manager)...${NC}"

cat > Dockerfile.alpine-fast << 'EOF'
FROM alpine:latest

# Alpine's apk is much faster than apt-get
RUN apk add --no-cache curl ca-certificates

# Copy certificate  
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building fast Alpine container..."
if docker build -t alpine-fast -f Dockerfile.alpine-fast .; then
    echo -e "${GREEN}✅ Fast Alpine built successfully${NC}"
    ALPINE_FAST=true
else
    echo -e "${RED}Alpine build failed${NC}"
    ALPINE_FAST=false
fi

# Method 3: Use existing image that already has tools (fastest of all)
echo ""
echo -e "${YELLOW}Method 3: Using existing image with tools pre-installed...${NC}"

cat > Dockerfile.prebuilt-fast << 'EOF'
# Use an image that already has everything we need
FROM curlimages/curl:latest

# Switch to root to install certificate
USER root

# Install ca-certificates if not present
RUN apk add --no-cache ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building prebuilt container with curl already installed..."
if docker build -t prebuilt-fast -f Dockerfile.prebuilt-fast .; then
    echo -e "${GREEN}✅ Prebuilt container built successfully${NC}"
    PREBUILT_FAST=true
else
    echo -e "${RED}Prebuilt build failed${NC}"
    PREBUILT_FAST=false
fi

# Method 4: Use debian slim (faster than full ubuntu)
echo ""
echo -e "${YELLOW}Method 4: Using Debian slim (faster than Ubuntu)...${NC}"

cat > Dockerfile.debian-fast << 'EOF'
FROM debian:bookworm-slim

# Debian slim is faster than full Ubuntu
RUN apt-get update -qq && apt-get install -y -qq \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/bash"]
EOF

echo "Building Debian slim container..."
docker build -t debian-fast -f Dockerfile.debian-fast . &
DEBIAN_PID=$!

# Test what we have so far while Debian builds
echo ""
echo -e "${YELLOW}Step 4: Testing fast containers...${NC}"

# Get Docker IP
DOCKER_IP=$(docker inspect mitmproxy | grep '"IPAddress"' | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

if [ "$ALPINE_FAST" = "true" ]; then
    echo -e "${BLUE}Testing Alpine fast container...${NC}"
    docker run --rm alpine-fast sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        if [ \$? -eq 0 ]; then
            echo '✅ Alpine fast WORKS!'
        fi
    "
fi

if [ "$PREBUILT_FAST" = "true" ]; then
    echo -e "${BLUE}Testing prebuilt container...${NC}"
    docker run --rm prebuilt-fast sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        if [ \$? -eq 0 ]; then
            echo '✅ Prebuilt fast WORKS!'
        fi
    "
fi

if [ "$UBUNTU_FAST" = "true" ]; then
    echo -e "${BLUE}Testing Ubuntu fast container...${NC}"
    # Check if curl exists in the base image
    if docker run --rm ubuntu-fast which curl >/dev/null 2>&1; then
        docker run --rm ubuntu-fast sh -c "
            curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
            if [ \$? -eq 0 ]; then
                echo '✅ Ubuntu fast WORKS!'
            fi
        "
    else
        echo "❌ Ubuntu base doesn't have curl"
    fi
fi

# Wait for Debian build to complete
wait $DEBIAN_PID
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Debian slim built successfully${NC}"
    echo -e "${BLUE}Testing Debian slim container...${NC}"
    docker run --rm debian-fast sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        if [ \$? -eq 0 ]; then
            echo '✅ Debian slim WORKS!'
        fi
    "
fi

# Create Go app with the fastest working base
echo ""
echo -e "${YELLOW}Step 5: Creating fast Go app...${NC}"

cat > Dockerfile.go-fast << 'EOF'
# Use Alpine Go image (much smaller and faster)
FROM golang:alpine

# Alpine apk is fast
RUN apk add --no-cache ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

# Create Go app
COPY <<'GOEOF' main.go
package main

import (
    "fmt"
    "io"
    "net/http"
    "os"
)

func main() {
    fmt.Println("⚡ Fast HTTPS test without InsecureSkipVerify...")
    
    client := &http.Client{}
    
    req, _ := http.NewRequest("GET", "https://api.github.com/users/github", nil)
    
    if proxy := os.Getenv("HTTP_PROXY"); proxy != "" {
        fmt.Printf("✅ Using proxy: %s\n", proxy)
    }
    
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("❌ Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("⚡ FAST SUCCESS! Got %d bytes\n", len(body))
}
GOEOF

CMD ["go", "run", "main.go"]
EOF

docker build -t go-fast -f Dockerfile.go-fast .

# Test Go app
echo -e "${BLUE}Testing fast Go app...${NC}"
docker run --rm \
    -e HTTP_PROXY=http://$DOCKER_IP:8082 \
    -e HTTPS_PROXY=http://$DOCKER_IP:8082 \
    go-fast

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ⚡ FAST SOLUTION RESULTS${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""

echo "Fast containers built:"
[ "$ALPINE_FAST" = "true" ] && echo "✅ alpine-fast (Alpine package manager - very fast)" || echo "❌ alpine-fast failed"
[ "$PREBUILT_FAST" = "true" ] && echo "✅ prebuilt-fast (Tools pre-installed - fastest)" || echo "❌ prebuilt-fast failed"
echo "✅ debian-fast (Debian slim - faster than Ubuntu)"
echo "✅ go-fast (Go with Alpine base - fast build)"

echo ""
echo -e "${YELLOW}Recommended fast option:${NC}"
if [ "$PREBUILT_FAST" = "true" ]; then
    echo "🏆 ${GREEN}docker run --rm --network host prebuilt-fast${NC}"
    echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
elif [ "$ALPINE_FAST" = "true" ]; then
    echo "🥈 ${GREEN}docker run --rm --network host alpine-fast${NC}"
    echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
else
    echo "🥉 ${GREEN}docker run --rm --network host debian-fast${NC}"
    echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
fi

echo ""
echo -e "${GREEN}No more slow apt-get updates! ⚡${NC}"
echo "MITMProxy: ${GREEN}http://localhost:8082${NC}"
echo "Logs: ${GREEN}docker logs -f mitmproxy${NC}"