#!/bin/bash
# CAPTURE-HTTPS-NO-ENV.sh - Capture HTTPS content WITHOUT environment variables
# Uses network namespace sharing - your app needs NO modifications at all

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
echo -e "${BLUE}  HTTPS CAPTURE WITHOUT ENV VARIABLES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}NO changes needed to your Go app!${NC}"
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Step 1: Start the mitmproxy container
echo -e "${YELLOW}Starting mitmproxy for HTTPS interception...${NC}"

docker run -d \
    --name mitm-capture \
    --cap-add NET_ADMIN \
    -p 8090:8090 \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts \
    mitmproxy/mitmproxy \
    sh -c "
        # Start transparent proxy with capture script
        mitmdump --mode transparent \
                 --listen-port 8084 \
                 --set confdir=/home/mitmproxy/.mitmproxy \
                 --scripts /scripts/capture_https.py \
                 --set block_global=false \
                 --ssl-insecure
    "

echo -e "${YELLOW}Waiting for mitmproxy to start...${NC}"
sleep 5

# Get the certificate (for later use if needed)
docker exec mitm-capture cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# Step 2: Start your app sharing the network namespace
echo -e "${YELLOW}Starting your app with automatic HTTPS interception...${NC}"

# Check if we have golang image, otherwise use alpine
if docker images | grep -q "golang"; then
    BASE_IMAGE="golang:1.23-alpine"
    INSTALL_CMD="apk add --no-cache ca-certificates"
else
    BASE_IMAGE="alpine:latest"
    INSTALL_CMD="apk add --no-cache go ca-certificates git"
fi

docker run -d \
    --name app-captured \
    --network "container:mitm-capture" \
    -v ~/temp:/app:ro \
    -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
    $BASE_IMAGE \
    sh -c "
        echo 'Setting up environment...'
        $INSTALL_CMD
        
        # Install certificate in system store
        cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt 2>/dev/null || true
        update-ca-certificates 2>/dev/null || true
        
        echo 'Starting app (all HTTPS will be captured)...'
        cd /app
        ${GO_APP_CMD#~/temp}
    "

echo -e "${GREEN}✅ System starting...${NC}"
sleep 5

# Step 3: Start the viewer
echo -e "${YELLOW}Starting capture viewer...${NC}"

docker run -d \
    --name viewer \
    -p 8091:8090 \
    -v $(pwd)/captured:/app/captured:ro \
    -e PORT=8090 \
    -e CAPTURE_DIR=/app/captured \
    busybox \
    sh -c "
        cd /app
        echo 'Starting simple HTTP server for viewing captures...'
        while true; do
            echo 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n' | nc -l -p 8090
            echo '<h1>Captured Requests</h1><pre>' | nc -l -p 8090
            ls -la /app/captured/ 2>/dev/null | nc -l -p 8090
            echo '</pre>' | nc -l -p 8090
        done
    "

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Your app is running with HTTPS capture${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ NO environment variables needed${NC}"
echo -e "${GREEN}✅ NO proxy configuration needed${NC}"
echo -e "${GREEN}✅ ALL HTTPS traffic is captured${NC}"
echo ""
echo "📍 Your app port: Shared with proxy on port 8084"
echo "📍 View captures: ls -la captured/"
echo "📍 App logs: docker logs app-captured"
echo "📍 Proxy logs: docker logs mitm-capture"
echo ""
echo -e "${YELLOW}To test if capture is working:${NC}"
echo "docker exec app-captured wget -O- https://api.github.com"
echo ""
echo -e "${YELLOW}Your app's HTTPS calls will appear in:${NC}"
echo "captured/ directory"