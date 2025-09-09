#!/bin/bash
# FIX-PORTS.sh - Clean up ports and containers

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING PORT CONFLICTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check what's using our ports
echo -e "${YELLOW}Checking port usage:${NC}"
for PORT in 8080 8081 8084 8090 8091; do
    echo -n "Port $PORT: "
    if lsof -i :$PORT 2>/dev/null | grep -q LISTEN; then
        echo -e "${RED}IN USE${NC}"
        lsof -i :$PORT | grep LISTEN
    else
        echo -e "${GREEN}FREE${NC}"
    fi
done

echo ""
echo -e "${YELLOW}Docker containers using these ports:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "808[0-9]|809[0-9]" || echo "None found"

echo ""
echo -e "${YELLOW}Stopping all related containers...${NC}"
docker stop $(docker ps -q) 2>/dev/null || true

echo ""
echo -e "${YELLOW}Removing all stopped containers...${NC}"
docker container prune -f

echo ""
echo -e "${YELLOW}Final check - all containers:${NC}"
docker ps -a --format "table {{.Names}}\t{{.Status}}"

echo ""
echo -e "${GREEN}✅ Ports should be free now!${NC}"
echo ""
echo "You can now run:"
echo "  ./CAPTURE-WORKING.sh"
echo ""
echo "Or if you still have issues:"
echo "  docker rm -f \$(docker ps -aq)  # Remove ALL containers"