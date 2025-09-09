#!/bin/bash
# Debug why containers aren't running

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DEBUGGING CAPTURE CONTAINERS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}1. Checking running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${YELLOW}2. Checking stopped containers:${NC}"
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${YELLOW}3. Checking container logs:${NC}"
for container in mitm-capture app-captured app-sidecar app-transparent transparent-proxy; do
    if docker ps -a | grep -q $container; then
        echo -e "${BLUE}--- Logs for $container ---${NC}"
        docker logs --tail 20 $container 2>&1 | head -20
        echo ""
    fi
done

echo -e "${YELLOW}4. Checking if images exist:${NC}"
docker images | grep -E "mitmproxy|golang|alpine|sidecar|transparent" || echo "No relevant images found"
echo ""

echo -e "${YELLOW}5. Testing basic Docker:${NC}"
docker run --rm alpine:latest echo "Docker works!" || echo -e "${RED}Docker basic test failed${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  QUICK FIX SUGGESTIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

if ! docker ps -a | grep -q app-captured; then
    echo -e "${RED}app-captured container doesn't exist${NC}"
    echo "Try running: ./CAPTURE-HTTPS-NO-ENV.sh"
elif docker ps -a | grep "Exited" | grep -q app-captured; then
    echo -e "${RED}app-captured container exited${NC}"
    echo "Check the error with: docker logs app-captured"
fi

echo ""
echo -e "${YELLOW}To clean up and try again:${NC}"
echo "./CLEANUP-ALL.sh"
echo "./CAPTURE-HTTPS-NO-ENV.sh"