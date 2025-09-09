#!/bin/bash
# FIX 3: NETWORK NAMESPACE SHARING
# Run your app sharing the proxy's network - forces ALL traffic through proxy

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 3: NETWORK NAMESPACE SHARING${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ Forces ALL traffic through proxy"
echo "  ✓ No code changes needed"
echo "  ✓ Works even if app ignores proxy settings"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ Apps share same network (port conflicts possible)"
echo "  ✗ More complex networking"
echo ""

# Clean up
docker stop go-proxy-transparent app 2>/dev/null || true
docker rm -f go-proxy-transparent app 2>/dev/null || true

# Start proxy with transparent iptables
echo -e "${YELLOW}Starting proxy with iptables rules...${NC}"
docker run -d \
    --name go-proxy-transparent \
    --privileged \
    --cap-add NET_ADMIN \
    -p 8084:8084 \
    -p 8080:8080 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-3-transparent-proxy \
    sh -c '
        # Set up transparent proxy with iptables
        iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
        iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
        
        # Start mitmproxy
        mkdir -p ~/.mitmproxy /captured
        mitmdump --mode transparent --listen-port 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    '

sleep 5

# Start viewer
docker run -d \
    --name viewer \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-server.js:/app/viewer-server.js:ro \
    -e PORT=8090 \
    -e CAPTURED_DIR=/app/captured \
    proxy-3-viewer 2>/dev/null || true

echo -e "${GREEN}✅ Proxy ready with network sharing${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}NO CODE CHANGES NEEDED!${NC}"
echo ""
echo "Run your app sharing the proxy's network:"
echo -e "${GREEN}docker run \\
    --network container:go-proxy-transparent \\
    -v \$(pwd):/app \\
    -w /app \\
    golang:latest \\
    go run your-app.go${NC}"
echo ""
echo "Or if using docker-compose, add to your app service:"
echo -e "${GREEN}network_mode: \"container:go-proxy-transparent\"${NC}"
echo ""
echo "ALL network traffic will be forced through the proxy!"
echo ""
echo "View captures at: http://localhost:8090/viewer"
echo "Check logs: docker logs go-proxy-transparent"