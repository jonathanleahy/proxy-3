#!/bin/bash
# Fix "unsupported protocol scheme" error on other machine

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Proxy Protocol Scheme Error${NC}"
echo "============================================"

# Check what's running
echo -e "${YELLOW}Current containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "proxy|app"

# Get the actual Docker bridge IP on this machine
echo -e "\n${YELLOW}Finding Docker bridge IP...${NC}"
DOCKER_IP=$(docker network inspect bridge --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
echo "Docker bridge IP: $DOCKER_IP"

# Check if proxy is accessible
echo -e "\n${YELLOW}Testing proxy accessibility...${NC}"
if curl -s -m 2 http://$DOCKER_IP:8084 2>/dev/null | head -c 1 | grep -q .; then
    echo -e "${GREEN}✅ Proxy is accessible at http://$DOCKER_IP:8084${NC}"
else
    echo -e "${RED}❌ Proxy not accessible at http://$DOCKER_IP:8084${NC}"
    echo "Trying localhost..."
    if curl -s -m 2 http://localhost:8084 2>/dev/null | head -c 1 | grep -q .; then
        echo -e "${GREEN}✅ Proxy is accessible at http://localhost:8084${NC}"
        DOCKER_IP="host.docker.internal"
    fi
fi

# Stop the app to reconfigure it
echo -e "\n${YELLOW}Stopping app to reconfigure...${NC}"
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true

# For your custom app, you need to set proxy variables correctly
echo -e "\n${YELLOW}Starting app with correct proxy settings...${NC}"
echo -e "${BLUE}Using proxy at: http://$DOCKER_IP:8084${NC}"

# If you're running your own app, use this template:
cat << 'EOF' > /tmp/run-with-proxy.sh
#!/bin/sh
# Set proxy environment variables
export HTTP_PROXY="http://${PROXY_HOST}:8084"
export HTTPS_PROXY="http://${PROXY_HOST}:8084"
export http_proxy="http://${PROXY_HOST}:8084"
export https_proxy="http://${PROXY_HOST}:8084"
export NO_PROXY="localhost,127.0.0.1"
export no_proxy="localhost,127.0.0.1"

# Trust the certificate if it exists
if [ -f /proxy/mitmproxy-ca.pem ]; then
    export SSL_CERT_FILE=/proxy/mitmproxy-ca.pem
    export NODE_EXTRA_CA_CERTS=/proxy/mitmproxy-ca.pem
    export REQUESTS_CA_BUNDLE=/proxy/mitmproxy-ca.pem
fi

echo "Proxy settings:"
echo "  HTTP_PROXY=$HTTP_PROXY"
echo "  HTTPS_PROXY=$HTTPS_PROXY"
echo "  SSL_CERT_FILE=$SSL_CERT_FILE"

# Run your application here
exec "$@"
EOF

chmod +x /tmp/run-with-proxy.sh

# Start app with the wrapper script
docker run -d \
    --name app \
    --rm \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -v /tmp/run-with-proxy.sh:/run-with-proxy.sh \
    -e PROXY_HOST="$DOCKER_IP" \
    -w /proxy/example-app \
    app-image \
    /run-with-proxy.sh go run main.go

echo -e "\n${GREEN}Solution for your custom app:${NC}"
echo "================================"
echo "If you're running a different application, make sure to:"
echo ""
echo "1. Set ALL proxy variables (some apps check different ones):"
echo "   export HTTP_PROXY=\"http://$DOCKER_IP:8084\""
echo "   export HTTPS_PROXY=\"http://$DOCKER_IP:8084\""
echo "   export http_proxy=\"http://$DOCKER_IP:8084\""
echo "   export https_proxy=\"http://$DOCKER_IP:8084\""
echo ""
echo "2. For Node.js apps, also set:"
echo "   export NODE_EXTRA_CA_CERTS=/proxy/mitmproxy-ca.pem"
echo ""
echo "3. For Python apps, also set:"
echo "   export REQUESTS_CA_BUNDLE=/proxy/mitmproxy-ca.pem"
echo "   export SSL_CERT_FILE=/proxy/mitmproxy-ca.pem"
echo ""
echo "4. For Go apps, also set:"
echo "   export SSL_CERT_FILE=/proxy/mitmproxy-ca.pem"
echo ""
echo "5. If using docker run directly:"
echo "   docker run -d \\"
echo "     -e HTTP_PROXY=\"http://$DOCKER_IP:8084\" \\"
echo "     -e HTTPS_PROXY=\"http://$DOCKER_IP:8084\" \\"
echo "     -e http_proxy=\"http://$DOCKER_IP:8084\" \\"
echo "     -e https_proxy=\"http://$DOCKER_IP:8084\" \\"
echo "     -v \$(pwd)/mitmproxy-ca.pem:/certs/ca.pem \\"
echo "     -e SSL_CERT_FILE=/certs/ca.pem \\"
echo "     your-app"
echo ""
echo -e "${YELLOW}Testing in 10 seconds...${NC}"
sleep 10

# Test
echo -e "\n${YELLOW}Testing if app is using proxy...${NC}"
if curl -s http://localhost:8080/health 2>/dev/null | grep -q "healthy"; then
    echo -e "${GREEN}✅ App is running${NC}"
    
    # Make a test request
    echo -e "\nMaking test request..."
    RESPONSE=$(curl -s http://localhost:8080/users 2>&1)
    if echo "$RESPONSE" | grep -q "unsupported protocol"; then
        echo -e "${RED}❌ Still getting protocol error${NC}"
        echo ""
        echo "Your app might be using a different proxy library."
        echo "Try setting lowercase proxy variables too:"
        echo "  export http_proxy=\"http://$DOCKER_IP:8084\""
        echo "  export https_proxy=\"http://$DOCKER_IP:8084\""
    else
        echo -e "${GREEN}✅ App is working with proxy!${NC}"
        echo "Response: $(echo "$RESPONSE" | head -c 100)..."
    fi
else
    echo -e "${YELLOW}⚠️ App not responding yet${NC}"
fi

echo -e "\n${BLUE}Debug Commands:${NC}"
echo "  docker logs app"
echo "  docker exec app env | grep -i proxy"
echo "  docker logs proxy"