#!/bin/bash
# Start system in proxy mode (no iptables required)
# Apps must be configured to use the proxy

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting in Proxy Mode (No iptables)${NC}"
echo "============================================"
echo "This mode requires apps to be configured with proxy settings"
echo "but works in all environments without iptables issues."
echo ""

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker compose -f docker-compose-proxy-mode.yml down 2>/dev/null || true
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker compose -f docker-compose-noiptables.yml down 2>/dev/null || true

# Build
echo -e "${YELLOW}Building containers...${NC}"
docker compose -f docker-compose-proxy-mode.yml build

# Start
echo -e "${YELLOW}Starting containers...${NC}"
docker compose -f docker-compose-proxy-mode.yml up -d

# Wait for proxy
echo -e "${YELLOW}Waiting for proxy to be ready...${NC}"
sleep 5

# Check certificate
if docker exec proxy ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate ready${NC}"
else
    echo -e "${YELLOW}⚠️  Certificate may still be generating${NC}"
fi

# Start example app with proxy configuration
echo -e "${YELLOW}Starting example app with proxy settings...${NC}"
docker exec -d app sh -c "
    export HTTP_PROXY=http://proxy:8084
    export HTTPS_PROXY=http://proxy:8084
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    cd /proxy/example-app && go run main.go
"

sleep 3

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 System Ready in Proxy Mode!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "The proxy is running and will capture HTTPS traffic"
echo "from apps configured to use it."
echo ""
echo "Proxy settings for your apps:"
echo "  HTTP_PROXY=http://localhost:8084"
echo "  HTTPS_PROXY=http://localhost:8084"
echo ""
echo "Test endpoints:"
echo "  • http://localhost:8080/health (no proxy needed)"
echo "  • http://localhost:8080/users (uses proxy for HTTPS)"
echo "  • http://localhost:8090/viewer (view captures)"
echo ""
echo "To configure other apps to use the proxy:"
echo "  export HTTP_PROXY=http://localhost:8084"
echo "  export HTTPS_PROXY=http://localhost:8084"
echo "  export SSL_CERT_FILE=\$(pwd)/certs/mitmproxy-ca-cert.pem"
echo ""
echo "Note: The app MUST support proxy settings for this to work!"