#!/bin/bash
# START-FIX-1: Run your Go app with TRANSPARENT MODE
# Default app: ~/temp/aa/cmd/api/main.go

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
echo -e "${BLUE}  STARTING FIX-1: TRANSPARENT MODE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""

# Clean up first
cleanup_all_containers

# First ensure FIX-1 is running
echo -e "${YELLOW}Setting up transparent proxy...${NC}"
./FIX-1-TRANSPARENT-MODE.sh

echo ""
echo -e "${YELLOW}Waiting for proxy to be ready...${NC}"
sleep 5

# Mount the host's home directory into container
echo -e "${YELLOW}Starting your Go app...${NC}"

# Kill any existing app processes
docker exec app sh -c "pkill -f 'go run' 2>/dev/null || true"
sleep 1

# Start the app with access to ~/temp directory
docker exec -d app su appuser -s /bin/sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export HOME=/home/appuser
    # Copy or mount your app directory
    cp -r /proxy/temp ~/temp 2>/dev/null || true
    cd ~
    $GO_APP_CMD
"

echo -e "${GREEN}✅ App starting...${NC}"
sleep 5

# Check if app is running
if docker exec app sh -c "ps aux | grep -v grep | grep 'go run'" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ App is running!${NC}"
else
    echo -e "${RED}❌ App may have failed to start${NC}"
    echo "Check logs: docker exec app sh -c 'tail -100 /tmp/go-build*/b001/exe/main'"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Test your app:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Call your app: curl http://localhost:8080/your-endpoint"
echo "2. View captures: http://localhost:8090/viewer"
echo "3. Check captures: ls -la captured/*.json"
echo "4. Monitor proxy: docker logs -f transparent-proxy"
echo ""
echo -e "${YELLOW}Note:${NC} Make sure your ~/temp/aa directory is accessible"