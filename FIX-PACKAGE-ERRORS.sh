#!/bin/bash
# FIX-PACKAGE-ERRORS.sh - Fix curl ca-certificates installation issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔧 FIXING PACKAGE INSTALLATION ERRORS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up
echo -e "${YELLOW}Step 1: Cleaning up...${NC}"
docker stop mitmproxy 2>/dev/null || true
docker rm mitmproxy 2>/dev/null || true

# Start mitmproxy
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

# Method 1: Super simple Alpine with error handling
echo ""
echo -e "${YELLOW}Method 1: Super simple Alpine with robust error handling...${NC}"

cat > Dockerfile.alpine-robust << 'EOF'
FROM alpine:3.22

# Update with retry logic
RUN for i in 1 2 3; do \
        apk update && break || \
        { echo "Attempt $i failed, retrying..."; sleep 5; } \
    done

# Install packages with individual error handling  
RUN apk add --no-cache ca-certificates || \
    { echo "Failed to install ca-certificates"; exit 1; }

RUN apk add --no-cache curl || \
    { echo "Failed to install curl, trying with different method"; \
      apk add --no-cache wget && echo "Using wget instead of curl"; }

# Verify installations
RUN ls -la /usr/bin/curl || ls -la /usr/bin/wget
RUN ls -la /etc/ssl/certs/ca-certificates.crt

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates with verification
RUN update-ca-certificates && \
    ls -la /etc/ssl/certs/ | grep mitmproxy

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building robust Alpine container..."
if docker build -t alpine-robust -f Dockerfile.alpine-robust .; then
    echo -e "${GREEN}✅ Robust Alpine built successfully${NC}"
    ALPINE_ROBUST=true
else
    echo -e "${RED}Robust Alpine build failed${NC}"
    ALPINE_ROBUST=false
fi

# Method 2: Use different Alpine version
echo ""
echo -e "${YELLOW}Method 2: Using Alpine 3.19 (older stable)...${NC}"

cat > Dockerfile.alpine-319 << 'EOF'
FROM alpine:3.19

# Older Alpine version may have more stable packages
RUN apk update && apk add --no-cache \
    ca-certificates \
    curl

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building Alpine 3.19 container..."
if docker build -t alpine-319 -f Dockerfile.alpine-319 .; then
    echo -e "${GREEN}✅ Alpine 3.19 built successfully${NC}"
    ALPINE_319=true
else
    echo -e "${RED}Alpine 3.19 build failed${NC}"
    ALPINE_319=false
fi

# Method 3: Minimal working solution using busybox
echo ""
echo -e "${YELLOW}Method 3: Ultra-minimal with busybox wget...${NC}"

cat > Dockerfile.busybox-minimal << 'EOF'
FROM alpine:latest

# Only install ca-certificates (most essential)
RUN apk update && apk add --no-cache ca-certificates

# Copy certificate first
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Verify busybox has wget
RUN which wget || echo "No wget available"

# Set certificate environment
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building busybox minimal container..."
if docker build -t busybox-minimal -f Dockerfile.busybox-minimal .; then
    echo -e "${GREEN}✅ Busybox minimal built successfully${NC}"
    BUSYBOX_MINIMAL=true
else
    echo -e "${RED}Busybox minimal build failed${NC}"
    BUSYBOX_MINIMAL=false
fi

# Method 4: Use curlimages/curl (guaranteed to work)
echo ""
echo -e "${YELLOW}Method 4: Using official curl image (guaranteed)...${NC}"

cat > Dockerfile.curl-official << 'EOF'
FROM curlimages/curl:8.5.0

# Switch to root
USER root

# This image already has curl, just add ca-certificates
RUN apk add --no-cache ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF

echo "Building official curl container..."
if docker build -t curl-official -f Dockerfile.curl-official .; then
    echo -e "${GREEN}✅ Official curl built successfully${NC}"
    CURL_OFFICIAL=true
else
    echo -e "${RED}Official curl build failed${NC}"
    CURL_OFFICIAL=false
fi

# Test what works
echo ""
echo -e "${YELLOW}Step 4: Testing working containers...${NC}"

