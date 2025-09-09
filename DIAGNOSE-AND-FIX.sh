#!/bin/bash
# Comprehensive diagnostic and fix script for proxy issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔍 Diagnostic and Fix Tool${NC}"
echo "============================================"

# Step 1: Check what's running
echo -e "\n${YELLOW}Step 1: Checking current state...${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "proxy|app|viewer" || echo "No containers running"

# Step 2: Check if app is running and as what user
echo -e "\n${YELLOW}Step 2: Checking app process...${NC}"
APP_PID=$(docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep | awk '{print \$1,\$2}'" 2>/dev/null || echo "none")
if [ "$APP_PID" != "none" ] && [ ! -z "$APP_PID" ]; then
    echo "App is running: $APP_PID"
    USER_ID=$(echo $APP_PID | awk '{print $1}')
    PID=$(echo $APP_PID | awk '{print $2}')
    
    if [ "$USER_ID" = "root" ] || [ "$USER_ID" = "0" ]; then
        echo -e "${RED}❌ App running as root - HTTPS won't be intercepted!${NC}"
        echo "Killing root process..."
        docker exec app kill -9 $PID 2>/dev/null || true
        sleep 2
    elif [ "$USER_ID" = "1000" ] || [ "$USER_ID" = "appuser" ]; then
        echo -e "${GREEN}✅ App running as correct user${NC}"
    fi
else
    echo "App not running"
fi

# Step 3: Check certificate
echo -e "\n${YELLOW}Step 3: Checking certificate...${NC}"
if docker exec app ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate exists${NC}"
else
    echo -e "${RED}❌ Certificate missing${NC}"
    echo "Waiting for certificate..."
    sleep 5
fi

# Step 4: Check iptables
echo -e "\n${YELLOW}Step 4: Checking iptables rules...${NC}"
IPTABLES_CHECK=$(docker exec transparent-proxy iptables -t nat -L OUTPUT -n 2>&1 | grep -c "REDIRECT" || echo "0")
if [ "$IPTABLES_CHECK" -gt 0 ]; then
    echo -e "${GREEN}✅ iptables rules configured ($IPTABLES_CHECK rules)${NC}"
else
    echo -e "${RED}❌ No iptables rules${NC}"
    echo "This means transparent mode isn't working. Use proxy mode instead."
fi

# Step 5: Kill any existing app
echo -e "\n${YELLOW}Step 5: Cleaning up old processes...${NC}"
docker exec app sh -c "pkill -f 'go run' 2>/dev/null || true"
docker exec app sh -c "pkill -f main 2>/dev/null || true"
sleep 2

# Step 6: Start app correctly
echo -e "\n${YELLOW}Step 6: Starting app as UID 1000...${NC}"
docker exec -u 1000 app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
    export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    cd /proxy/example-app && nohup go run main.go > /tmp/app.log 2>&1 &
" || echo "Failed to start as UID 1000"

echo "Waiting for app to start..."
sleep 7

# Step 7: Test
echo -e "\n${YELLOW}Step 7: Testing...${NC}"
echo "Testing health endpoint..."
HEALTH=$(curl -s http://localhost:8080/health 2>/dev/null || echo "failed")
if echo "$HEALTH" | grep -q "healthy"; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${RED}❌ Health check failed${NC}"
    echo "Checking app logs..."
    docker exec app cat /tmp/app.log 2>/dev/null | tail -10 || echo "No logs"
fi

echo -e "\nTesting HTTPS interception..."
USERS=$(curl -s http://localhost:8080/users 2>/dev/null || echo "failed")
if echo "$USERS" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS interception WORKING!${NC}"
elif echo "$USERS" | grep -q "Error fetching"; then
    echo -e "${RED}❌ HTTPS not being intercepted${NC}"
    echo ""
    echo "Trying direct connection test..."
    docker exec -u 1000 app sh -c "cd /proxy/example-app && wget -O- https://jsonplaceholder.typicode.com/users 2>&1 | head -5"
    
    if [ "$IPTABLES_CHECK" -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}The system doesn't support transparent mode.${NC}"
        echo "Use proxy mode instead: ./WORKING-SOLUTION.sh"
    else
        echo ""
        echo -e "${YELLOW}Possible issues:${NC}"
        echo "1. Certificate not trusted"
        echo "2. iptables not intercepting UID 1000 traffic"
        echo "3. Network connectivity issues"
    fi
else
    echo -e "${RED}❌ App not responding${NC}"
fi

# Step 8: Summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Diagnostic Summary:${NC}"
echo -e "${BLUE}=========================================${NC}"

# Final check
FINAL_CHECK=$(docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep | awk '{print \$1}'" 2>/dev/null | head -1)
if [ "$FINAL_CHECK" = "1000" ] || [ "$FINAL_CHECK" = "appuser" ]; then
    echo -e "${GREEN}✅ App running as correct user (UID 1000)${NC}"
    
    if echo "$USERS" | grep -q "success\|Leanne Graham"; then
        echo -e "${GREEN}✅ HTTPS interception working${NC}"
        echo ""
        echo "System is working correctly!"
        echo "View captures at: http://localhost:8090/viewer"
    else
        echo -e "${YELLOW}⚠️  App running but HTTPS not intercepted${NC}"
        echo ""
        echo "Try proxy mode: ./WORKING-SOLUTION.sh"
    fi
else
    echo -e "${RED}❌ App not running correctly${NC}"
    echo ""
    echo "Manual fix:"
    echo "  docker exec -u 1000 -d app sh -c 'cd /proxy/example-app && go run main.go'"
fi