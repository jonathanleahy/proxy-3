#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   TRANSPARENT PROXY CONNECTION TEST${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check if containers are running
echo -e "${YELLOW}1. Checking container status...${NC}"
CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "transparent-proxy|app" | wc -l)
if [ "$CONTAINERS" -eq "2" ]; then
    echo -e "${GREEN}✓ Both containers are running${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "transparent-proxy|app"
else
    echo -e "${RED}✗ Containers not running properly${NC}"
    echo "Run: ./transparent-capture.sh start"
    exit 1
fi
echo ""

# Step 2: Stop any existing server
echo -e "${YELLOW}2. Stopping any existing server...${NC}"
docker compose -f docker-compose-transparent.yml exec app pkill main 2>/dev/null || true
docker compose -f docker-compose-transparent.yml exec app pkill test-server 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Cleaned up${NC}"
echo ""

# Step 3: Start test server
echo -e "${YELLOW}3. Starting test server inside container...${NC}"
docker compose -f docker-compose-transparent.yml exec -d app sh -c "cd /proxy && ./test-server > /proxy/test.log 2>&1"
echo "Waiting for server to start..."
sleep 3

# Step 4: Test from inside the container
echo -e "${YELLOW}4. Testing connection from INSIDE container...${NC}"
docker compose -f docker-compose-transparent.yml exec app sh -c "curl -s -w '\nHTTP Status: %{http_code}\n' http://localhost:8080/test || echo 'Failed to connect from inside container'"
echo ""

# Step 5: Test from host
echo -e "${YELLOW}5. Testing connection from HOST...${NC}"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" http://localhost:8080/test 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Successfully connected from host!${NC}"
    echo "$RESPONSE" | grep -v "HTTP_STATUS:"
else
    echo -e "${RED}✗ Failed to connect from host${NC}"
    echo "Response: $RESPONSE"
fi
echo ""

# Step 6: Check logs
echo -e "${YELLOW}6. Server logs:${NC}"
docker compose -f docker-compose-transparent.yml exec app sh -c "tail -10 /proxy/test.log 2>/dev/null || echo 'No logs available'"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test complete!${NC}"
echo -e "${BLUE}========================================${NC}"
