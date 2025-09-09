#!/bin/bash
# DEBUG-CERTS.sh - Debug certificate issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DEBUGGING CERTIFICATE ISSUES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# 1. Check if files exist
echo -e "${YELLOW}1. Checking certificate files:${NC}"
if [ -f mitmproxy-ca.pem ]; then
    echo "✅ mitmproxy-ca.pem exists ($(wc -c < mitmproxy-ca.pem) bytes)"
else
    echo "❌ mitmproxy-ca.pem NOT found"
fi

if [ -f combined-ca-bundle.pem ]; then
    echo "✅ combined-ca-bundle.pem exists ($(wc -c < combined-ca-bundle.pem) bytes)"
else
    echo "❌ combined-ca-bundle.pem NOT found"
fi

if [ -f mitm-ca.pem ]; then
    echo "✅ mitm-ca.pem exists ($(wc -c < mitm-ca.pem) bytes)"
else
    echo "❌ mitm-ca.pem NOT found"
fi

# 2. Check proxy status
echo ""
echo -e "${YELLOW}2. Checking proxy status:${NC}"
if docker ps | grep -q mitmproxy; then
    echo "✅ mitmproxy container is running"
    PROXY_PORT=8080
else
    echo "❌ mitmproxy is NOT running"
    echo "Start it with: ./WORKING-MITM.sh"
    exit 1
fi

# 3. Test basic connectivity
echo ""
echo -e "${YELLOW}3. Testing basic proxy connectivity:${NC}"
echo -n "HTTP through proxy: "
if curl -x http://localhost:$PROXY_PORT -s --max-time 3 http://httpbin.org/get -o /dev/null; then
    echo "✅ Works"
else
    echo "❌ Failed"
fi

# 4. Test HTTPS with different methods
echo ""
echo -e "${YELLOW}4. Testing HTTPS with different certificate approaches:${NC}"

echo ""
echo "a) With --insecure (should always work):"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://httpbin.org/json 2>&1)

if echo "$response" | grep -q "slideshow"; then
    echo "   ✅ Works - proxy IS intercepting HTTPS"
else
    echo "   ❌ Failed - $(echo $response | head -c 100)"
fi

echo ""
echo "b) With mitmproxy certificate only:"
if [ -f mitmproxy-ca.pem ]; then
    response=$(curl -x http://localhost:$PROXY_PORT \
         --cacert mitmproxy-ca.pem \
         -s --max-time 5 \
         https://httpbin.org/json 2>&1)
    
    if echo "$response" | grep -q "slideshow"; then
        echo "   ✅ Works with mitmproxy cert"
    else
        echo "   ❌ Failed: $(echo $response | head -c 150)"
    fi
else
    echo "   ⚠️  No mitmproxy certificate"
fi

echo ""
echo "c) With combined bundle:"
if [ -f combined-ca-bundle.pem ]; then
    response=$(curl -x http://localhost:$PROXY_PORT \
         --cacert combined-ca-bundle.pem \
         -s --max-time 5 \
         https://httpbin.org/json 2>&1)
    
    if echo "$response" | grep -q "slideshow"; then
        echo "   ✅ Works with combined bundle"
    else
        echo "   ❌ Failed: $(echo $response | head -c 150)"
    fi
else
    echo "   ⚠️  No combined bundle"
fi

# 5. Get fresh certificate from mitmproxy
echo ""
echo -e "${YELLOW}5. Getting fresh certificate from mitmproxy:${NC}"

# Try different paths
for path in \
    "/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem" \
    "~/.mitmproxy/mitmproxy-ca-cert.pem" \
    "/root/.mitmproxy/mitmproxy-ca-cert.pem"; do
    
    echo -n "Trying $path: "
    if docker exec mitmproxy cat "$path" > temp-cert.pem 2>/dev/null; then
        if [ -s temp-cert.pem ]; then
            echo "✅ Got certificate"
            mv temp-cert.pem mitmproxy-ca-fresh.pem
            break
        else
            echo "❌ Empty"
        fi
    else
        echo "❌ Not found"
    fi
done

# 6. Test with fresh certificate
if [ -f mitmproxy-ca-fresh.pem ]; then
    echo ""
    echo -e "${YELLOW}6. Testing with fresh certificate:${NC}"
    response=$(curl -x http://localhost:$PROXY_PORT \
         --cacert mitmproxy-ca-fresh.pem \
         -s --max-time 5 \
         https://httpbin.org/json 2>&1)
    
    if echo "$response" | grep -q "slideshow"; then
        echo "   ✅ Works with fresh cert!"
        echo ""
        echo -e "${GREEN}SOLUTION: Use the fresh certificate${NC}"
        cp mitmproxy-ca-fresh.pem mitmproxy-ca.pem
        echo "Updated mitmproxy-ca.pem with fresh certificate"
    else
        echo "   ❌ Still fails: $(echo $response | head -c 150)"
    fi
fi

# 7. Alternative solution
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ALTERNATIVE SOLUTIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "If certificates aren't working, you can:"
echo ""
echo "1. Always use --insecure flag:"
echo "   ${GREEN}curl -x http://localhost:$PROXY_PORT --insecure https://site.com${NC}"
echo ""
echo "2. Set environment variable to ignore certs:"
echo "   ${GREEN}export NODE_TLS_REJECT_UNAUTHORIZED=0${NC}"
echo "   ${GREEN}export PYTHONWARNINGS='ignore:Unverified HTTPS'${NC}"
echo ""
echo "3. For Go apps, use InsecureSkipVerify:"
echo "   ${GREEN}TLSClientConfig: &tls.Config{InsecureSkipVerify: true}${NC}"
echo ""

# 8. Working example
echo -e "${YELLOW}Working example that captures HTTPS:${NC}"
echo "curl -x http://localhost:$PROXY_PORT --insecure https://api.github.com/users/github"
echo ""
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://api.github.com/users/github | python3 -m json.tool 2>/dev/null | head -20

echo ""
echo -e "${YELLOW}Check proxy logs to see captured traffic:${NC}"
echo "docker logs --tail 5 mitmproxy"