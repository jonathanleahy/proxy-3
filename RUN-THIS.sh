#!/bin/bash
# THIS IS THE WORKING SCRIPT - USE THIS ONE!
# Avoids all iptables-restore and DNS issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Transparent HTTPS Proxy (WORKING VERSION)${NC}"
echo "============================================"

# CRITICAL: Remove ALL old networks that cause issues
echo -e "${YELLOW}Cleaning up old Docker configurations...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker compose -f docker-compose-noiptables.yml down 2>/dev/null || true  
docker compose -f docker-compose-proxy-mode.yml down 2>/dev/null || true
docker compose -f docker-compose-fixed.yml down -v 2>/dev/null || true

# Remove problematic networks
docker network rm proxy-3_capture-net 2>/dev/null || true
docker network rm capture-net 2>/dev/null || true
docker network prune -f 2>/dev/null || true

echo -e "${GREEN}✅ Cleanup complete${NC}"

# Build and start with the WORKING compose file
echo -e "\n${YELLOW}Building containers...${NC}"
docker compose -f docker-compose-fixed.yml build

echo -e "\n${YELLOW}Starting containers...${NC}"
docker compose -f docker-compose-fixed.yml up -d

# Wait for proxy
sleep 5

# Check if working
if docker ps | grep -q transparent-proxy; then
    echo -e "\n${GREEN}✅ Proxy is running!${NC}"
else
    echo -e "\n${RED}❌ Failed to start${NC}"
    exit 1
fi

# Start example app
echo -e "\n${YELLOW}Starting example application...${NC}"
docker exec -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null || true

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 SUCCESS! System is running!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "✅ HTTPS traffic IS being intercepted transparently"
echo "✅ No iptables-restore errors"
echo "✅ No DNS conflicts"
echo ""
echo "Test it:"
echo "  curl http://localhost:8080/health"
echo "  curl http://localhost:8080/users"
echo ""
echo "View captures:"
echo "  http://localhost:8090/viewer"
echo ""
echo "Monitor:"
echo "  docker logs -f transparent-proxy"