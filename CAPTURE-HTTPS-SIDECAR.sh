#!/bin/bash
# CAPTURE-HTTPS-SIDECAR.sh - Run app and proxy in same container
# Captures ALL HTTPS content without any app modifications

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

# Your Go app command
GO_APP_CMD="${1:-go run ~/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIDECAR: APP + PROXY IN SAME CONTAINER${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}NO changes needed to your Go app!${NC}"
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Create a custom Dockerfile for the sidecar
cat > /tmp/Dockerfile.sidecar << 'EOF'
FROM mitmproxy/mitmproxy

# Install Go and required tools
USER root
RUN apk add --no-cache go git ca-certificates iptables sudo

# Create directories
RUN mkdir -p /captured /scripts /app

# Setup user
RUN addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser && \
    echo "appuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Copy scripts
COPY scripts/capture_https.py /scripts/

WORKDIR /app
EOF

echo -e "${YELLOW}Building sidecar image...${NC}"
docker build -t sidecar-capture -f /tmp/Dockerfile.sidecar .

echo -e "${YELLOW}Starting sidecar container with app and proxy...${NC}"

docker run -d \
    --name app-sidecar \
    --cap-add NET_ADMIN \
    -p 8080:8080 \
    -p 8090:8090 \
    -v ~/temp:/app:ro \
    -v $(pwd)/captured:/captured \
    sidecar-capture \
    sh -c "
        echo '🚀 Starting sidecar container...'
        
        # Start mitmproxy in background
        echo '📡 Starting mitmproxy...'
        mitmdump --mode transparent \
                 --listen-port 8084 \
                 --scripts /scripts/capture_https.py \
                 --set block_global=false \
                 --ssl-insecure \
                 > /tmp/proxy.log 2>&1 &
        PROXY_PID=\$!
        
        # Wait for proxy to start
        sleep 3
        
        # Setup iptables for transparent capture
        echo '🔧 Setting up transparent interception...'
        iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
        iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
        
        # Get and install certificate
        echo '🔐 Installing certificate...'
        cat ~/.mitmproxy/mitmproxy-ca-cert.pem > /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates
        
        # Start the app as appuser
        echo '🚀 Starting your Go app...'
        cd /app
        su appuser -c '${GO_APP_CMD#~/temp}'
        
        # Keep proxy running
        wait \$PROXY_PID
    "

echo -e "${GREEN}✅ Sidecar container starting...${NC}"
sleep 5

# Check status
if docker ps | grep -q app-sidecar; then
    echo -e "${GREEN}✅ Sidecar is running!${NC}"
else
    echo -e "${RED}❌ Sidecar failed to start${NC}"
    echo "Check logs: docker logs app-sidecar"
    exit 1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Sidecar running with HTTPS capture${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ NO environment variables needed${NC}"
echo -e "${GREEN}✅ NO proxy configuration needed${NC}"
echo -e "${GREEN}✅ ALL HTTPS traffic captured transparently${NC}"
echo ""
echo "📍 Your app: http://localhost:8080"
echo "📍 Captures saved to: captured/"
echo "📍 View logs: docker logs app-sidecar"
echo ""
echo -e "${YELLOW}Test HTTPS capture:${NC}"
echo "docker exec app-sidecar su appuser -c 'wget -O- https://api.github.com'"
echo ""
echo -e "${YELLOW}View captured requests:${NC}"
echo "ls -la captured/*.json"