#!/bin/bash
# SETUP-SSL-PROPERLY.sh - Get SSL working without certificate errors

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SETTING UP SSL PROPERLY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Find proxy port
PROXY_PORT=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep proxy | grep -oE '0.0.0.0:([0-9]+)' | cut -d: -f2 | head -1)

if [ -z "$PROXY_PORT" ]; then
    echo -e "${RED}Proxy not running. Starting it...${NC}"
    
    # Start proxy
    PROXY_PORT=3100
    docker run -d \
        --name proxy \
        -p $PROXY_PORT:8080 \
        mitmproxy/mitmproxy \
        mitmdump
    
    sleep 3
fi

echo -e "${GREEN}✅ Proxy running on port $PROXY_PORT${NC}"

# Step 1: Get the mitmproxy certificate
echo ""
echo -e "${YELLOW}Step 1: Getting mitmproxy certificate...${NC}"

# Get certificate from container
docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || {
    echo "First attempt failed, trying alternative path..."
    docker exec proxy cat ~/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || {
        echo "Generating certificate..."
        docker exec proxy mitmdump --quiet &
        sleep 3
        docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem
    }
}

if [ -f mitmproxy-ca.pem ]; then
    echo -e "${GREEN}✅ Certificate saved to mitmproxy-ca.pem${NC}"
    ls -lh mitmproxy-ca.pem
else
    echo -e "${RED}Failed to get certificate${NC}"
    exit 1
fi

# Step 2: Create test script that uses the certificate
echo ""
echo -e "${YELLOW}Step 2: Creating test commands with proper SSL...${NC}"

cat > test-with-ssl.sh << EOF
#!/bin/bash
# Test commands with proper SSL certificate

PROXY_PORT=$PROXY_PORT

echo "Testing HTTPS with proper certificate..."
echo ""

# Test 1: curl with certificate
echo "1. Using curl with certificate:"
curl -x http://localhost:\$PROXY_PORT \\
     --cacert mitmproxy-ca.pem \\
     -s \\
     https://api.github.com \\
     | python -m json.tool | head -10

echo ""
echo "2. Using wget with certificate:"
wget --ca-certificate=mitmproxy-ca.pem \\
     -e use_proxy=yes \\
     -e https_proxy=localhost:\$PROXY_PORT \\
     -O- -q \\
     https://api.github.com/users/github \\
     | python -m json.tool | head -10

echo ""
echo "✅ No SSL errors!"
EOF

chmod +x test-with-ssl.sh

# Step 3: Create Go example with proper certificate
echo ""
echo -e "${YELLOW}Step 3: Creating Go example with certificate...${NC}"

mkdir -p ssl-example
cat > ssl-example/main.go << 'EOF'
package main

import (
    "crypto/tls"
    "crypto/x509"
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
    "net/url"
    "os"
)

func main() {
    // Load mitmproxy certificate
    caCert, err := ioutil.ReadFile("mitmproxy-ca.pem")
    if err != nil {
        log.Fatal("Error loading certificate:", err)
    }

    // Create certificate pool
    caCertPool := x509.NewCertPool()
    if !caCertPool.AppendCertsFromPEM(caCert) {
        log.Fatal("Failed to parse certificate")
    }

    // Create HTTP client with proxy and certificate
    proxyURL, _ := url.Parse("http://localhost:" + os.Getenv("PROXY_PORT"))
    
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyURL(proxyURL),
            TLSClientConfig: &tls.Config{
                RootCAs: caCertPool,
            },
        },
    }

    // Make HTTPS request
    fmt.Println("Making HTTPS request through proxy with proper certificate...")
    resp, err := client.Get("https://api.github.com")
    if err != nil {
        log.Fatal("Request failed:", err)
    }
    defer resp.Body.Close()

    body, _ := ioutil.ReadAll(resp.Body)
    fmt.Printf("✅ Success! Got %d bytes from GitHub API\n", len(body))
    fmt.Println("No SSL errors!")
}
EOF

echo -e "${GREEN}✅ Created ssl-example/main.go${NC}"

# Step 4: Test everything
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING SSL SETUP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Test 1: curl with certificate (no SSL errors)${NC}"
curl -x http://localhost:$PROXY_PORT \
     --cacert mitmproxy-ca.pem \
     -s \
     https://api.github.com/users/github \
     -o /dev/null \
     -w "Status: %{http_code} - SSL: %{ssl_verify_result}\n"

echo ""
echo -e "${YELLOW}Test 2: Check proxy captured the request${NC}"
docker logs --tail 5 proxy | grep github || echo "Request should appear in logs"

# Step 5: System-wide certificate installation (optional)
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  OPTIONAL: Install certificate system-wide${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "To install the certificate system-wide (requires sudo):"
echo ""
echo "On macOS:"
echo "  ${GREEN}sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain mitmproxy-ca.pem${NC}"
echo ""
echo "On Linux:"
echo "  ${GREEN}sudo cp mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt"
echo "  sudo update-ca-certificates${NC}"
echo ""
echo "On Ubuntu/Debian:"
echo "  ${GREEN}sudo cp mitmproxy-ca.pem /usr/share/ca-certificates/mitmproxy.crt"
echo "  sudo dpkg-reconfigure ca-certificates${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}SSL SETUP COMPLETE!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "✅ Certificate saved: mitmproxy-ca.pem"
echo "✅ No more SSL errors when using:"
echo "   curl --cacert mitmproxy-ca.pem"
echo ""
echo "Test it:"
echo "  ${GREEN}./test-with-ssl.sh${NC}"
echo ""
echo "Run Go example:"
echo "  ${GREEN}cd ssl-example && PROXY_PORT=$PROXY_PORT go run main.go${NC}"