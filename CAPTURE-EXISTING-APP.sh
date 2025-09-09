#!/bin/bash
# CAPTURE-EXISTING-APP.sh - Capture traffic from your app already running on 8080

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  CAPTURE FROM EXISTING APP ON PORT 8080${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Your app stays running on port 8080!${NC}"
echo "We'll set up a proxy to capture its HTTPS traffic"
echo ""

# Check if app is running on 8080
echo -e "${YELLOW}Checking your app on port 8080...${NC}"
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Your app is responding on port 8080${NC}"
    echo "Response:"
    curl -s http://localhost:8080 | head -3
else
    echo -e "${RED}❌ No response from port 8080${NC}"
    echo "Make sure your app is running first"
fi

echo ""
echo -e "${YELLOW}Setting up proxy to capture HTTPS traffic...${NC}"

# Stop any old proxy containers
docker stop proxy-capture 2>/dev/null || true
docker rm proxy-capture 2>/dev/null || true

# Start mitmproxy on port 9084
docker run -d \
    --name proxy-capture \
    -p 9084:8080 \
    -p 9081:8081 \
    -v $(pwd)/captured:/captured \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --web-port 8081 \
        --web-host 0.0.0.0 \
        --save-stream-file /captured/traffic.mitm

sleep 3

if docker ps | grep -q proxy-capture; then
    echo -e "${GREEN}✅ Proxy is running${NC}"
    echo "  Proxy port: 9084"
    echo "  Web UI: http://localhost:9081"
else
    echo -e "${RED}❌ Proxy failed to start${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HOW TO CAPTURE YOUR APP'S HTTPS TRAFFIC${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Option 1: Set environment variables (if your app uses them)${NC}"
echo "Restart your app with:"
echo "  HTTP_PROXY=http://localhost:9084 HTTPS_PROXY=http://localhost:9084 your-app"
echo ""

echo -e "${YELLOW}Option 2: Modify your Go code temporarily${NC}"
echo "Add to your http.Client:"
cat << 'EOF'
  Transport: &http.Transport{
      Proxy: func(req *http.Request) (*url.URL, error) {
          return url.Parse("http://localhost:9084")
      },
  }
EOF
echo ""

echo -e "${YELLOW}Option 3: Use iptables (requires root)${NC}"
echo "Route all HTTPS traffic through proxy:"
echo "  sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 9084"
echo "  (Remember to remove later with: sudo iptables -t nat -F)"
echo ""

echo -e "${YELLOW}Option 4: Test with curl through proxy${NC}"
echo "Make requests through the proxy:"
echo "  curl -x http://localhost:9084 https://api.github.com"
echo "  curl -x http://localhost:9084 https://www.google.com"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MONITORING${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "View captured traffic:"
echo "  1. Web UI: http://localhost:9081"
echo "  2. Logs: docker logs proxy-capture"
echo "  3. Saved captures: ls -la captured/"
echo ""
echo -e "${GREEN}The proxy is now running and waiting for traffic!${NC}"
echo "Any HTTPS requests routed through localhost:9084 will be captured."