#!/bin/bash
# FIX-APK-PACKAGES.sh - Fix package installation issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING APK PACKAGE ISSUES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Test what packages are available
echo -e "${YELLOW}Testing package availability...${NC}"

docker run --rm alpine:latest sh -c "
    echo 'Updating package index...'
    apk update
    
    echo ''
    echo 'Testing individual packages...'
    
    echo -n 'curl: '
    apk info curl >/dev/null 2>&1 && echo 'Available' || echo 'Not found'
    
    echo -n 'ca-certificates: '
    apk info ca-certificates >/dev/null 2>&1 && echo 'Available' || echo 'Not found'
    
    echo -n 'wget: '
    apk info wget >/dev/null 2>&1 && echo 'Available' || echo 'Not found'
    
    echo -n 'bash: '
    apk info bash >/dev/null 2>&1 && echo 'Available' || echo 'Not found'
"

# Create fixed Dockerfile
echo ""
echo -e "${YELLOW}Creating fixed Dockerfile...${NC}"

cat > Dockerfile.trusted-fixed << 'EOF'
FROM alpine:latest

# Update package index first
RUN apk update

# Install packages individually to catch errors
RUN apk add --no-cache curl && \
    apk add --no-cache ca-certificates && \
    apk add --no-cache wget && \
    apk add --no-cache bash

# Alternative: use busybox if bash fails
RUN if ! command -v bash > /dev/null; then \
        echo "Bash not available, using busybox sh"; \
    fi

# Copy and install the mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

CMD ["/bin/sh"]
EOF

# Test building the fixed Dockerfile
echo ""
echo -e "${YELLOW}Testing fixed Dockerfile build...${NC}"

if [ -f mitmproxy-ca.pem ]; then
    docker build -t trusted-client-fixed -f Dockerfile.trusted-fixed . || {
        echo -e "${RED}Build failed, trying minimal version...${NC}"
        
        # Create even simpler version
        cat > Dockerfile.minimal << 'EOF'
FROM alpine:latest

# Just install the essentials
RUN apk update && apk add --no-cache curl ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/sh"]
EOF
        
        docker build -t trusted-client-minimal -f Dockerfile.minimal .
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Minimal version built successfully${NC}"
        fi
    }
else
    echo -e "${RED}mitmproxy-ca.pem not found${NC}"
    echo "Run ./CONTAINER-TRUST-CERTS.sh to get the certificate first"
fi

# Alternative: Use Ubuntu base if Alpine has issues
echo ""
echo -e "${YELLOW}Creating Ubuntu-based alternative...${NC}"

cat > Dockerfile.ubuntu-trusted << 'EOF'
FROM ubuntu:latest

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

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
CMD ["/bin/bash"]
EOF

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ALTERNATIVE SOLUTIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "If Alpine packages fail, try:"
echo ""
echo "1. Use the minimal Alpine version:"
echo "   ${GREEN}docker build -t trusted-client -f Dockerfile.minimal .${NC}"
echo ""
echo "2. Use Ubuntu base instead:"
echo "   ${GREEN}docker build -t trusted-client -f Dockerfile.ubuntu-trusted .${NC}"
echo ""
echo "3. Test package availability first:"
echo "   ${GREEN}docker run --rm alpine:latest apk update${NC}"
echo "   ${GREEN}docker run --rm alpine:latest apk info curl${NC}"
echo ""
echo "4. Use existing Alpine image tools:"
echo "   ${GREEN}docker run --rm alpine:latest sh -c 'which curl wget'${NC}"