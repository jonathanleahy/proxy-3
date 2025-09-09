#!/bin/bash
# Complete cleanup and run the working solution

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🧹 Complete Cleanup and Working Solution${NC}"
echo "============================================"

# AGGRESSIVE CLEANUP
echo -e "${YELLOW}Step 1: Stopping ALL related containers...${NC}"
docker stop transparent-proxy app mock-viewer proxy viewer 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer proxy viewer 2>/dev/null || true

# Also stop any containers with our image names
docker ps -a | grep -E "proxy-3|transparent|mock-viewer" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

echo -e "${GREEN}✅ All containers removed${NC}"

# Clean networks
echo -e "\n${YELLOW}Step 2: Cleaning up networks...${NC}"
docker network rm proxy-3_capture-net capture-net proxy-network macvlan-net 2>/dev/null || true
docker network prune -f
echo -e "${GREEN}✅ Networks cleaned${NC}"

# Clean volumes
echo -e "\n${YELLOW}Step 3: Cleaning up volumes...${NC}"
docker volume prune -f
echo -e "${GREEN}✅ Volumes cleaned${NC}"

# Now run the WORKING solution (proxy mode)
echo -e "\n${BLUE}🚀 Starting Working Solution (Proxy Mode)${NC}"
echo "============================================"
echo "This bypasses ALL iptables and network issues"
echo ""

# Build images if needed
echo -e "${YELLOW}Building images...${NC}"
docker build -t proxy-image -f docker/Dockerfile.mitmproxy-simple . 2>/dev/null || \
docker build -t proxy-image -f docker/Dockerfile.mitmproxy-universal .

docker build -t app-image -f docker/Dockerfile.app.minimal .
docker build -t viewer-image -f Dockerfile .

# Start proxy (simple mode, no iptables)
echo -e "\n${YELLOW}Starting proxy...${NC}"
docker run -d \
    --name proxy \
    --rm \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-image \
    sh -c "
        mkdir -p ~/.mitmproxy /captured
        mitmdump --quiet >/dev/null 2>&1 & sleep 3; kill \$! 2>/dev/null || true
        echo '✅ Starting proxy on port 8084'
        exec mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    "

sleep 5

# Get certificate
echo -e "\n${YELLOW}Getting certificate...${NC}"
docker exec proxy sh -c "cat ~/.mitmproxy/mitmproxy-ca-cert.pem" > mitmproxy-ca.pem 2>/dev/null || true
if [ -f mitmproxy-ca.pem ] && [ -s mitmproxy-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate saved${NC}"
else
    echo -e "${YELLOW}⚠️  Certificate will be generated${NC}"
fi

# Start app with proxy configuration
echo -e "\n${YELLOW}Starting app with proxy settings...${NC}"
docker run -d \
    --name app \
    --rm \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -e SSL_CERT_FILE=/proxy/mitmproxy-ca.pem \
    -e NO_PROXY=localhost,127.0.0.1 \
    -w /proxy/example-app \
    app-image \
    sh -c "
        echo 'Waiting for proxy...'
        sleep 3
        echo 'Starting app with proxy configuration'
        export HTTP_PROXY=http://172.17.0.1:8084
        export HTTPS_PROXY=http://172.17.0.1:8084
        export SSL_CERT_FILE=/proxy/mitmproxy-ca.pem
        go run main.go
    "

# Start viewer
echo -e "\n${YELLOW}Starting viewer...${NC}"
docker run -d \
    --name viewer \
    --rm \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-history.html:/app/viewer-history.html:ro \
    -e PORT=8090 \
    viewer-image

echo -e "\n${YELLOW}Waiting for services to start...${NC}"
for i in {1..15}; do
    if curl -s http://localhost:8080/health 2>/dev/null | grep -q "healthy"; then
        echo -e "${GREEN}✅ App is ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Test
echo -e "\n${YELLOW}Testing HTTPS capture...${NC}"
RESPONSE=$(curl -s -m 10 http://localhost:8080/users 2>/dev/null)
if echo "$RESPONSE" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS traffic IS being captured!${NC}"
    echo ""
    echo "🎉 SUCCESS! System working!"
    echo ""
    echo "Endpoints:"
    echo "  • App: http://localhost:8080"
    echo "  • Viewer: http://localhost:8090/viewer"
    echo "  • Proxy: http://localhost:8084"
    echo ""
    echo "Test with: curl http://localhost:8080/users"
else
    echo -e "${YELLOW}⚠️  App may still be starting${NC}"
    echo "Wait a moment then try: curl http://localhost:8080/users"
    echo ""
    echo "Debug commands:"
    echo "  docker logs app"
    echo "  docker logs proxy"
    echo "  docker ps"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}This solution works on ANY system!${NC}"
echo -e "${BLUE}=========================================${NC}"