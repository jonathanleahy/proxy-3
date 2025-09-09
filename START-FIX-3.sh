#!/bin/bash
# START-FIX-3: Run your Go app with NETWORK NAMESPACE SHARING
# Default app: ~/temp/aa/cmd/api/main.go
# Forces ALL traffic through proxy - no code changes needed!

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
echo -e "${BLUE}  STARTING FIX-3: NETWORK NAMESPACE SHARING${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""
echo -e "${GREEN}NO CODE CHANGES NEEDED!${NC}"
echo "All network traffic will be forced through the proxy"
echo ""

# Clean up first
cleanup_all_containers

# First ensure FIX-3 is running
echo -e "${YELLOW}Setting up network sharing proxy...${NC}"
./FIX-3-NETWORK-SHARING.sh

echo ""
echo -e "${YELLOW}Waiting for proxy to be ready...${NC}"
sleep 5

# Stop any existing app container
docker stop go-app-shared 2>/dev/null || true
docker rm go-app-shared 2>/dev/null || true

# Start your app sharing the proxy's network
echo -e "${YELLOW}Starting your Go app with shared network...${NC}"

docker run -d \
    --name go-app-shared \
    --network container:go-proxy-transparent \
    -v ~/temp:/home/appuser/temp:ro \
    -w /home/appuser \
    golang:1.23-alpine \
    sh -c "
        echo 'Starting with shared network namespace...'
        echo 'All traffic will be intercepted!'
        addgroup -g 1000 -S appuser 2>/dev/null || true
        adduser -u 1000 -S appuser -G appuser 2>/dev/null || true
        su appuser -c '$GO_APP_CMD'
    "

echo -e "${GREEN}✅ App container starting...${NC}"
sleep 5

# Check if app is running
if docker ps | grep -q go-app-shared; then
    echo -e "${GREEN}✅ App is running with shared network!${NC}"
    echo "All HTTPS traffic is being intercepted!"
else
    echo -e "${RED}❌ App may have failed to start${NC}"
    echo "Check logs: docker logs go-app-shared"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Test your app:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Call your app: curl http://localhost:8080/your-endpoint"
echo "2. View captures: http://localhost:8090/viewer"
echo "3. Check captures: ls -la captured/*.json"
echo "4. Monitor proxy: docker logs -f go-proxy-transparent"
echo ""
echo -e "${GREEN}ALL traffic is being captured - no proxy config needed!${NC}"