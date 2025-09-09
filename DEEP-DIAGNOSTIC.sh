#!/bin/bash
# Deep diagnostic for HTTPS interception issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔍 Deep Diagnostic for HTTPS Interception${NC}"
echo "============================================"

# 1. Check network namespace sharing
echo -e "\n${YELLOW}1. Checking network namespace sharing...${NC}"
PROXY_NS=$(docker inspect transparent-proxy -f '{{.NetworkSettings.SandboxKey}}')
APP_NS=$(docker inspect app -f '{{.NetworkSettings.SandboxKey}}')
if [ "$PROXY_NS" = "$APP_NS" ]; then
    echo -e "${GREEN}✅ App and proxy share network namespace${NC}"
else
    echo -e "${RED}❌ Network namespaces don't match!${NC}"
    echo "Proxy: $PROXY_NS"
    echo "App: $APP_NS"
fi

# 2. Check if app is actually running
echo -e "\n${YELLOW}2. Checking app process...${NC}"
docker exec app ps aux | grep -E "go|main" | grep -v grep || echo "No app running"

# 3. Check actual network traffic path
echo -e "\n${YELLOW}3. Testing network path from app container...${NC}"
echo "Testing direct HTTPS from app container:"
docker exec -u 1000 app sh -c "cd /proxy/example-app && wget -O- -q https://jsonplaceholder.typicode.com/users 2>&1 | head -c 100" && echo "..." || echo "Failed"

# 4. Check iptables rules in detail
echo -e "\n${YELLOW}4. Detailed iptables check...${NC}"
echo "NAT OUTPUT chain:"
docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v --line-numbers

# 5. Check if mitmproxy is actually listening
echo -e "\n${YELLOW}5. Checking mitmproxy listener...${NC}"
docker exec transparent-proxy netstat -tlnp 2>/dev/null | grep 8084 || echo "Port 8084 not listening"

# 6. Test redirection manually
echo -e "\n${YELLOW}6. Testing manual redirection...${NC}"
echo "Creating test connection to port 443 as UID 1000:"
docker exec -u 1000 transparent-proxy sh -c "timeout 2 nc -zv jsonplaceholder.typicode.com 443 2>&1" || true

# 7. Check packet counts after test
echo -e "\n${YELLOW}7. Checking packet counts...${NC}"
docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v | grep REDIRECT

# 8. Check for conflicting rules
echo -e "\n${YELLOW}8. Checking for conflicting rules...${NC}"
echo "PREROUTING chain:"
docker exec transparent-proxy iptables -t nat -L PREROUTING -n | head -10

# 9. Test with curl from inside container
echo -e "\n${YELLOW}9. Testing with different user IDs...${NC}"
echo "As root (should NOT be intercepted):"
docker exec transparent-proxy sh -c "curl -s -m 2 https://httpbin.org/ip 2>&1 | head -c 50" || echo "Timeout/failed"

echo -e "\nAs UID 1000 (SHOULD be intercepted):"
docker exec -u 1000 transparent-proxy sh -c "curl -s -m 2 https://httpbin.org/ip 2>&1 | head -c 50" || echo "Timeout/failed"

# 10. Check mitmproxy logs
echo -e "\n${YELLOW}10. Recent mitmproxy output...${NC}"
docker logs transparent-proxy --tail 20 2>&1 | grep -v "^$"

# Summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Diagnostic Summary:${NC}"
echo -e "${BLUE}=========================================${NC}"

# Final test from app
echo -e "\n${YELLOW}Final test: Making request from app...${NC}"
RESPONSE=$(curl -s -m 5 http://localhost:8080/users 2>/dev/null | head -c 200)
if echo "$RESPONSE" | grep -q "success"; then
    echo -e "${GREEN}✅ Working now!${NC}"
else
    echo -e "${RED}❌ Still not working${NC}"
    echo "Response: $RESPONSE"
    echo ""
    echo -e "${YELLOW}Likely issues:${NC}"
    echo "1. Traffic not going through OUTPUT chain (check namespace)"
    echo "2. Mitmproxy not listening on 8084"
    echo "3. Different iptables implementation on this system"
    echo "4. Certificate trust issues"
fi