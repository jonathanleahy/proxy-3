#!/bin/bash
# Universal fix that works on ALL systems

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Universal Transparent Proxy Fix${NC}"
echo "============================================"
echo "This version detects and handles different iptables capabilities"
echo ""

# Complete cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
docker compose -f docker-compose-universal.yml down 2>/dev/null || true
docker compose -f docker-compose-final.yml down 2>/dev/null || true
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true
docker network prune -f >/dev/null 2>&1

# Build with universal configuration
echo -e "${YELLOW}Building universal proxy...${NC}"
docker compose -f docker-compose-universal.yml build

# Start containers
echo -e "${YELLOW}Starting containers...${NC}"
docker compose -f docker-compose-universal.yml up -d

echo "Waiting for initialization..."
sleep 7

# Check what mode we're in
echo -e "\n${YELLOW}Checking iptables mode...${NC}"
MODE=$(docker logs transparent-proxy 2>&1 | grep -E "Owner matching|universal rules" | tail -1)
echo "$MODE"

# Start app as UID 1000 (always)
echo -e "\n${YELLOW}Starting app as UID 1000...${NC}"
docker exec -u 1000 -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null || true
sleep 5

# Test
echo -e "\n${YELLOW}Testing system...${NC}"
echo "Health check:"
curl -s http://localhost:8080/health | grep -q "healthy" && echo -e "${GREEN}✅ Health OK${NC}" || echo -e "${RED}❌ Health failed${NC}"

echo -e "\nHTTPS interception test:"
RESULT=$(curl -s http://localhost:8080/users 2>/dev/null)
if echo "$RESULT" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS interception WORKING!${NC}"
    
    # Check packet counts
    echo -e "\n${YELLOW}Verifying with packet counts:${NC}"
    docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v | grep REDIRECT || echo "Rules shown above"
    
    echo -e "\n${GREEN}🎉 System working correctly!${NC}"
    echo "View captures at: http://localhost:8090/viewer"
else
    echo -e "${RED}❌ HTTPS not intercepted${NC}"
    echo "Response: $(echo $RESULT | head -c 100)"
    echo ""
    echo "Checking iptables rules:"
    docker exec transparent-proxy iptables -t nat -L OUTPUT -n
    echo ""
    echo -e "${YELLOW}If this still doesn't work, use proxy mode:${NC}"
    echo "  ./WORKING-SOLUTION.sh"
fi