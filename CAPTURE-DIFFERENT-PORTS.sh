#!/bin/bash
# CAPTURE-DIFFERENT-PORTS.sh - Use different ports to avoid conflicts
# Uses ports 9084, 9081, 9080, 9090 instead of 80xx

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HTTPS CAPTURE (ALTERNATIVE PORTS)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Using ports: 9084 (proxy), 9081 (web), 9080 (app), 9090 (viewer)${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Verify the app exists
APP_DIR="$HOME/temp/aa"
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}❌ Directory not found: $APP_DIR${NC}"
    echo "Creating test app instead..."
    
    mkdir -p test-app
    cat > test-app/main.go << 'EOF'
package main

import (
    "fmt"
    "net/http"
    "log"
    "io/ioutil"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello! App is working on port 9080\n")
    })
    
    http.HandleFunc("/test-https", func(w http.ResponseWriter, r *http.Request) {
        resp, err := http.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "GitHub API response: %d bytes\n", len(body))
    })
    
    log.Println("Starting server on :8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF
    USE_TEST_APP=true
else
    echo -e "${GREEN}✅ Found app directory: $APP_DIR${NC}"
    USE_TEST_APP=false
fi

# Create capture directory
mkdir -p captured

# Step 1: Start mitmproxy on different ports
echo -e "${YELLOW}Starting mitmproxy on port 9084...${NC}"

docker run -d \
    --name proxy-alt \
    -p 9084:8080 \
    -p 9081:8081 \
    -v $(pwd)/captured:/home/mitmproxy/captured \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --web-port 8081 \
        --web-host 0.0.0.0 \
        --set confdir=/home/mitmproxy/.mitmproxy \
        --set save_stream_file=/home/mitmproxy/captured/stream.mitm

echo -e "${YELLOW}Waiting for proxy to start...${NC}"
sleep 5

# Get certificate
echo -e "${YELLOW}Getting certificate...${NC}"
docker exec proxy-alt cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# Step 2: Run your Go app
echo -e "${YELLOW}Starting Go app on port 9080...${NC}"

if [ "$USE_TEST_APP" = true ]; then
    MOUNT_DIR="$(pwd)/test-app"
    WORK_DIR="/app"
    GO_CMD="go run main.go"
else
    MOUNT_DIR="$(realpath $HOME/temp)"
    WORK_DIR="/workspace/aa/cmd/api"
    GO_CMD="go run main.go"
fi

docker run -d \
    --name app-alt \
    -p 9080:8080 \
    -v "$MOUNT_DIR:/workspace:ro" \
    -v "$(pwd)/mitmproxy-ca.pem:/ca.pem:ro" \
    -e HTTP_PROXY=http://host.docker.internal:9084 \
    -e HTTPS_PROXY=http://host.docker.internal:9084 \
    -e SSL_CERT_FILE=/ca.pem \
    --add-host=host.docker.internal:host-gateway \
    -w "$WORK_DIR" \
    alpine:latest \
    sh -c "
        echo '📦 Installing Go...'
        apk add --no-cache go git ca-certificates curl
        
        echo '📁 Working from:'
        pwd
        ls -la
        
        echo '🔐 Installing certificate...'
        cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates
        
        echo '🚀 Starting app with proxy...'
        echo \"HTTP_PROXY=\$HTTP_PROXY\"
        echo \"HTTPS_PROXY=\$HTTPS_PROXY\"
        
        $GO_CMD
    "

echo -e "${YELLOW}Waiting for app to start...${NC}"
sleep 10

# Step 3: Start viewer
echo -e "${YELLOW}Starting capture viewer on port 9090...${NC}"

docker run -d \
    --name viewer-alt \
    -p 9090:80 \
    -v $(pwd)/captured:/usr/share/nginx/html:ro \
    nginx:alpine

# Check status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if docker ps | grep -q proxy-alt; then
    echo -e "${GREEN}✅ Proxy running on port 9084${NC}"
    echo "   Web interface: http://localhost:9081"
else
    echo -e "${RED}❌ Proxy failed${NC}"
fi

if docker ps | grep -q app-alt; then
    echo -e "${GREEN}✅ App running on port 9080${NC}"
    echo "   Your app: http://localhost:9080"
else
    echo -e "${RED}❌ App failed${NC}"
    echo "Logs:"
    docker logs app-alt 2>&1 | tail -10
fi

if docker ps | grep -q viewer-alt; then
    echo -e "${GREEN}✅ Viewer running on port 9090${NC}"
    echo "   View captures: http://localhost:9090"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}TEST COMMANDS:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Test app:"
echo "   curl http://localhost:9080/"
echo ""
echo "2. Test HTTPS capture:"
echo "   curl http://localhost:9080/test-https"
echo ""
echo "3. View mitmproxy web UI:"
echo "   http://localhost:9081"
echo ""
echo "4. Check captures:"
echo "   ls -la captured/"