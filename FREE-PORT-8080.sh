#!/bin/bash
# FREE-PORT-8080.sh - Find and stop whatever is using port 8080

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FREEING PORT 8080${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check what's using port 8080
echo -e "${YELLOW}What's using port 8080:${NC}"
lsof -i :8080 2>/dev/null || echo "Nothing found with lsof"

echo ""
echo -e "${YELLOW}Checking Docker containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 8080 || echo "No Docker containers using 8080"

echo ""
echo -e "${YELLOW}Checking all processes:${NC}"
netstat -tlnp 2>/dev/null | grep :8080 || ss -tlnp | grep :8080 || echo "No process found"

echo ""
echo -e "${BLUE}Attempting to free port 8080...${NC}"

# Try to stop Docker containers using 8080
echo -e "${YELLOW}Stopping Docker containers on port 8080...${NC}"
for container in $(docker ps --format "{{.Names}}" --filter "publish=8080"); do
    echo "Stopping container: $container"
    docker stop $container
    docker rm $container
done

# Try to kill processes using port 8080
echo -e "${YELLOW}Killing processes on port 8080...${NC}"
if lsof -ti:8080 > /dev/null 2>&1; then
    echo "Found process IDs: $(lsof -ti:8080)"
    echo "Killing them..."
    lsof -ti:8080 | xargs kill -9 2>/dev/null || {
        echo -e "${RED}Cannot kill process (may need sudo)${NC}"
        echo "Try: sudo lsof -ti:8080 | xargs kill -9"
    }
else
    echo "No processes to kill"
fi

echo ""
echo -e "${YELLOW}Final check:${NC}"
if lsof -i :8080 2>/dev/null | grep -q LISTEN; then
    echo -e "${RED}❌ Port 8080 is STILL in use${NC}"
    echo ""
    echo "The process using it:"
    lsof -i :8080
    echo ""
    echo "You may need to:"
    echo "1. Run with sudo: sudo ./FREE-PORT-8080.sh"
    echo "2. Or use alternative ports: ./CAPTURE-ALT-PORTS.sh"
else
    echo -e "${GREEN}✅ Port 8080 is now FREE!${NC}"
    echo ""
    echo "You can now run the capture scripts on port 8080"
fi