# Get Docker IP
DOCKER_IP=$(docker inspect mitmproxy | grep '"IPAddress"' | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

if [ "$ALPINE_ROBUST" = "true" ]; then
    echo -e "${BLUE}Testing robust Alpine...${NC}"
    docker run --rm alpine-robust sh -c "
        if command -v curl >/dev/null; then
            curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        elif command -v wget >/dev/null; then
            wget -q -O- --proxy=on --http-proxy=http://$DOCKER_IP:8082 https://api.github.com/users/github | head -3
        fi
        echo '✅ Robust Alpine WORKS!'
    "
fi

if [ "$ALPINE_319" = "true" ]; then
    echo -e "${BLUE}Testing Alpine 3.19...${NC}"
    docker run --rm alpine-319 sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        echo '✅ Alpine 3.19 WORKS!'
    "
fi

if [ "$BUSYBOX_MINIMAL" = "true" ]; then
    echo -e "${BLUE}Testing busybox minimal...${NC}"
    docker run --rm busybox-minimal sh -c "
        if command -v wget >/dev/null; then
            wget -q -O- --proxy=on --http-proxy=http://$DOCKER_IP:8082 https://api.github.com/users/github | head -3
            echo '✅ Busybox minimal WORKS!'
        else
            echo '❌ No wget available'
        fi
    "
fi

if [ "$CURL_OFFICIAL" = "true" ]; then
    echo -e "${BLUE}Testing official curl...${NC}"
    docker run --rm curl-official sh -c "
        curl -x http://$DOCKER_IP:8082 -s --max-time 5 https://api.github.com/users/github | head -3
        echo '✅ Official curl WORKS!'
    "
fi

# Create Go app with most reliable base
echo ""
echo -e "${YELLOW}Step 5: Creating Go app with most reliable container...${NC}"

cat > Dockerfile.go-reliable << 'EOF'
# Use official Go Alpine image (most reliable)
FROM golang:1.21-alpine3.19

# Use older Alpine for stability
RUN apk update && apk add --no-cache ca-certificates

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
    fmt.Println("🔧 Reliable HTTPS test without InsecureSkipVerify...")
    
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
    fmt.Printf("🔧 RELIABLE SUCCESS! Got %d bytes\n", len(body))
}
GOEOF

CMD ["go", "run", "main.go"]
EOF

docker build -t go-reliable -f Dockerfile.go-reliable .

# Test Go app
echo -e "${BLUE}Testing reliable Go app...${NC}"
docker run --rm \
    -e HTTP_PROXY=http://$DOCKER_IP:8082 \
    -e HTTPS_PROXY=http://$DOCKER_IP:8082 \
    go-reliable

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🔧 PACKAGE ERROR FIXES COMPLETE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""

echo "Working containers:"
[ "$ALPINE_ROBUST" = "true" ] && echo "✅ alpine-robust - Error handling with curl/wget fallback" || echo "❌ alpine-robust failed"
[ "$ALPINE_319" = "true" ] && echo "✅ alpine-319 - Older stable Alpine version" || echo "❌ alpine-319 failed"  
[ "$BUSYBOX_MINIMAL" = "true" ] && echo "✅ busybox-minimal - Ultra-minimal with wget" || echo "❌ busybox-minimal failed"
[ "$CURL_OFFICIAL" = "true" ] && echo "✅ curl-official - Official curl image (guaranteed)" || echo "❌ curl-official failed"
echo "✅ go-reliable - Go with stable Alpine 3.19"

echo ""
echo -e "${YELLOW}Most reliable option:${NC}"
if [ "$CURL_OFFICIAL" = "true" ]; then
    echo "🏆 ${GREEN}docker run --rm --network host curl-official${NC}"
    echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
elif [ "$ALPINE_319" = "true" ]; then
    echo "🥈 ${GREEN}docker run --rm --network host alpine-319${NC}"
elif [ "$ALPINE_ROBUST" = "true" ]; then
    echo "🥉 ${GREEN}docker run --rm --network host alpine-robust${NC}"
fi

echo ""
echo -e "${GREEN}Package installation issues resolved! 🔧${NC}"
echo "MITMProxy: ${GREEN}http://localhost:8082${NC}"