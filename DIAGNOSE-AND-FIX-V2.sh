#!/bin/bash
# Comprehensive diagnostic and fix script - Version 2 with timeout handling

# Don't use set -e to prevent script from stopping on errors
# set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔍 Diagnostic and Fix Tool V2${NC}"
echo "============================================"

# Step 1: Check what's running
echo -e "\n${YELLOW}Step 1: Checking current state...${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "proxy|app|viewer" || echo "No containers running"

# Step 2: Check if app is running and as what user
echo -e "\n${YELLOW}Step 2: Checking app process...${NC}"
APP_INFO=$(timeout 5 docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep" 2>/dev/null || echo "")
if [ ! -z "$APP_INFO" ]; then
    echo "Found app process:"
    echo "$APP_INFO"
    USER_ID=$(echo "$APP_INFO" | awk '{print $1}' | head -1)
    PID=$(echo "$APP_INFO" | awk '{print $2}' | head -1)
    
    if [ "$USER_ID" = "root" ] || [ "$USER_ID" = "0" ]; then
        echo -e "${RED}❌ App running as root - HTTPS won't be intercepted!${NC}"
        echo "Force killing root process..."
        timeout 2 docker exec app sh -c "kill -9 $PID" 2>/dev/null || true
        sleep 1
    elif [ "$USER_ID" = "1000" ] || [ "$USER_ID" = "appuser" ]; then
        echo -e "${GREEN}✅ App running as correct user${NC}"
        echo "Stopping it to restart fresh..."
        timeout 2 docker exec app sh -c "kill -9 $PID" 2>/dev/null || true
        sleep 1
    fi
else
    echo "No app process found"
fi

# Step 3: Check certificate
echo -e "\n${YELLOW}Step 3: Checking certificate...${NC}"
if timeout 5 docker exec app ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate exists${NC}"
else
    echo -e "${RED}❌ Certificate missing or container not responding${NC}"
fi

# Step 4: Check iptables
echo -e "\n${YELLOW}Step 4: Checking iptables rules...${NC}"
IPTABLES_CHECK=$(timeout 5 docker exec transparent-proxy iptables -t nat -L OUTPUT -n 2>&1 | grep -c "REDIRECT" || echo "0")
if [ "$IPTABLES_CHECK" -gt 0 ]; then
    echo -e "${GREEN}✅ iptables rules configured ($IPTABLES_CHECK rules)${NC}"
else
    echo -e "${YELLOW}⚠️  No iptables redirect rules found${NC}"
fi

# Step 5: Force cleanup (with timeouts to prevent hanging)
echo -e "\n${YELLOW}Step 5: Force cleaning up processes...${NC}"
echo "Killing any Go processes..."
timeout 2 docker exec app sh -c "killall -9 go 2>/dev/null" || true
timeout 2 docker exec app sh -c "killall -9 main 2>/dev/null" || true
echo "Cleanup complete"
sleep 2

# Step 6: Start app correctly
echo -e "\n${YELLOW}Step 6: Starting app as UID 1000...${NC}"
# Start in background without waiting
timeout 10 docker exec -u 1000 app sh -c '
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
    export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    cd /proxy/example-app 
    nohup go run main.go > /tmp/app.log 2>&1 &
    echo "Started app process"
' || echo "Note: App start command sent"

echo "Waiting for app to initialize..."
sleep 8

# Step 7: Verify app is running
echo -e "\n${YELLOW}Step 7: Verifying app status...${NC}"
APP_CHECK=$(timeout 5 docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep | awk '{print \$1}'" 2>/dev/null | head -1)
if [ "$APP_CHECK" = "1000" ] || [ "$APP_CHECK" = "appuser" ]; then
    echo -e "${GREEN}✅ App running as UID 1000${NC}"
else
    echo -e "${YELLOW}⚠️  App may not be running. Checking logs...${NC}"
    timeout 5 docker exec app sh -c "tail -20 /tmp/app.log 2>/dev/null" || echo "No logs available"
fi

# Step 8: Test endpoints
echo -e "\n${YELLOW}Step 8: Testing endpoints...${NC}"
echo "Testing health..."
HEALTH=$(timeout 5 curl -s http://localhost:8080/health 2>/dev/null || echo "timeout")
if echo "$HEALTH" | grep -q "healthy"; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${RED}❌ Health check failed: $HEALTH${NC}"
fi

echo -e "\nTesting HTTPS interception..."
USERS=$(timeout 10 curl -s http://localhost:8080/users 2>/dev/null || echo "timeout")
if echo "$USERS" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS interception WORKING!${NC}"
    echo ""
    echo "🎉 System is working correctly!"
    echo "View captures at: http://localhost:8090/viewer"
elif echo "$USERS" | grep -q "Error fetching"; then
    echo -e "${RED}❌ App running but HTTPS not being intercepted${NC}"
    echo ""
    echo "This machine may not support transparent iptables mode."
    echo -e "${YELLOW}Alternative: Use proxy mode instead:${NC}"
    echo "  ./WORKING-SOLUTION.sh"
else
    echo -e "${RED}❌ No response from app${NC}"
    echo "Response: $USERS"
fi

# Step 9: Summary and recommendations
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Summary:${NC}"
echo -e "${BLUE}=========================================${NC}"

if echo "$USERS" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ System working - HTTPS being captured${NC}"
elif [ "$IPTABLES_CHECK" -eq 0 ]; then
    echo -e "${YELLOW}This system doesn't support transparent mode.${NC}"
    echo "Use: ./WORKING-SOLUTION.sh (proxy mode)"
else
    echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
    echo "1. Try proxy mode: ./WORKING-SOLUTION.sh"
    echo "2. Check Docker logs: docker logs transparent-proxy"
    echo "3. Restart everything: docker compose -f docker-compose-final.yml down && ./TRY-THIS-IPTABLES-FIX.sh"
fi