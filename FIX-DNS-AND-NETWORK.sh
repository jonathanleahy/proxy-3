#!/bin/bash
# Fix DNS and network sharing issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing DNS and Network Issues${NC}"
echo "============================================"
echo "Problems detected:"
echo "1. App container has no network namespace"
echo "2. DNS resolution failing in app container"
echo ""

# Complete cleanup
echo -e "${YELLOW}Complete cleanup...${NC}"
docker compose -f docker-compose-universal.yml down -v 2>/dev/null || true
docker compose -f docker-compose-final.yml down -v 2>/dev/null || true
docker compose -f docker-compose-simple-share.yml down -v 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true
docker network prune -f
docker volume prune -f

echo -e "\n${YELLOW}Trying simplified network setup...${NC}"

# Create a custom network first
docker network create proxy-network 2>/dev/null || true

# Start containers manually with proper network setup
echo -e "\n${YELLOW}Starting proxy container...${NC}"
docker run -d \
    --name transparent-proxy \
    --network proxy-network \
    --privileged \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    -v proxy-certs:/certs \
    -p 8080:8080 \
    -p 8084:8084 \
    proxy-3-transparent-proxy

sleep 5

# Verify proxy started
if ! docker ps | grep -q transparent-proxy; then
    echo -e "${RED}❌ Proxy failed to start${NC}"
    docker logs transparent-proxy --tail 20
    exit 1
fi

echo -e "${GREEN}✅ Proxy started${NC}"

# Test DNS from proxy container
echo -e "\n${YELLOW}Testing DNS in proxy container...${NC}"
docker exec transparent-proxy nslookup google.com >/dev/null 2>&1 && echo -e "${GREEN}✅ DNS working in proxy${NC}" || echo -e "${RED}❌ DNS failed in proxy${NC}"

# Start app container sharing proxy's network
echo -e "\n${YELLOW}Starting app container with shared network stack...${NC}"
docker run -d \
    --name app \
    --network container:transparent-proxy \
    -v $(pwd):/proxy \
    -v proxy-certs:/certs:ro \
    -w /proxy \
    proxy-3-app \
    sh -c "
        echo 'Testing DNS...'
        nslookup google.com || echo 'DNS not working'
        echo 'App container ready'
        tail -f /dev/null
    "

sleep 3

# Check if network sharing worked
echo -e "\n${YELLOW}Verifying network configuration...${NC}"
PROXY_IP=$(docker exec transparent-proxy hostname -i 2>/dev/null || echo "none")
APP_IP=$(docker exec app hostname -i 2>/dev/null || echo "none")

echo "Proxy IP: $PROXY_IP"
echo "App IP: $APP_IP"

if [ "$PROXY_IP" = "$APP_IP" ]; then
    echo -e "${GREEN}✅ Network stack is shared${NC}"
else
    echo -e "${YELLOW}⚠️  IPs don't match but checking DNS...${NC}"
fi

# Test DNS from app
echo -e "\n${YELLOW}Testing DNS resolution in app container...${NC}"
DNS_TEST=$(docker exec app nslookup jsonplaceholder.typicode.com 2>&1)
if echo "$DNS_TEST" | grep -q "Address"; then
    echo -e "${GREEN}✅ DNS working in app container${NC}"
else
    echo -e "${RED}❌ DNS still not working${NC}"
    echo "$DNS_TEST"
    
    echo -e "\n${YELLOW}Trying with explicit DNS...${NC}"
    docker exec app sh -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    docker exec app nslookup jsonplaceholder.typicode.com
fi

# Start viewer separately
echo -e "\n${YELLOW}Starting viewer...${NC}"
docker run -d \
    --name mock-viewer \
    --network proxy-network \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-history.html:/app/viewer-history.html:ro \
    -p 8090:8090 \
    -e PORT=8090 \
    proxy-3-viewer

# Start the application
echo -e "\n${YELLOW}Starting application...${NC}"
docker exec -u 1000 -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null || \
docker exec -d app sh -c "cd /proxy/example-app && go run main.go" 2>/dev/null
sleep 5

# Final test
echo -e "\n${YELLOW}Testing HTTPS interception...${NC}"
RESPONSE=$(curl -s -m 10 http://localhost:8080/users 2>/dev/null)
if echo "$RESPONSE" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ SUCCESS! HTTPS interception working!${NC}"
    echo "View captures at: http://localhost:8090/viewer"
else
    echo -e "${RED}❌ Still not working${NC}"
    echo "Response: $(echo $RESPONSE | head -c 100)"
    
    echo -e "\n${YELLOW}System status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    
    echo -e "\n${RED}This appears to be a fundamental Docker networking issue on this machine.${NC}"
    echo ""
    echo -e "${YELLOW}SOLUTION: Use proxy mode which doesn't require network sharing:${NC}"
    echo -e "${GREEN}./WORKING-SOLUTION.sh${NC}"
    echo ""
    echo "Proxy mode will work because each container has its own network."
fi