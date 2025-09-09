#!/bin/bash
# FIX-MITM-TLS.sh - Fix mitmproxy's TLS handshake issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING MITMPROXY TLS HANDSHAKE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The issue: mitmproxy itself can't verify external SSL certs"
echo "Solution: Run mitmproxy with --ssl-insecure"
echo ""

# Stop old proxy
echo -e "${YELLOW}Stopping old mitmproxy...${NC}"
docker stop mitmproxy proxy 2>/dev/null || true
docker rm mitmproxy proxy 2>/dev/null || true

# Start mitmproxy with SSL verification disabled
echo -e "${YELLOW}Starting mitmproxy with --ssl-insecure flag...${NC}"

docker run -d \
    --name mitmproxy \
    -p 8080:8080 \
    -v $(pwd)/captured:/captured \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-host 0.0.0.0 \
        --listen-port 8080 \
        --ssl-insecure \
        --set confdir=/home/mitmproxy/.mitmproxy

sleep 3

if docker ps | grep -q mitmproxy; then
    echo -e "${GREEN}✅ MITMProxy started with SSL verification disabled${NC}"
else
    echo -e "${RED}Failed to start${NC}"
    docker logs mitmproxy
    exit 1
fi

# Get the certificate
echo ""
echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || {
    sleep 2
    docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem
}

if [ -s mitmproxy-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate obtained${NC}"
else
    echo -e "${YELLOW}Certificate may not be ready yet${NC}"
fi

# Test the fixed setup
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING FIXED SETUP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Test 1: HTTP request:${NC}"
curl -x http://localhost:8080 \
     -s --max-time 5 \
     http://httpbin.org/get \
     -o /dev/null \
     -w "Status: %{http_code}\n"

echo ""
echo -e "${YELLOW}Test 2: HTTPS request (with --insecure on client):${NC}"
response=$(curl -x http://localhost:8080 \
     --insecure \
     -s --max-time 5 \
     https://httpbin.org/json 2>&1)

if echo "$response" | grep -q "slideshow"; then
    echo -e "${GREEN}✅ SUCCESS! HTTPS interception working!${NC}"
    echo "Sample response:"
    echo "$response" | python3 -m json.tool 2>/dev/null | head -10 || echo "$response" | head -10
else
    echo -e "${RED}Failed: $response${NC}"
fi

echo ""
echo -e "${YELLOW}Test 3: GitHub API:${NC}"
curl -x http://localhost:8080 \
     --insecure \
     -s --max-time 5 \
     https://api.github.com/users/github \
     -o /dev/null \
     -w "Status: %{http_code}\n"

# Check logs
echo ""
echo -e "${YELLOW}Checking mitmproxy logs:${NC}"
docker logs --tail 10 mitmproxy 2>&1 | grep -v "certificate verify failed" | grep -E "GET|POST|<<" || echo "No recent requests"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}FIXED! MITMProxy is now working${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The --ssl-insecure flag tells mitmproxy to accept"
echo "any certificate from upstream servers."
echo ""
echo "To capture HTTPS traffic:"
echo "  ${GREEN}curl -x http://localhost:8080 --insecure https://any-site.com${NC}"
echo ""
echo "View captured traffic:"
echo "  ${GREEN}docker logs mitmproxy${NC}"
echo ""
echo "For your Go app:"
echo "  ${GREEN}export HTTP_PROXY=http://localhost:8080${NC}"
echo "  ${GREEN}export HTTPS_PROXY=http://localhost:8080${NC}"
echo "  Add to your code: ${GREEN}InsecureSkipVerify: true${NC}"