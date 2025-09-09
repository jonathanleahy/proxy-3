#!/bin/bash
# FIX 5: THE WORKING SOLUTION (FINAL-CLEANUP-AND-RUN)
# Uses the proven working proxy mode configuration

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 5: PROVEN WORKING SOLUTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ Known to work on most systems"
echo "  ✓ Simple proxy mode"
echo "  ✓ Certificate handled properly"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ Go apps need ProxyFromEnvironment"
echo ""

# BUILD IMAGES FIRST (in case FINAL-CLEANUP-AND-RUN doesn't build them)
echo -e "${YELLOW}Building Docker images...${NC}"
docker build -t proxy-image -f docker/Dockerfile.mitmproxy-simple . 2>/dev/null || \
    docker build -t proxy-image -f docker/Dockerfile.mitmproxy-universal .
docker build -t app-image -f docker/Dockerfile.app.minimal .
docker build -t viewer-image -f docker/Dockerfile.viewer . 2>/dev/null || \
    docker build -t viewer-image -f Dockerfile .
echo -e "${GREEN}✅ Images built${NC}"

# Just use the working solution
echo -e "${YELLOW}Running FINAL-CLEANUP-AND-RUN.sh...${NC}"
./FINAL-CLEANUP-AND-RUN.sh

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${RED}REQUIRED Go code change:${NC}"
echo "  client := &http.Client{"
echo "      Transport: &http.Transport{"
echo "          Proxy: http.ProxyFromEnvironment,"
echo "      },"
echo "  }"
echo ""
echo "Then run your app:"
echo -e "${GREEN}docker run \\
    -e HTTP_PROXY=http://172.17.0.1:8084 \\
    -e HTTPS_PROXY=http://172.17.0.1:8084 \\
    -v \$(pwd)/mitmproxy-ca.pem:/ca.pem \\
    -e SSL_CERT_FILE=/ca.pem \\
    your-go-app-image${NC}"
echo ""
echo "View captures at: http://localhost:8090/viewer"