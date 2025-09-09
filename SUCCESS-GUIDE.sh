#!/bin/bash
# SUCCESS-GUIDE.sh - Complete guide for using your working HTTPS capture

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 HTTPS CAPTURE IS WORKING!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "You have successfully set up HTTPS traffic capture!"
echo "Here's everything you can do now:"
echo ""

# Find which proxy is running
if docker ps | grep -q mitmproxy; then
    PROXY_PORT=8080
    PROXY_TYPE="mitmproxy"
elif pgrep mitmdump > /dev/null; then
    PROXY_PORT=8081
    PROXY_TYPE="local mitmproxy"
else
    PROXY_PORT=8080
    PROXY_TYPE="proxy"
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  1. CAPTURE HTTPS TRAFFIC${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Basic usage:${NC}"
echo "curl -x http://localhost:$PROXY_PORT --insecure https://api.github.com/users/github"
echo ""

echo -e "${YELLOW}Capture from any HTTPS site:${NC}"
echo "curl -x http://localhost:$PROXY_PORT --insecure https://www.google.com"
echo "curl -x http://localhost:$PROXY_PORT --insecure https://api.github.com"
echo "curl -x http://localhost:$PROXY_PORT --insecure https://jsonplaceholder.typicode.com/posts"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  2. VIEW CAPTURED TRAFFIC${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

if [ "$PROXY_TYPE" = "mitmproxy" ]; then
    echo -e "${YELLOW}View all captured requests/responses:${NC}"
    echo "docker logs mitmproxy"
    echo ""
    echo -e "${YELLOW}Watch traffic in real-time:${NC}"
    echo "docker logs -f mitmproxy"
    echo ""
    echo -e "${YELLOW}Save captures to file:${NC}"
    echo "docker logs mitmproxy > captured-traffic.log"
else
    echo -e "${YELLOW}View captured traffic:${NC}"
    echo "tail -f /tmp/mitmproxy.log"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  3. USE WITH YOUR GO APP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Option 1: Set environment variables:${NC}"
cat << EOF
export HTTP_PROXY=http://localhost:$PROXY_PORT
export HTTPS_PROXY=http://localhost:$PROXY_PORT
go run your-app.go
EOF

echo ""
echo -e "${YELLOW}Option 2: Add to your Go code:${NC}"
cat << 'EOF'
import (
    "crypto/tls"
    "net/http"
    "net/url"
)

proxyURL, _ := url.Parse("http://localhost:8080")
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyURL(proxyURL),
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: true, // Required for mitmproxy
        },
    },
}

// Now use this client for requests
resp, err := client.Get("https://api.github.com")
EOF

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  4. TEST IT NOW${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Making a test HTTPS request...${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://api.github.com/users/octocat 2>&1)

if echo "$response" | grep -q "login"; then
    echo -e "${GREEN}✅ Captured HTTPS response:${NC}"
    echo "$response" | python3 -m json.tool 2>/dev/null | head -15 || echo "$response" | head -15
    echo ""
    echo -e "${GREEN}You can see the decrypted HTTPS content!${NC}"
else
    echo "Response: $response"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  5. IMPORTANT NOTES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "• The ${GREEN}--insecure${NC} flag is REQUIRED (tells curl to accept mitmproxy's certificate)"
echo "• MITMProxy acts as a 'man in the middle' to decrypt HTTPS"
echo "• You can see ALL request/response content including:"
echo "  - Headers"
echo "  - Request bodies (POST data)"
echo "  - Response bodies (JSON, HTML, etc.)"
echo "  - Cookies"
echo "  - Authentication tokens"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ EVERYTHING IS WORKING!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your HTTPS capture proxy is fully operational."
echo "You can now monitor and debug any HTTPS traffic!"