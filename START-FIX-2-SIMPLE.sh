#!/bin/bash
# START-FIX-2-SIMPLE: Run your Go app with PROXY MODE using basic alpine
# Uses alpine:latest with Go installed - more reliable for restricted environments

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

# Default to your specific app if no argument provided
GO_APP_CMD="${1:-go run ~/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STARTING FIX-2-SIMPLE: PROXY MODE (Alpine)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""

# Clean up first
cleanup_all_containers

# First ensure FIX-2 is running
echo -e "${YELLOW}Setting up proxy mode...${NC}"
./FIX-2-PROXY-MODE.sh

echo ""
echo -e "${YELLOW}Waiting for proxy to be ready...${NC}"
sleep 5

# Get the certificate
if [ -f mitmproxy-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate found${NC}"
else
    echo -e "${YELLOW}Getting certificate...${NC}"
    docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true
fi

# Start your app with proxy settings using basic alpine
echo -e "${YELLOW}Starting your Go app with proxy settings...${NC}"

docker run -d \
    --name go-app-proxied \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -v ~/temp:/app:ro \
    -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -e SSL_CERT_FILE=/ca.pem \
    -e GOPROXY=direct \
    -w /app \
    alpine:latest \
    sh -c "
        echo 'Installing Go and certificates...'
        apk add --no-cache go ca-certificates git
        
        echo 'Setting up certificate...'
        cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates
        
        echo 'Go version:'
        go version
        
        echo 'Starting with proxy settings...'
        echo 'HTTP_PROXY=\$HTTP_PROXY'
        echo 'HTTPS_PROXY=\$HTTPS_PROXY'
        
        cd /app
        ${GO_APP_CMD#~/temp}
    "

echo -e "${GREEN}✅ App container starting...${NC}"
sleep 5

# Check if app is running
if docker logs go-app-proxied 2>&1 | grep -q "Starting with proxy"; then
    echo -e "${GREEN}✅ App is running with proxy!${NC}"
else
    echo -e "${RED}❌ App may have failed to start${NC}"
    echo "Check logs: docker logs go-app-proxied"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Test your app:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Call your app: curl http://localhost:8080/your-endpoint"
echo "2. View captures: http://localhost:8090/viewer"
echo "3. Check captures: ls -la captured/*.json"
echo "4. Monitor proxy: docker logs -f proxy"
echo ""
echo -e "${YELLOW}If still having issues, try:${NC}"
echo "./FIX-CERT-GO-CODE.sh  # For Go code changes needed"