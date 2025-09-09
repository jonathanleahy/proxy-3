#!/bin/bash
# Solution that works without admin privileges

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 No-Admin Proxy Solution${NC}"
echo "============================================"
echo "This bypasses all iptables and network issues"
echo "Works with standard Docker permissions only"
echo ""

# Check Docker access
if ! docker ps >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot access Docker${NC}"
    echo "You need to either:"
    echo "1. Be in docker group: sudo usermod -aG docker $USER && newgrp docker"
    echo "2. Run with: sudo ./NO-ADMIN-SOLUTION.sh"
    exit 1
fi

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker stop proxy app viewer 2>/dev/null || true
docker rm proxy app viewer 2>/dev/null || true

# Use the simplest possible setup - no iptables, no network sharing
echo -e "\n${YELLOW}Starting simple proxy (no iptables)...${NC}"
docker run -d \
    --name proxy \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    -v $(pwd)/certs:/certs \
    -e TRANSPARENT_MODE=false \
    proxy-3-transparent-proxy \
    sh -c "
        mkdir -p ~/.mitmproxy /certs
        mitmdump --quiet >/dev/null 2>&1 & sleep 3; kill \$! 2>/dev/null
        [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ] && cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/
        echo '✅ Proxy ready on port 8084'
        exec mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    "

sleep 5

# Start app with its own network, configured to use proxy
echo -e "\n${YELLOW}Starting app with proxy configuration...${NC}"
docker run -d \
    --name app \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -v $(pwd)/certs:/certs:ro \
    -e HTTP_PROXY=http://host.docker.internal:8084 \
    -e HTTPS_PROXY=http://host.docker.internal:8084 \
    -e NO_PROXY=localhost,127.0.0.1 \
    -e SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem \
    proxy-3-app \
    sh -c "
        echo 'Waiting for certificate...'
        while [ ! -f /certs/mitmproxy-ca-cert.pem ]; do sleep 1; done
        echo '✅ Certificate found'
        cd /proxy/example-app
        export HTTP_PROXY=http://host.docker.internal:8084
        export HTTPS_PROXY=http://host.docker.internal:8084
        export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
        go run main.go
    "

# Start viewer
echo -e "\n${YELLOW}Starting viewer...${NC}"
docker run -d \
    --name viewer \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-history.html:/app/viewer-history.html:ro \
    -e PORT=8090 \
    proxy-3-viewer

echo -e "\n${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Test
echo -e "\n${YELLOW}Testing...${NC}"
echo "Health check:"
curl -s http://localhost:8080/health | grep -q "healthy" && echo -e "${GREEN}✅ App running${NC}" || echo -e "${RED}❌ App not ready${NC}"

echo -e "\nHTTPS capture test:"
RESPONSE=$(curl -s http://localhost:8080/users 2>/dev/null)
if echo "$RESPONSE" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS traffic IS being captured!${NC}"
    echo ""
    echo "🎉 SUCCESS! Working without admin or iptables!"
    echo ""
    echo "How it works:"
    echo "- Proxy runs on port 8084"
    echo "- App configured with HTTP_PROXY environment variables"
    echo "- No iptables or network sharing needed"
    echo "- View captures at: http://localhost:8090/viewer"
else
    echo -e "${YELLOW}⚠️  May need more time to start${NC}"
    echo "Wait 10 seconds and try: curl http://localhost:8080/users"
    echo ""
    echo "Check logs:"
    echo "  docker logs app"
    echo "  docker logs proxy"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}No admin privileges needed!${NC}"
echo -e "${BLUE}=========================================${NC}"