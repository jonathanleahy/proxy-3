#!/bin/bash
# WORKING-MITM.sh - Get mitmproxy working properly to see HTTPS content

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MITMPROXY - SEE HTTPS CONTENT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "MITMProxy CAN decrypt HTTPS and show request/response bodies"
echo "Squid/Tinyproxy cannot - they just tunnel HTTPS"
echo ""

# Clean up
docker stop mitmproxy mitm proxy 2>/dev/null || true
docker rm mitmproxy mitm proxy 2>/dev/null || true

# Step 1: Start mitmproxy with proper network config
echo -e "${YELLOW}Starting mitmproxy with fixed networking...${NC}"

# Create custom entrypoint to test connectivity first
cat > mitm-start.sh << 'EOF'
#!/bin/sh
echo "Testing network connectivity..."

# Test DNS
echo "DNS test:"
nslookup google.com || echo "DNS might be an issue"

# Test connectivity
echo "Connection test:"
wget -O- --timeout=5 http://httpbin.org/get 2>&1 | head -5 || echo "Connection test failed"

# Start mitmproxy
echo "Starting mitmproxy..."
mitmdump --listen-host 0.0.0.0 --listen-port 8080 --set confdir=/home/mitmproxy/.mitmproxy
EOF

chmod +x mitm-start.sh

# Try different network modes
echo -e "${YELLOW}Method 1: Starting with host network (best for connectivity)...${NC}"

docker run -d \
    --name mitmproxy \
    --network host \
    -v $(pwd)/mitm-start.sh:/mitm-start.sh:ro \
    -v $(pwd)/captured:/captured \
    mitmproxy/mitmproxy \
    sh /mitm-start.sh 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Host network not allowed, trying bridge..."
    docker rm mitmproxy 2>/dev/null
    
    echo -e "${YELLOW}Method 2: Bridge network with explicit DNS...${NC}"
    docker run -d \
        --name mitmproxy \
        -p 8080:8080 \
        --dns 8.8.8.8 \
        --dns 8.8.4.4 \
        --add-host api.github.com:140.82.113.5 \
        --add-host httpbin.org:34.227.213.82 \
        -v $(pwd)/captured:/captured \
        mitmproxy/mitmproxy \
        mitmdump --listen-host 0.0.0.0 --listen-port 8080
    
    PROXY_PORT=8080
else
    PROXY_PORT=8080
    echo -e "${GREEN}Using host network${NC}"
fi

sleep 5

# Check if it's running
if ! docker ps | grep -q mitmproxy; then
    echo -e "${RED}MITMProxy failed to start${NC}"
    echo "Logs:"
    docker logs mitmproxy 2>&1 | tail -20
    
    # Try one more method
    echo -e "${YELLOW}Method 3: Using Docker's internal DNS...${NC}"
    docker rm mitmproxy 2>/dev/null
    
    docker run -d \
        --name mitmproxy \
        -p 8080:8080 \
        -v $(pwd)/captured:/captured \
        -e HTTP_PROXY="" \
        -e HTTPS_PROXY="" \
        -e NO_PROXY="*" \
        mitmproxy/mitmproxy \
        mitmdump --listen-host 0.0.0.0 --listen-port 8080 --ssl-insecure
    
    PROXY_PORT=8080
    sleep 5
fi

if docker ps | grep -q mitmproxy; then
    echo -e "${GREEN}✅ MITMProxy is running on port $PROXY_PORT${NC}"
else
    echo -e "${RED}Failed to start mitmproxy${NC}"
    exit 1
fi

# Get certificate
echo ""
echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitm-ca.pem 2>/dev/null || {
    sleep 3
    docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitm-ca.pem
}

