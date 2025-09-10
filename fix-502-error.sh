#!/bin/bash
# fix-502-error.sh - Fix 502 Bad Gateway errors

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔧 Fixing 502 Bad Gateway Error${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Stop everything
echo -e "${YELLOW}Step 1: Stopping all containers...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down 2>/dev/null || true
docker stop app transparent-proxy mock-viewer 2>/dev/null || true
docker rm app transparent-proxy mock-viewer 2>/dev/null || true
echo -e "${GREEN}✅ Containers stopped${NC}"
echo ""

# Step 2: Clean up certificates
echo -e "${YELLOW}Step 2: Cleaning up old certificates...${NC}"
docker volume rm proxy-3_certs 2>/dev/null || true
docker volume rm $(basename $(pwd))_certs 2>/dev/null || true
echo -e "${GREEN}✅ Certificate volumes removed${NC}"
echo ""

# Step 3: Rebuild images
echo -e "${YELLOW}Step 3: Rebuilding Docker images...${NC}"
docker compose -f docker-compose-transparent.yml build --no-cache
echo -e "${GREEN}✅ Images rebuilt${NC}"
echo ""

# Step 4: Start fresh
echo -e "${YELLOW}Step 4: Starting fresh system...${NC}"
./start-capture.sh
echo ""

# Step 5: Wait for initialization
echo -e "${YELLOW}Step 5: Waiting for full initialization...${NC}"
sleep 5

# Check certificate was created
if docker exec app ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate generated successfully${NC}"
else
    echo -e "${RED}❌ Certificate generation failed${NC}"
    exit 1
fi

# Step 6: Start health server
echo -e "${YELLOW}Step 6: Starting health server...${NC}"
docker exec -d -u appuser app sh -c "cd /proxy && go run health-server.go" 2>/dev/null || true
sleep 3

if curl -s http://localhost:8080/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Health server running${NC}"
fi
echo ""

# Step 7: Test the fix
echo -e "${YELLOW}Step 7: Testing HTTPS capture...${NC}"
echo ""

# Run debug test
docker exec -u appuser app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
    export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    cd /proxy
    go run test-https-debug.go
" 2>&1 | tail -20

echo ""
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  📋 Next Steps${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""
echo "If you're still getting 502 errors:"
echo ""
echo "1. Run diagnostics:"
echo -e "   ${YELLOW}./diagnose-proxy.sh${NC}"
echo ""
echo "2. Test with debug script:"
echo -e "   ${YELLOW}./run-app.sh 'go run /proxy/test-https-debug.go'${NC}"
echo ""
echo "3. Try the insecure test (skips cert validation):"
echo -e "   ${YELLOW}docker exec -u appuser app sh -c 'cd /proxy && go run test-https-debug.go'${NC}"
echo ""
echo "4. Check your Docker/system configuration:"
echo "   - Docker version: $(docker --version)"
echo "   - OS: $(uname -s)"
echo "   - Architecture: $(uname -m)"
echo ""
echo "5. If on macOS or Windows, ensure Docker Desktop has enough resources:"
echo "   - Memory: At least 4GB"
echo "   - CPU: At least 2 cores"
echo ""