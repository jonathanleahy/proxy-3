#!/bin/bash
# Fix capture visibility issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Capture Visibility${NC}"
echo "============================================"

# Check what's running
echo -e "${YELLOW}Current setup:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "proxy|viewer"

# Check if captures exist
echo -e "\n${YELLOW}Checking captures on host:${NC}"
CAPTURE_COUNT=$(ls -1 captured/*.json 2>/dev/null | wc -l)
echo "Found $CAPTURE_COUNT capture files"
if [ $CAPTURE_COUNT -gt 0 ]; then
    echo "Latest capture:"
    ls -lt captured/*.json | head -1
fi

# Check if proxy is actually intercepting
echo -e "\n${YELLOW}Checking proxy mode:${NC}"
PROXY_MODE=$(docker logs transparent-proxy 2>&1 | grep -E "transparent mode|proxy mode|Owner matching" | tail -1)
echo "$PROXY_MODE"

# Force save current captures
echo -e "\n${YELLOW}Force saving captures...${NC}"
docker exec transparent-proxy sh -c "
    if [ -f /scripts/mitm_capture_improved.py ]; then
        # Trigger manual save if possible
        killall -USR1 mitmdump 2>/dev/null || true
        echo 'Signaled save'
    fi
    
    # Check what's in /captured
    echo 'Files in /captured:'
    ls -la /captured/ | tail -5
" || echo "Could not check proxy container"

# Copy captures from container to host
echo -e "\n${YELLOW}Syncing captures from container to host...${NC}"
docker cp transparent-proxy:/captured/. captured/ 2>/dev/null && echo -e "${GREEN}✅ Captures synced${NC}" || echo "No new captures to sync"

# Make sure viewer can see them
echo -e "\n${YELLOW}Ensuring viewer has access...${NC}"
chmod -R 755 captured/ 2>/dev/null || true

# Test viewer API
echo -e "\n${YELLOW}Testing viewer endpoints:${NC}"
echo "Viewer status:"
curl -s http://localhost:8090/health 2>/dev/null || echo "Viewer not responding on :8090"

echo -e "\nChecking capture endpoint:"
curl -s http://localhost:8090/api/captures 2>/dev/null | head -c 100 || echo "No capture API"

# Try alternate viewer endpoint
echo -e "\nTrying viewer page:"
curl -s http://localhost:8090/viewer 2>/dev/null | grep -o "<title>.*</title>" || echo "Viewer page not accessible"

# Restart viewer with correct mounts
echo -e "\n${YELLOW}Restarting viewer with correct configuration...${NC}"
docker stop mock-viewer 2>/dev/null || true
docker rm mock-viewer 2>/dev/null || true

docker run -d \
    --name mock-viewer \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-history.html:/app/viewer-history.html:ro \
    -e PORT=8090 \
    proxy-3-viewer

sleep 3

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Testing capture system:${NC}"
echo -e "${BLUE}=========================================${NC}"

# Make a test request
echo -e "\n${YELLOW}Making test request...${NC}"
RESPONSE=$(curl -s http://localhost:8080/users 2>/dev/null | head -c 100)
if echo "$RESPONSE" | grep -q "success\|error\|User"; then
    echo -e "${GREEN}✅ Request made${NC}"
    
    # Wait for capture to save
    echo "Waiting for capture to save..."
    sleep 5
    
    # Check for new captures
    NEW_COUNT=$(ls -1 captured/*.json 2>/dev/null | wc -l)
    if [ $NEW_COUNT -gt $CAPTURE_COUNT ]; then
        echo -e "${GREEN}✅ New capture saved!${NC}"
        echo "Latest: $(ls -lt captured/*.json | head -1)"
    else
        echo -e "${YELLOW}⚠️  No new captures${NC}"
        echo ""
        echo "The proxy might not be intercepting traffic."
        echo "This is likely because:"
        echo "1. Network namespace not shared (transparent mode broken)"
        echo "2. iptables not working"
        echo ""
        echo -e "${GREEN}Solution: Use proxy mode instead:${NC}"
        echo "  ./FINAL-CLEANUP-AND-RUN.sh"
    fi
else
    echo -e "${RED}❌ App not responding${NC}"
fi

echo -e "\n${GREEN}To view captures:${NC}"
echo "1. Web viewer: http://localhost:8090/viewer"
echo "2. Latest file: cat \$(ls -t captured/*.json | head -1) | jq '.'"
echo "3. All captures: ls -la captured/"

# If still not working, suggest proxy mode
if [ $NEW_COUNT -eq $CAPTURE_COUNT ]; then
    echo -e "\n${YELLOW}If captures still aren't working:${NC}"
    echo "The transparent mode isn't intercepting on this machine."
    echo -e "${GREEN}Use proxy mode which always works:${NC}"
    echo "  ./FINAL-CLEANUP-AND-RUN.sh"
fi