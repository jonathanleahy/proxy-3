#!/bin/bash
# Test script to verify proxy capture is working

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🧪 Testing Transparent Proxy Capture System${NC}"
echo "============================================"

# Function to check app user
check_app_user() {
    local user=$(docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep | awk '{print \$1}'" 2>/dev/null | head -1)
    echo "$user"
}

# Step 1: Ensure app is running as appuser
echo -e "\n${YELLOW}Step 1: Checking app user...${NC}"
APP_USER=$(check_app_user)

if [ "$APP_USER" != "appuser" ]; then
    echo -e "${RED}❌ App running as $APP_USER, restarting as appuser...${NC}"
    
    # Kill existing process
    docker exec app sh -c "pkill -f 'go run' 2>/dev/null || true"
    sleep 1
    
    # Start as appuser
    docker exec -d app su-exec appuser sh -c "cd /proxy/example-app && go run main.go"
    sleep 3
    
    # Verify
    APP_USER=$(check_app_user)
    if [ "$APP_USER" = "appuser" ]; then
        echo -e "${GREEN}✅ App now running as appuser${NC}"
    else
        echo -e "${RED}❌ Failed to start as appuser${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ App already running as appuser${NC}"
fi

# Step 2: Clear iptables counters to see new traffic
echo -e "\n${YELLOW}Step 2: Resetting iptables counters...${NC}"
docker exec transparent-proxy iptables -t nat -Z OUTPUT 2>/dev/null || true
echo -e "${GREEN}✅ Counters reset${NC}"

# Step 3: Get initial capture count
echo -e "\n${YELLOW}Step 3: Checking current captures...${NC}"
INITIAL_COUNT=$(ls -1 captured/*.json 2>/dev/null | wc -l)
echo "Initial capture files: $INITIAL_COUNT"

# Step 4: Make test requests
echo -e "\n${YELLOW}Step 4: Making test requests...${NC}"

echo "Testing health endpoint..."
curl -s http://localhost:8080/health | grep -q "healthy" && echo -e "${GREEN}✅ Health check passed${NC}" || echo -e "${RED}❌ Health check failed${NC}"

echo "Testing users endpoint (HTTPS call)..."
USERS_RESULT=$(curl -s http://localhost:8080/users)
if echo "$USERS_RESULT" | grep -q "success"; then
    echo -e "${GREEN}✅ Users fetched successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Users endpoint returned: $(echo $USERS_RESULT | jq -r '.message' 2>/dev/null)${NC}"
fi

echo "Testing posts endpoint (HTTPS call)..."
POSTS_RESULT=$(curl -s http://localhost:8080/posts)
if echo "$POSTS_RESULT" | grep -q "success"; then
    echo -e "${GREEN}✅ Posts fetched successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Posts endpoint returned: $(echo $POSTS_RESULT | jq -r '.message' 2>/dev/null)${NC}"
fi

# Step 5: Check iptables counters
echo -e "\n${YELLOW}Step 5: Checking traffic interception...${NC}"
PACKETS=$(docker exec transparent-proxy iptables -t nat -L OUTPUT -v -n 2>/dev/null | grep "443.*REDIRECT" | awk '{print $1}')
if [ -n "$PACKETS" ] && [ "$PACKETS" != "0" ]; then
    echo -e "${GREEN}✅ HTTPS traffic intercepted: $PACKETS packets${NC}"
else
    echo -e "${RED}❌ No HTTPS traffic intercepted!${NC}"
    echo "This means traffic is NOT going through mitmproxy"
fi

# Step 6: Check for new captures
echo -e "\n${YELLOW}Step 6: Waiting for captures to save (30s)...${NC}"
sleep 30

FINAL_COUNT=$(ls -1 captured/*.json 2>/dev/null | wc -l)
NEW_CAPTURES=$((FINAL_COUNT - INITIAL_COUNT))

if [ $NEW_CAPTURES -gt 0 ]; then
    echo -e "${GREEN}✅ New captures saved: $NEW_CAPTURES files${NC}"
    echo "Latest capture:"
    ls -lt captured/*.json | head -1
else
    echo -e "${RED}❌ No new captures saved${NC}"
    echo "Checking mitmproxy logs for errors..."
    docker logs transparent-proxy --tail 20 2>&1 | grep -E "Error|error|failed" || echo "No errors in logs"
fi

# Step 7: Summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Test Summary:${NC}"
echo -e "${BLUE}=========================================${NC}"

if [ "$APP_USER" = "appuser" ] && [ "$PACKETS" != "0" ] && [ $NEW_CAPTURES -gt 0 ]; then
    echo -e "${GREEN}✅ SYSTEM WORKING CORRECTLY${NC}"
    echo "- App running as correct user (appuser)"
    echo "- Traffic being intercepted by mitmproxy"
    echo "- Captures being saved to disk"
else
    echo -e "${RED}❌ SYSTEM HAS ISSUES${NC}"
    [ "$APP_USER" != "appuser" ] && echo "- App not running as appuser"
    [ "$PACKETS" = "0" ] || [ -z "$PACKETS" ] && echo "- Traffic not being intercepted"
    [ $NEW_CAPTURES -eq 0 ] && echo "- Captures not being saved"
fi

echo -e "\n${YELLOW}To monitor the system continuously, run:${NC} ./monitor-proxy.sh"