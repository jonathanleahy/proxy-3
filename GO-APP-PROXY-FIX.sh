#!/bin/bash
# Fix Go app proxy issues - for ANY Go application

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Go Application Proxy Configuration Fix${NC}"
echo "============================================"
echo ""
echo -e "${YELLOW}The Issue:${NC}"
echo "Your Go app is getting 'unsupported protocol scheme' because:"
echo "1. Go's http.Client doesn't automatically use proxy env vars"
echo "2. The proxy URL might be malformed or empty"
echo ""

# Find Docker bridge IP
DOCKER_IP=$(docker network inspect bridge --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
echo -e "${GREEN}Docker bridge IP: $DOCKER_IP${NC}"

# Test proxy
echo -e "\n${YELLOW}Testing proxy accessibility...${NC}"
if curl -s -m 2 http://$DOCKER_IP:8084 2>&1 | grep -q "Proxy"; then
    echo -e "${GREEN}✅ Proxy is running at http://$DOCKER_IP:8084${NC}"
    PROXY_URL="http://$DOCKER_IP:8084"
elif curl -s -m 2 http://localhost:8084 2>&1 | grep -q "Proxy"; then
    echo -e "${GREEN}✅ Proxy is running at http://localhost:8084${NC}"
    PROXY_URL="http://localhost:8084"
    DOCKER_IP="host.docker.internal"
else
    echo -e "${RED}❌ Proxy not accessible${NC}"
    echo "Start the proxy first with: ./FINAL-CLEANUP-AND-RUN.sh"
    exit 1
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}SOLUTION 1: Run Your Go App with Proxy${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "If your Go app uses standard http.Client, it needs http.ProxyFromEnvironment."
echo "Most Go apps DON'T have this by default!"
echo ""
echo -e "${YELLOW}Option A: Modify your Go app code${NC}"
echo "Add this to your HTTP client creation:"
echo ""
cat << 'EOF'
import (
    "net/http"
    "net/url"
    "os"
)

// Create HTTP client that respects proxy settings
func createHTTPClient() *http.Client {
    // Option 1: Use environment variables automatically
    return &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment,
        },
        Timeout: 10 * time.Second,
    }
    
    // Option 2: Force specific proxy
    proxyURL, _ := url.Parse("http://172.17.0.1:8084")
    return &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyURL(proxyURL),
        },
    }
}
EOF

echo ""
echo -e "${YELLOW}Option B: Use Go's built-in proxy support${NC}"
echo "Run your app with these EXACT environment variables:"
echo ""
echo -e "${GREEN}export HTTP_PROXY=\"$PROXY_URL\"${NC}"
echo -e "${GREEN}export HTTPS_PROXY=\"$PROXY_URL\"${NC}"
echo -e "${GREEN}export http_proxy=\"$PROXY_URL\"${NC}"
echo -e "${GREEN}export https_proxy=\"$PROXY_URL\"${NC}"
echo ""

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}SOLUTION 2: Docker Run Command${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Run your Go app container like this:"
echo ""
cat << EOF
docker run -d \\
    --name your-app \\
    -e HTTP_PROXY="$PROXY_URL" \\
    -e HTTPS_PROXY="$PROXY_URL" \\
    -e http_proxy="$PROXY_URL" \\
    -e https_proxy="$PROXY_URL" \\
    -e NO_PROXY="localhost,127.0.0.1" \\
    -v \$(pwd)/mitmproxy-ca.pem:/certs/ca.pem:ro \\
    -e SSL_CERT_FILE=/certs/ca.pem \\
    your-go-app-image
EOF

echo ""
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}SOLUTION 3: Wrapper Script (RECOMMENDED)${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Creating a wrapper script that forces proxy usage..."

cat << EOF > go-proxy-wrapper.sh
#!/bin/sh
# Go App Proxy Wrapper

# Set all proxy variants (Go checks different ones)
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export NO_PROXY="localhost,127.0.0.1"
export no_proxy="localhost,127.0.0.1"

# For HTTPS certificate trust
if [ -f /certs/ca.pem ]; then
    export SSL_CERT_FILE=/certs/ca.pem
    export CA_BUNDLE=/certs/ca.pem
fi

echo "Starting Go app with proxy settings:"
echo "  HTTP_PROXY=\$HTTP_PROXY"
echo "  HTTPS_PROXY=\$HTTPS_PROXY"

# Run the actual Go app
exec "\$@"
EOF

chmod +x go-proxy-wrapper.sh

echo -e "${GREEN}✅ Created go-proxy-wrapper.sh${NC}"
echo ""
echo "Use it like this:"
echo "  docker run -v \$(pwd)/go-proxy-wrapper.sh:/wrapper.sh your-image /wrapper.sh your-app"
echo ""

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}SOLUTION 4: Test with curl in container${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "First, verify the proxy works from inside your container:"
echo ""
echo "  docker exec your-app-container sh -c \\"
echo "    'HTTP_PROXY=\"$PROXY_URL\" curl -v http://example.com'"
echo ""
echo "If this works but your Go app doesn't, the app isn't using proxy settings."
echo ""

echo -e "\n${RED}⚠️  IMPORTANT for Go Apps:${NC}"
echo "================================"
echo "1. Go's default http.Client does NOT use proxy env vars!"
echo "2. You must either:"
echo "   - Use http.ProxyFromEnvironment in your code"
echo "   - Or use DefaultTransport which includes it"
echo "3. Some Go HTTP libraries ignore proxy settings entirely"
echo ""
echo "Quick test - run this Go code in your container:"
echo ""
cat << 'EOF'
package main
import (
    "fmt"
    "net/http"
    "os"
)
func main() {
    fmt.Printf("HTTP_PROXY=%s\n", os.Getenv("HTTP_PROXY"))
    
    // This WILL use proxy
    resp, err := http.Get("http://example.com")
    if err != nil {
        fmt.Printf("Error: %v\n", err)
    } else {
        fmt.Printf("Success: %d\n", resp.StatusCode)
    }
}
EOF

echo ""
echo -e "${YELLOW}Still having issues?${NC}"
echo "Try running your app with explicit proxy in code:"
echo "  proxyURL, _ := url.Parse(\"$PROXY_URL\")"
echo "  client := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}}"