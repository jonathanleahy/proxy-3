#!/bin/bash
# FIX-ALL-SSL.sh - Fix both 502 Bad Gateway and SSL certificate issues

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING 502 BAD GATEWAY & SSL ISSUES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up old proxy
echo -e "${YELLOW}Cleaning up old proxy...${NC}"
docker stop proxy 2>/dev/null || true
docker rm proxy 2>/dev/null || true

# Find free port
PROXY_PORT=8888
while lsof -i :$PROXY_PORT 2>/dev/null | grep -q LISTEN; do
    PROXY_PORT=$((PROXY_PORT + 1))
done

# Start proxy with proper network settings
echo -e "${YELLOW}Starting proxy with proper settings on port $PROXY_PORT...${NC}"

# Method 1: Try with host network first (best for connectivity)
docker run -d \
    --name proxy \
    --network host \
    mitmproxy/mitmproxy \
    mitmdump --listen-port $PROXY_PORT 2>/dev/null || {
        echo "Host network not allowed, using bridge..."
        docker rm proxy 2>/dev/null
        
        # Method 2: Bridge network with DNS
        docker run -d \
            --name proxy \
            -p $PROXY_PORT:$PROXY_PORT \
            --dns 8.8.8.8 \
            --dns 8.8.4.4 \
            mitmproxy/mitmproxy \
            mitmdump --listen-port $PROXY_PORT
    }

sleep 3

if ! docker ps | grep -q proxy; then
    echo -e "${RED}Proxy failed to start${NC}"
    docker logs proxy
    exit 1
fi

echo -e "${GREEN}✅ Proxy started on port $PROXY_PORT${NC}"

# Generate and get certificate
echo ""
echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"

# Wait for certificate generation
sleep 2

# Try multiple paths to get certificate
docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || \
docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || \
docker exec proxy cat /root/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || {
    echo "Certificate not found, generating..."
    docker exec proxy sh -c "mitmdump --quiet & sleep 3; kill %1"
    sleep 2
    docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem
}

if [ -f mitmproxy-ca.pem ] && [ -s mitmproxy-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate obtained${NC}"
else
    echo -e "${RED}Failed to get certificate${NC}"
fi

# Test connectivity from inside proxy container
echo ""
echo -e "${YELLOW}Testing proxy connectivity...${NC}"

echo "1. Testing DNS resolution:"
docker exec proxy nslookup api.github.com 2>&1 | head -3 || \
docker exec proxy ping -c 1 api.github.com 2>&1 | head -3 || \
echo "DNS test skipped"

echo ""
echo "2. Testing direct HTTPS from proxy container:"
docker exec proxy wget -O- --timeout=5 https://api.github.com 2>&1 | head -5 || \
docker exec proxy curl -s --max-time 5 https://api.github.com 2>&1 | head -5 || \
echo "Direct test failed"

# Create test script
echo ""
echo -e "${YELLOW}Creating test scripts...${NC}"

# Script 1: Test with curl (multiple methods)
cat > test-ssl-fixed.sh << EOF
#!/bin/bash
echo "Testing proxy on port $PROXY_PORT..."
echo ""

# Method 1: Ignore SSL
echo "1. Ignoring SSL certificate:"
curl -x http://localhost:$PROXY_PORT \\
     --insecure \\
     -s --max-time 10 \\
     https://httpbin.org/get \\
     | head -10 || echo "Failed"

echo ""

# Method 2: With certificate
if [ -f mitmproxy-ca.pem ]; then
    echo "2. Using mitmproxy certificate:"
    curl -x http://localhost:$PROXY_PORT \\
         --cacert mitmproxy-ca.pem \\
         -s --max-time 10 \\
         https://httpbin.org/get \\
         | head -10 || echo "Failed"
fi

echo ""

# Method 3: HTTP only (no SSL issues)
echo "3. Testing HTTP (no SSL):"
curl -x http://localhost:$PROXY_PORT \\
     -s --max-time 10 \\
     http://httpbin.org/get \\
     | head -10 || echo "Failed"
EOF

chmod +x test-ssl-fixed.sh

# Script 2: Alternative proxy setup
cat > use-different-proxy.sh << EOF
#!/bin/bash
# Alternative: Use a simpler HTTP proxy

echo "Starting simple HTTP proxy on port 7777..."

# Kill old proxy
docker stop simple-proxy 2>/dev/null || true
docker rm simple-proxy 2>/dev/null || true

# Start tinyproxy (simpler, less SSL issues)
docker run -d \\
    --name simple-proxy \\
    -p 7777:8888 \\
    dannydirect/tinyproxy:latest

sleep 3

echo "Test with:"
echo "  curl -x http://localhost:7777 http://httpbin.org/get"
echo "  curl -x http://localhost:7777 -k https://httpbin.org/get"
EOF

chmod +x use-different-proxy.sh

# Final test
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING FIXED SETUP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Test 1: HTTP request (no SSL)${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     -s --max-time 5 \
     http://httpbin.org/get 2>&1)

if echo "$response" | grep -q "Host"; then
    echo -e "${GREEN}✅ HTTP proxy works!${NC}"
else
    echo -e "${RED}HTTP proxy failed: $response${NC}"
fi

echo ""
echo -e "${YELLOW}Test 2: HTTPS with --insecure${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://httpbin.org/get 2>&1)

if echo "$response" | grep -q "Host"; then
    echo -e "${GREEN}✅ HTTPS proxy works (ignoring cert)!${NC}"
else
    echo -e "${RED}HTTPS failed: $(echo $response | head -c 100)${NC}"
    
    # Check if it's a network issue
    echo ""
    echo -e "${YELLOW}Debugging network issue...${NC}"
    
    # Test without proxy
    echo "Testing direct connection (no proxy):"
    curl -s --max-time 5 https://httpbin.org/get -o /dev/null -w "Status: %{http_code}\n" || echo "Direct connection also failed"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SOLUTIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "If you get 502 Bad Gateway:"
echo "  1. The proxy can't reach the internet"
echo "  2. Try: ${GREEN}./use-different-proxy.sh${NC} for a simpler proxy"
echo "  3. Check your Docker network: ${GREEN}docker network ls${NC}"
echo ""
echo "For SSL issues:"
echo "  1. Use ${GREEN}--insecure${NC} flag with curl"
echo "  2. Or use the certificate: ${GREEN}--cacert mitmproxy-ca.pem${NC}"
echo "  3. For HTTP only (no SSL): ${GREEN}curl -x http://localhost:$PROXY_PORT http://site.com${NC}"
echo ""
echo "Test scripts:"
echo "  ${GREEN}./test-ssl-fixed.sh${NC} - Test the current proxy"
echo "  ${GREEN}./use-different-proxy.sh${NC} - Try a simpler proxy"