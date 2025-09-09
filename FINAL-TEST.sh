#!/bin/bash
# FINAL-TEST.sh - Test that everything is working with certificates

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FINAL TEST - HTTPS CAPTURE WITH CERTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# First, set up the certificate environment
if [ -f setup-certs.sh ]; then
    echo -e "${YELLOW}Setting up certificate environment...${NC}"
    source ./setup-certs.sh
    echo ""
fi

# Check if mitmproxy is running
PROXY_PORT=8080
if ! docker ps | grep -q mitmproxy; then
    echo -e "${RED}MITMProxy not running!${NC}"
    echo "Start it with: ./WORKING-MITM.sh"
    exit 1
fi

echo -e "${GREEN}✅ MITMProxy is running on port $PROXY_PORT${NC}"
echo ""

# Test 1: HTTPS with proper certificates (no --insecure needed!)
echo -e "${YELLOW}Test 1: HTTPS with certificates (no --insecure):${NC}"
if [ -f combined-ca-bundle.pem ]; then
    response=$(curl -x http://localhost:$PROXY_PORT \
         --cacert combined-ca-bundle.pem \
         -s --max-time 5 \
         https://api.github.com/users/github 2>&1)
    
    if echo "$response" | grep -q "login"; then
        echo -e "${GREEN}✅ SUCCESS! HTTPS working with certificates!${NC}"
        echo "Sample response:"
        echo "$response" | python3 -m json.tool 2>/dev/null | head -20 || echo "$response" | head -20
    else
        echo -e "${RED}Certificate test failed${NC}"
        echo "Response: $response"
    fi
else
    echo -e "${RED}No combined certificate bundle found${NC}"
    echo "Run ./USE-SYSTEM-CERTS.sh first"
fi

echo ""
echo "---"
echo ""

# Test 2: Multiple HTTPS sites
echo -e "${YELLOW}Test 2: Testing multiple HTTPS sites:${NC}"
sites=("https://api.github.com" "https://httpbin.org/json" "https://www.google.com")

for site in "${sites[@]}"; do
    echo -n "  $site: "
    status=$(curl -x http://localhost:$PROXY_PORT \
         --cacert combined-ca-bundle.pem \
         -s --max-time 3 \
         -o /dev/null \
         -w "%{http_code}" \
         "$site" 2>/dev/null)
    
    if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
        echo -e "${GREEN}✅ $status${NC}"
    else
        echo -e "${RED}❌ $status${NC}"
    fi
done

echo ""
echo "---"
echo ""

# Test 3: Show what mitmproxy captured
echo -e "${YELLOW}Test 3: What mitmproxy captured:${NC}"
docker logs --tail 15 mitmproxy 2>&1 | grep -E "GET|POST|github|httpbin|google" || echo "No recent captures"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  YOUR SETUP STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check setup status
if [ -f combined-ca-bundle.pem ]; then
    echo "✅ Combined certificate bundle exists"
fi

if [ -n "$SSL_CERT_FILE" ]; then
    echo "✅ SSL_CERT_FILE is set to: $SSL_CERT_FILE"
fi

if [ -n "$CURL_CA_BUNDLE" ]; then
    echo "✅ CURL_CA_BUNDLE is set"
fi

if docker ps | grep -q mitmproxy; then
    echo "✅ MITMProxy is running"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HOW TO USE WITH YOUR APP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "1. For command line tools:"
echo "   ${GREEN}source ./setup-certs.sh${NC}"
echo "   ${GREEN}curl -x http://localhost:8080 https://any-site.com${NC}"
echo ""
echo "2. For your Go app, add to the code:"
echo "   ${GREEN}export SSL_CERT_FILE=$(pwd)/combined-ca-bundle.pem${NC}"
echo "   ${GREEN}export HTTP_PROXY=http://localhost:8080${NC}"
echo "   ${GREEN}export HTTPS_PROXY=http://localhost:8080${NC}"
echo "   ${GREEN}go run your-app.go${NC}"
echo ""
echo "3. View captured traffic:"
echo "   ${GREEN}docker logs mitmproxy | less${NC}"
echo ""

if echo "$response" | grep -q "login"; then
    echo -e "${GREEN}🎉 EVERYTHING IS WORKING!${NC}"
    echo "MITMProxy is successfully decrypting HTTPS traffic!"
    echo "You can now see all HTTPS request/response content!"
else
    echo -e "${YELLOW}⚠️  Some tests failed - check the output above${NC}"
fi