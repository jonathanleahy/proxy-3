#!/bin/bash
# USE-YOUR-APP.sh - Keep your app on 8080, run proxy on different port

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PROXY FOR YOUR EXISTING APP ON 8080${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if something is on 8080 (presumably your app)
echo -e "${YELLOW}Checking port 8080...${NC}"
if lsof -i :8080 2>/dev/null | grep -q LISTEN; then
    echo -e "${GREEN}✅ Found something on port 8080 (your app?)${NC}"
    echo "Process using it:"
    lsof -i :8080 | grep LISTEN
    echo ""
    
    # Test if it responds
    if curl -s -m 2 http://localhost:8080 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Your app is responding${NC}"
        echo "Sample response:"
        curl -s http://localhost:8080 2>/dev/null | head -5
    else
        echo -e "${YELLOW}⚠️  Port 8080 is in use but not responding to HTTP${NC}"
    fi
else
    echo -e "${RED}Nothing on port 8080${NC}"
    echo "Start your app first, then run this script"
    exit 1
fi

# Clean up old proxy containers
docker stop proxy proxy-capture 2>/dev/null || true
docker rm proxy proxy-capture 2>/dev/null || true

# Find a free port for the proxy
PROXY_PORT=9084
while lsof -i :$PROXY_PORT 2>/dev/null | grep -q LISTEN; do
    echo "Port $PROXY_PORT is busy, trying next..."
    PROXY_PORT=$((PROXY_PORT + 1))
done

echo ""
echo -e "${YELLOW}Starting proxy on port $PROXY_PORT...${NC}"

# Start mitmproxy
docker run -d \
    --name proxy \
    -p $PROXY_PORT:8080 \
    -v $(pwd)/captured:/captured \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080 --save-stream-file /captured/stream.mitm

sleep 3

if docker ps | grep -q " proxy"; then
    echo -e "${GREEN}✅ Proxy started on port $PROXY_PORT${NC}"
else
    echo -e "${RED}❌ Proxy failed to start${NC}"
    docker logs proxy
    exit 1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}SETUP COMPLETE!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your setup:"
echo "  • Your app: http://localhost:8080 (unchanged)"
echo "  • Proxy: localhost:$PROXY_PORT"
echo ""
echo -e "${YELLOW}To capture HTTPS traffic from your app:${NC}"
echo ""
echo "1. If your app uses environment variables:"
echo "   Restart it with:"
echo "   ${GREEN}HTTP_PROXY=http://localhost:$PROXY_PORT HTTPS_PROXY=http://localhost:$PROXY_PORT your-app${NC}"
echo ""
echo "2. Or test the proxy with curl:"
echo "   ${GREEN}curl -x http://localhost:$PROXY_PORT https://api.github.com${NC}"
echo ""
echo "3. View captured traffic:"
echo "   ${GREEN}docker logs proxy${NC}"
echo ""
echo "4. Captured files:"
echo "   ${GREEN}ls -la captured/${NC}"