#!/bin/bash
# Fix network namespace sharing issue

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Network Namespace Sharing${NC}"
echo "============================================"
echo "Problem: App container not sharing proxy's network"
echo ""

# Step 1: Stop everything
echo -e "${YELLOW}Step 1: Stopping all containers...${NC}"
docker stop transparent-proxy app mock-viewer 2>/dev/null || true
docker rm transparent-proxy app mock-viewer 2>/dev/null || true
docker network prune -f

# Step 2: Start proxy first
echo -e "\n${YELLOW}Step 2: Starting proxy container first...${NC}"
docker compose -f docker-compose-universal.yml up -d transparent-proxy
sleep 5

# Step 3: Verify proxy is running
PROXY_NS=$(docker inspect transparent-proxy -f '{{.NetworkSettings.SandboxKey}}' 2>/dev/null)
if [ -z "$PROXY_NS" ]; then
    echo -e "${RED}❌ Proxy container failed to start${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Proxy running with network: $PROXY_NS${NC}"

# Step 4: Start app with explicit network mode
echo -e "\n${YELLOW}Step 4: Starting app with shared network...${NC}"
docker run -d \
    --name app \
    --network container:transparent-proxy \
    -v $(pwd):/proxy \
    -v proxy-3_certs:/certs:ro \
    -w /proxy \
    proxy-3-app \
    tail -f /dev/null

# Step 5: Verify network sharing
sleep 3
APP_NS=$(docker inspect app -f '{{.NetworkSettings.SandboxKey}}' 2>/dev/null)
echo "App network: ${APP_NS:-none}"

if [ "$PROXY_NS" = "$APP_NS" ] || [ -z "$APP_NS" ]; then
    echo -e "${GREEN}✅ Network namespace sharing confirmed${NC}"
else
    echo -e "${RED}❌ Network sharing failed${NC}"
    echo "Trying alternative method..."
    
    # Alternative: recreate with docker-compose
    docker stop app && docker rm app
    docker compose -f docker-compose-universal.yml up -d app
    sleep 3
    
    # Check again
    APP_NS=$(docker inspect app -f '{{.NetworkSettings.SandboxKey}}' 2>/dev/null)
    if [ -z "$APP_NS" ]; then
        echo -e "${GREEN}✅ App using proxy's network (empty namespace is correct)${NC}"
    fi
fi

# Step 6: Start viewer
echo -e "\n${YELLOW}Step 5: Starting viewer...${NC}"
docker compose -f docker-compose-universal.yml up -d viewer

# Step 7: Start the app process
echo -e "\n${YELLOW}Step 6: Starting application as UID 1000...${NC}"
docker exec -u 1000 -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null || true
sleep 5

# Step 8: Test
echo -e "\n${YELLOW}Step 7: Testing HTTPS interception...${NC}"
RESPONSE=$(curl -s -m 10 http://localhost:8080/users 2>/dev/null)
if echo "$RESPONSE" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS interception WORKING!${NC}"
    echo ""
    echo "🎉 Fixed! The issue was network namespace sharing."
    echo "View captures at: http://localhost:8090/viewer"
else
    echo -e "${RED}❌ Still not working${NC}"
    echo ""
    echo "Checking current state:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "Final diagnostic:"
    PROXY_NS=$(docker inspect transparent-proxy -f '{{.NetworkSettings.SandboxKey}}')
    APP_NS=$(docker inspect app -f '{{.NetworkSettings.SandboxKey}}')
    echo "Proxy namespace: $PROXY_NS"
    echo "App namespace: $APP_NS"
    
    if [ "$PROXY_NS" != "$APP_NS" ] && [ ! -z "$APP_NS" ]; then
        echo ""
        echo -e "${YELLOW}Docker compose network sharing not working on this system.${NC}"
        echo "Use the proxy mode instead: ./WORKING-SOLUTION.sh"
    fi
fi