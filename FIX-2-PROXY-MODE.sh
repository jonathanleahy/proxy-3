#!/bin/bash
# FIX 2: PROXY MODE (Uses HTTP_PROXY environment variables)
# Works on ALL machines but Go apps need ProxyFromEnvironment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 2: PROXY MODE (HTTP_PROXY)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ Works on ALL machines"
echo "  ✓ No iptables needed"
echo "  ✓ Simple and reliable"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ Go apps need http.ProxyFromEnvironment"
echo "  ✗ Or use http.Get() instead of custom client"
echo ""

# Clean up
docker stop proxy app viewer 2>/dev/null || true
docker rm -f proxy app viewer 2>/dev/null || true

# BUILD IMAGES FIRST
echo -e "${YELLOW}Building Docker images...${NC}"
docker build -t proxy-3-transparent-proxy -f docker/Dockerfile.mitmproxy-universal . || \
    docker build -t proxy-3-transparent-proxy -f docker/Dockerfile.mitmproxy .
docker build -t proxy-3-viewer -f docker/Dockerfile.viewer . || \
    docker build -t proxy-3-viewer -f Dockerfile .
echo -e "${GREEN}✅ Images built${NC}"

# Start proxy
echo -e "${YELLOW}Starting proxy on port 8084...${NC}"
docker run -d \
    --name proxy \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-3-transparent-proxy \
    sh -c "
        mkdir -p ~/.mitmproxy /captured
        mitmdump --quiet >/dev/null 2>&1 & sleep 3; kill \$! 2>/dev/null
        echo '✅ Proxy ready'
        exec mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    "

sleep 5

# Get certificate
docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

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

echo -e "${GREEN}✅ Proxy running on port 8084${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${RED}REQUIRED:${NC} Your Go app must use:"
echo "  client := &http.Client{"
echo "      Transport: &http.Transport{"
echo "          Proxy: http.ProxyFromEnvironment,"
echo "      },"
echo "  }"
echo ""
echo "Option A - Run with Docker:"
echo -e "${GREEN}docker run \\
    -e HTTP_PROXY=http://172.17.0.1:8084 \\
    -e HTTPS_PROXY=http://172.17.0.1:8084 \\
    -v \$(pwd)/mitmproxy-ca.pem:/ca.pem \\
    -e SSL_CERT_FILE=/ca.pem \\
    your-go-app-image${NC}"
echo ""
echo "Option B - Run locally:"
echo -e "${GREEN}export HTTP_PROXY=http://localhost:8084${NC}"
echo -e "${GREEN}export HTTPS_PROXY=http://localhost:8084${NC}"
echo -e "${GREEN}export SSL_CERT_FILE=\$(pwd)/mitmproxy-ca.pem${NC}"
echo -e "${GREEN}go run your-app.go${NC}"
echo ""
echo "View captures at: http://localhost:8090/viewer"