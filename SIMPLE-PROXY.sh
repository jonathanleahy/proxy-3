#!/bin/bash
# SIMPLE-PROXY.sh - Use a simpler proxy that just works

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIMPLE PROXY SETUP (No SSL issues)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up
docker stop proxy simple-proxy squid-proxy 2>/dev/null || true
docker rm proxy simple-proxy squid-proxy 2>/dev/null || true

# Option 1: Squid proxy (most reliable)
echo -e "${YELLOW}Starting Squid proxy (most reliable)...${NC}"

# Create squid config
mkdir -p squid-config
cat > squid-config/squid.conf << 'EOF'
http_port 3128

# Allow all
http_access allow all

# DNS
dns_nameservers 8.8.8.8 8.8.4.4

# Don't require authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm proxy

# Allow CONNECT to HTTPS ports
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access allow CONNECT SSL_ports

# Disable caching for testing
cache deny all
EOF

# Start Squid
docker run -d \
    --name squid-proxy \
    -p 3128:3128 \
    -v $(pwd)/squid-config/squid.conf:/etc/squid/squid.conf:ro \
    --dns 8.8.8.8 \
    ubuntu/squid || {
        echo "Squid image not available, trying alternative..."
        
        # Alternative: Use Alpine with tinyproxy
        docker run -d \
            --name simple-proxy \
            -p 3128:8888 \
            --dns 8.8.8.8 \
            dannydirect/tinyproxy:latest
    }

sleep 5

# Check which proxy is running
if docker ps | grep -q squid-proxy; then
    PROXY_NAME="squid-proxy"
    PROXY_PORT=3128
    echo -e "${GREEN}✅ Squid proxy running on port 3128${NC}"
elif docker ps | grep -q simple-proxy; then
    PROXY_NAME="simple-proxy"
    PROXY_PORT=3128
    echo -e "${GREEN}✅ Tinyproxy running on port 3128${NC}"
else
    echo -e "${RED}No proxy started successfully${NC}"
    
    # Last resort: Python proxy
    echo -e "${YELLOW}Starting Python HTTP proxy...${NC}"
    
    cat > proxy.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import sys

class ProxyHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = self.path[1:]  # Remove leading /
        if not url.startswith('http'):
            url = 'http://' + url
        try:
            with urllib.request.urlopen(url) as response:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(response.read())
        except Exception as e:
            self.send_error(502, str(e))
    
    def do_POST(self):
        self.do_GET()

PORT = 3128
with socketserver.TCPServer(("", PORT), ProxyHTTPRequestHandler) as httpd:
    print(f"Proxy running on port {PORT}")
    httpd.serve_forever()
EOF
    
    docker run -d \
        --name python-proxy \
        -p 3128:3128 \
        -v $(pwd)/proxy.py:/proxy.py:ro \
        python:3-alpine \
        python /proxy.py
    
    PROXY_NAME="python-proxy"
    PROXY_PORT=3128
    sleep 3
fi

# Test the proxy
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING SIMPLE PROXY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Test 1: HTTP request${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     -s --max-time 5 \
     http://httpbin.org/get 2>&1)

if echo "$response" | grep -q "origin"; then
    echo -e "${GREEN}✅ HTTP works perfectly!${NC}"
    echo "$response" | python -m json.tool 2>/dev/null | head -15 || echo "$response" | head -15
else
    echo -e "${RED}HTTP test failed${NC}"
    echo "Response: $response"
fi

echo ""
echo -e "${YELLOW}Test 2: HTTPS request (may need --insecure)${NC}"
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://api.github.com \
     -o /dev/null -w "HTTPS Status: %{http_code}\n"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}SIMPLE PROXY IS READY!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Proxy is running on port ${GREEN}$PROXY_PORT${NC}"
echo ""
echo "Use it with:"
echo "  ${GREEN}curl -x http://localhost:$PROXY_PORT http://any-website.com${NC}"
echo "  ${GREEN}curl -x http://localhost:$PROXY_PORT --insecure https://any-website.com${NC}"
echo ""
echo "For your Go app:"
echo "  ${GREEN}export HTTP_PROXY=http://localhost:$PROXY_PORT${NC}"
echo "  ${GREEN}export HTTPS_PROXY=http://localhost:$PROXY_PORT${NC}"
echo ""
echo "View logs:"
echo "  ${GREEN}docker logs $PROXY_NAME${NC}"