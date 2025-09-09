#!/bin/bash
# START-FIX-2: Run your Go app with PROXY MODE
# Default app: ~/temp/aa/cmd/api/main.go
# REQUIRES: Your Go app must use http.ProxyFromEnvironment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Default to your specific app if no argument provided
GO_APP_CMD="${1:-go run ~/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STARTING FIX-2: PROXY MODE (HTTP_PROXY)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""
echo -e "${RED}REQUIRED:${NC} Your Go app must have:"
echo "  client := &http.Client{"
echo "      Transport: &http.Transport{"
echo "          Proxy: http.ProxyFromEnvironment,"
echo "      },"
echo "  }"
echo ""

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

# Start your app with proxy settings
echo -e "${YELLOW}Starting your Go app with proxy settings...${NC}"

# Create a temporary container for your app
docker run -d \
    --name go-app-proxied \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -v ~/temp:/home/appuser/temp:ro \
    -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -e SSL_CERT_FILE=/ca.pem \
    -w /home/appuser \
    golang:1.23-alpine \
    sh -c "
        echo 'Starting with proxy settings...'
        echo 'HTTP_PROXY=\$HTTP_PROXY'
        echo 'HTTPS_PROXY=\$HTTPS_PROXY'
        $GO_APP_CMD
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
echo -e "${YELLOW}If no captures:${NC} Your Go app needs ProxyFromEnvironment!"