#!/bin/bash
# Run YOUR Go app with HTTPS capture - works on ANY machine

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🎯 Go App HTTPS Capture Solution${NC}"
echo "===================================="
echo ""

# Check if user provided their Go app command
if [ $# -eq 0 ]; then
    echo "Usage: $0 'your-go-app-command'"
    echo ""
    echo "Examples:"
    echo "  $0 'go run main.go'"
    echo "  $0 './my-compiled-app'"
    echo "  $0 'go run cmd/server/main.go -port 8080'"
    exit 1
fi

GO_APP_CMD="$*"

echo -e "${YELLOW}Your Go app command:${NC} $GO_APP_CMD"
echo ""

# First, try the original transparent mode
echo -e "${YELLOW}Attempting transparent mode...${NC}"
./start-proxy-system.sh --skip "$GO_APP_CMD"

# Check if transparent mode is working
sleep 5
if docker logs transparent-proxy 2>&1 | grep -q "Owner matching supported"; then
    echo -e "${GREEN}✅ Transparent mode working! Your Go app traffic is being captured.${NC}"
    echo "Captures will appear in ./captured/"
    echo ""
    echo "Monitor with: ./monitor-proxy.sh"
    exit 0
fi

echo -e "${YELLOW}⚠️ Transparent mode not working on this machine.${NC}"
echo -e "${YELLOW}Switching to proxy mode...${NC}"
echo ""

# Stop everything and use FINAL-CLEANUP-AND-RUN for proxy mode
docker compose down 2>/dev/null || true
docker stop transparent-proxy app mock-viewer 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true

# Use the working proxy mode solution
echo -e "${BLUE}Using proxy mode (works on all machines)...${NC}"

# Create a wrapper that forces Go to use proxy
cat << 'EOF' > /tmp/go-proxy-wrapper.sh
#!/bin/sh
# Force Go app to use proxy

# Try to get Docker host IP
if [ -f /etc/hosts ]; then
    HOST_IP=$(grep 'host.docker.internal' /etc/hosts | awk '{print $1}' | head -1)
fi
if [ -z "$HOST_IP" ]; then
    HOST_IP="172.17.0.1"  # Default Docker bridge
fi

# Set proxy for apps that respect env vars
export HTTP_PROXY="http://$HOST_IP:8084"
export HTTPS_PROXY="http://$HOST_IP:8084"
export http_proxy="http://$HOST_IP:8084"
export https_proxy="http://$HOST_IP:8084"
export NO_PROXY="localhost,127.0.0.1"

# Trust the certificate
if [ -f /proxy/mitmproxy-ca.pem ]; then
    export SSL_CERT_FILE=/proxy/mitmproxy-ca.pem
    export NODE_EXTRA_CA_CERTS=/proxy/mitmproxy-ca.pem
    export REQUESTS_CA_BUNDLE=/proxy/mitmproxy-ca.pem
fi

echo "Starting Go app with proxy settings:"
echo "  HTTP_PROXY=$HTTP_PROXY"
echo "  HTTPS_PROXY=$HTTPS_PROXY"

# Run the actual command
exec $@
EOF

chmod +x /tmp/go-proxy-wrapper.sh

# Start proxy
echo -e "${YELLOW}Starting proxy...${NC}"
docker run -d \
    --name proxy \
    --rm \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-image \
    sh -c "
        mkdir -p ~/.mitmproxy /captured
        mitmdump --quiet >/dev/null 2>&1 & sleep 3; kill \$! 2>/dev/null || true
        echo '✅ Proxy ready on port 8084'
        exec mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    "

sleep 5

# Get certificate
echo -e "${YELLOW}Setting up certificate...${NC}"
docker exec proxy sh -c "cat ~/.mitmproxy/mitmproxy-ca-cert.pem" > mitmproxy-ca.pem 2>/dev/null || true

# Start your Go app with the wrapper
echo -e "${YELLOW}Starting your Go app...${NC}"
docker run -d \
    --name app \
    --rm \
    -p 8080:8080 \
    -v $(pwd):/proxy \
    -v /tmp/go-proxy-wrapper.sh:/wrapper.sh:ro \
    -e GO_APP_CMD="$GO_APP_CMD" \
    -w /proxy \
    app-image \
    /wrapper.sh $GO_APP_CMD

# Start viewer
echo -e "${YELLOW}Starting viewer...${NC}"
docker run -d \
    --name viewer \
    --rm \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-history.html:/app/viewer-history.html:ro \
    -v $(pwd)/viewer-server.js:/app/viewer-server.js:ro \
    -e PORT=8090 \
    -e CAPTURED_DIR=/app/captured \
    viewer-image

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}✅ System Ready!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "If your Go app uses standard http.Client{}, it WON'T use the proxy automatically."
echo ""
echo "Your options:"
echo "1. Modify your Go code to use: http.ProxyFromEnvironment"
echo "2. Use http.Get() instead of custom client (uses default transport)"
echo "3. Force proxy in code: http.ProxyURL(url.Parse(\"http://172.17.0.1:8084\"))"
echo ""
echo "Endpoints:"
echo "  • Your app: http://localhost:8080"
echo "  • Viewer: http://localhost:8090/viewer"
echo "  • Proxy: http://localhost:8084"
echo ""
echo "If captures aren't appearing, your Go app isn't using the proxy."
echo "Check: docker logs proxy"