if [ -f mitm-ca.pem ] && [ -s mitm-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate saved${NC}"
else
    echo -e "${YELLOW}Certificate not ready yet${NC}"
fi

# Test from inside container first
echo ""
echo -e "${YELLOW}Testing connectivity from inside mitmproxy container...${NC}"
docker exec mitmproxy wget -O- --timeout=5 http://httpbin.org/get 2>&1 | grep -q "url" && {
    echo -e "${GREEN}✅ Container can reach internet${NC}"
} || {
    echo -e "${RED}Container cannot reach internet - this causes 502 errors${NC}"
    echo ""
    echo "Trying to fix with proxy bypass..."
    
    # Restart without any proxy settings
    docker stop mitmproxy && docker rm mitmproxy
    docker run -d \
        --name mitmproxy \
        -p 8080:8080 \
        --network bridge \
        -v $(pwd)/captured:/captured \
        mitmproxy/mitmproxy \
        sh -c "unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy && mitmdump --listen-host 0.0.0.0 --listen-port 8080"
    
    sleep 5
}

# Create test script that shows HTTPS content
cat > test-mitm-capture.sh << 'EOF'
#!/bin/bash
PROXY_PORT=8080

echo "Testing mitmproxy HTTPS interception..."
echo ""

# Test 1: HTTP (should always work)
echo "1. HTTP request (no SSL):"
curl -x http://localhost:$PROXY_PORT \
     -s --max-time 10 \
     http://httpbin.org/get | python -m json.tool | head -20 || echo "HTTP failed"

echo ""

# Test 2: HTTPS with cert ignore (shows content)
echo "2. HTTPS request (ignore cert - YOU CAN SEE THE CONTENT):"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://httpbin.org/json)

if [ -n "$response" ]; then
    echo "✅ HTTPS CONTENT VISIBLE:"
    echo "$response" | python -m json.tool || echo "$response"
else
    echo "❌ No response"
fi

echo ""
echo "3. Check what mitmproxy captured:"
docker logs --tail 10 mitmproxy | grep -E "GET|POST|200|304"
EOF

chmod +x test-mitm-capture.sh

# Create script to view captured traffic
cat > view-captures.sh << 'EOF'
#!/bin/bash
echo "=== CAPTURED HTTPS TRAFFIC ==="
echo ""
echo "Recent requests:"
docker logs mitmproxy 2>&1 | grep -E "GET|POST|PUT|DELETE" | tail -20
echo ""
echo "To see full details with request/response bodies:"
echo "docker logs mitmproxy | less"
echo ""
echo "To save captures to file:"
echo "docker logs mitmproxy > captured-traffic.txt"
EOF

chmod +x view-captures.sh

# Final test
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING HTTPS CONTENT CAPTURE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Making HTTPS request through mitmproxy...${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://api.github.com/users/github 2>&1)

if echo "$response" | grep -q "login"; then
    echo -e "${GREEN}✅ SUCCESS! MITMProxy is decrypting HTTPS!${NC}"
    echo ""
    echo "Sample decrypted HTTPS response:"
    echo "$response" | python -m json.tool 2>/dev/null | head -15 || echo "$response" | head -15
    echo ""
    echo -e "${GREEN}You can see the FULL HTTPS content!${NC}"
else
    if echo "$response" | grep -q "502"; then
        echo -e "${RED}502 Bad Gateway - Network issue${NC}"
        echo "The container can't reach external sites"
        echo ""
        echo "Try running mitmproxy on host directly:"
        echo "  pip install mitmproxy"
        echo "  mitmproxy --listen-port 8080"
    else
        echo -e "${YELLOW}Response: $response${NC}"
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HOW TO USE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "MITMProxy is running on port $PROXY_PORT"
echo ""
echo "To see HTTPS content:"
echo "  ${GREEN}curl -x http://localhost:$PROXY_PORT --insecure https://any-site.com${NC}"
echo ""
echo "Run tests:"
echo "  ${GREEN}./test-mitm-capture.sh${NC}"
echo ""
echo "View captured traffic:"
echo "  ${GREEN}./view-captures.sh${NC}"
echo "  ${GREEN}docker logs mitmproxy${NC}"
echo ""
echo -e "${YELLOW}Note: The --insecure flag is needed because mitmproxy"
echo "uses its own certificate to decrypt HTTPS traffic.${NC}"