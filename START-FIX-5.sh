#!/bin/bash
# START-FIX-5: Run your Go app with PROVEN WORKING SOLUTION
# Default app: ~/temp/aa/cmd/api/main.go
# Uses FINAL-CLEANUP-AND-RUN.sh - the most reliable solution

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
echo -e "${BLUE}  STARTING FIX-5: PROVEN WORKING SOLUTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""
echo -e "${GREEN}This is the most reliable solution!${NC}"
echo ""

# First run FIX-5 setup
echo -e "${YELLOW}Setting up proven working proxy...${NC}"
./FIX-5-WORKING-PROXY.sh

echo ""
echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Stop any old app container
docker stop go-app-fix5 2>/dev/null || true
docker rm go-app-fix5 2>/dev/null || true

# Get the certificate
if [ ! -f mitmproxy-ca.pem ]; then
    echo -e "${YELLOW}Getting certificate...${NC}"
    docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true
fi

# Start your app with proxy configuration
echo -e "${YELLOW}Starting your Go app...${NC}"

docker run -d \
    --name go-app-fix5 \
    -p 8080:8080 \
    -v ~/temp:/temp:ro \
    -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -e SSL_CERT_FILE=/ca.pem \
    -w / \
    golang:1.23-alpine \
    sh -c "
        echo 'Setting up user...'
        addgroup -g 1000 -S appuser 2>/dev/null || true
        adduser -u 1000 -S appuser -G appuser 2>/dev/null || true
        
        echo 'Copying app files...'
        cp -r /temp /home/appuser/temp
        chown -R appuser:appuser /home/appuser/temp
        
        echo 'Starting with proxy configuration...'
        echo 'HTTP_PROXY=\$HTTP_PROXY'
        echo 'HTTPS_PROXY=\$HTTPS_PROXY'
        
        su appuser -c 'cd /home/appuser && $GO_APP_CMD'
    "

echo -e "${GREEN}✅ App starting...${NC}"
sleep 5

# Check if app is running
if docker ps | grep -q go-app-fix5; then
    echo -e "${GREEN}✅ App is running!${NC}"
else
    echo -e "${RED}❌ App may have failed to start${NC}"
    echo "Check logs: docker logs go-app-fix5"
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
echo -e "${YELLOW}Note:${NC} Your Go app needs http.ProxyFromEnvironment for this to work!"