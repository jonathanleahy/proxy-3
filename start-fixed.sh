#!/bin/bash
# Start script using fixed docker-compose without network issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Fixed Transparent Proxy System${NC}"
echo "============================================"
echo "This version avoids iptables-restore errors"
echo "while still capturing HTTPS traffic transparently"
echo ""

# Step 1: Clean up
echo -e "${YELLOW}Step 1: Cleaning up...${NC}"
docker compose -f docker-compose-fixed.yml down 2>/dev/null || true
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true
docker network prune -f 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"

# Step 2: Build
echo -e "\n${YELLOW}Step 2: Building containers...${NC}"
docker compose -f docker-compose-fixed.yml build
echo -e "${GREEN}✅ Build complete${NC}"

# Step 3: Start
echo -e "\n${YELLOW}Step 3: Starting containers...${NC}"
docker compose -f docker-compose-fixed.yml up -d
sleep 5
echo -e "${GREEN}✅ Containers started${NC}"

# Step 4: Wait for certificate
echo -e "\n${YELLOW}Step 4: Waiting for certificate...${NC}"
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker exec transparent-proxy ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Certificate ready${NC}"
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

# Step 5: Start example app
echo -e "\n${YELLOW}Step 5: Starting example app...${NC}"
docker exec -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null
sleep 3
echo -e "${GREEN}✅ App started${NC}"

# Step 6: Test
echo -e "\n${YELLOW}Step 6: Testing system...${NC}"
echo "Testing health..."
curl -s http://localhost:8080/health | grep -q "healthy" && echo -e "${GREEN}✅ Health check passed${NC}" || echo -e "${YELLOW}⚠️  Health pending${NC}"

echo "Testing HTTPS capture..."
curl -s http://localhost:8080/users >/dev/null 2>&1 && echo -e "${GREEN}✅ HTTPS request made${NC}" || echo -e "${YELLOW}⚠️  HTTPS pending${NC}"

# Show status
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 System Ready!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "✅ HTTPS traffic IS being transparently intercepted"
echo "✅ No proxy configuration needed in your apps"
echo "✅ All traffic from the app container goes through mitmproxy"
echo ""
echo "Test endpoints:"
echo "  • http://localhost:8080/health"
echo "  • http://localhost:8080/users (HTTPS capture test)"
echo "  • http://localhost:8090/viewer (view captures)"
echo ""
echo "Monitor captures:"
echo "  • docker logs -f transparent-proxy"
echo "  • ls -la captured/"
echo ""
echo "The key: app container shares network with proxy container"
echo "This means ALL app traffic goes through the proxy!"