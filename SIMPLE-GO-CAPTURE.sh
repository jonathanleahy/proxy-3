#!/bin/bash
# SIMPLE solution to capture HTTPS traffic from any Go app

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🎯 Simple Go App HTTPS Capture${NC}"
echo "================================"
echo ""

# Clean up everything
docker stop proxy app viewer 2>/dev/null || true
docker rm proxy app viewer 2>/dev/null || true

# 1. Start the proxy
echo -e "${YELLOW}Starting proxy...${NC}"
docker run -d \
    --name proxy \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-3-transparent-proxy \
    sh -c "
        mkdir -p ~/.mitmproxy
        mitmdump --quiet >/dev/null 2>&1 & sleep 2; kill \$! 2>/dev/null || true
        exec mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    "

sleep 5

# 2. Get the certificate
echo -e "${YELLOW}Getting certificate...${NC}"
docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > ca.pem 2>/dev/null || true

# 3. Run YOUR Go app with proxy
echo -e "\n${GREEN}Now run your Go app with these settings:${NC}"
echo "================================"
echo ""
echo "Option 1 - If running directly:"
echo -e "${BLUE}export HTTP_PROXY=http://localhost:8084${NC}"
echo -e "${BLUE}export HTTPS_PROXY=http://localhost:8084${NC}"
echo -e "${BLUE}export SSL_CERT_FILE=$(pwd)/ca.pem${NC}"
echo -e "${BLUE}./your-go-app${NC}"
echo ""
echo "Option 2 - If using Docker:"
cat << 'EOF'
docker run \
    -e HTTP_PROXY=http://host.docker.internal:8084 \
    -e HTTPS_PROXY=http://host.docker.internal:8084 \
    -v $(pwd)/ca.pem:/ca.pem \
    -e SSL_CERT_FILE=/ca.pem \
    your-go-app-image
EOF
echo ""
echo "Option 3 - Force proxy in your Go code (GUARANTEED TO WORK):"
cat << 'EOF'
// Add this to your Go app:
import (
    "net/http"
    "net/url"
    "crypto/tls"
)

// Create client that MUST use proxy
proxyURL, _ := url.Parse("http://localhost:8084")
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyURL(proxyURL),
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: true, // For testing only
        },
    },
}

// Now use this client for all requests
resp, err := client.Get("https://api.example.com/data")
EOF
echo ""
echo -e "${GREEN}✅ Proxy is running on port 8084${NC}"
echo -e "${GREEN}✅ Captures will appear in: ./captured/${NC}"
echo ""
echo "View captures: ls -la captured/"