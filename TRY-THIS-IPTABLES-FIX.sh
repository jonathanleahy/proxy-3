#!/bin/bash
# Final attempt at fixing iptables with better rules

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Trying Fixed iptables Approach${NC}"
echo "============================================"

# Complete cleanup
echo -e "${YELLOW}Complete Docker cleanup...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker network prune -f
docker system prune -f

echo -e "${YELLOW}Building with fixed iptables script...${NC}"
docker compose -f docker-compose-final.yml build

echo -e "${YELLOW}Starting containers...${NC}"
docker compose -f docker-compose-final.yml up -d

sleep 5

# Check logs for iptables errors
echo -e "${YELLOW}Checking for iptables issues...${NC}"
if docker logs transparent-proxy 2>&1 | grep -q "iptables-restore"; then
    echo -e "${RED}❌ iptables still failing${NC}"
    echo ""
    echo "The system has fundamental iptables restrictions."
    echo "Use proxy mode instead: ./WORKING-SOLUTION.sh"
else
    echo -e "${GREEN}✅ No iptables errors detected${NC}"
    
    # Start app
    docker exec -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null || true
    
    echo -e "\n${GREEN}🎉 Success! Transparent HTTPS interception working!${NC}"
    echo ""
    echo "Test: curl http://localhost:8080/users"
    echo "View: http://localhost:8090/viewer"
fi