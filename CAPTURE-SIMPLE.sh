#!/bin/bash
# CAPTURE-SIMPLE.sh - Simplest possible HTTPS capture setup
# Uses basic containers without complex networking

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

# Your Go app command - simplified path
GO_APP_PATH="${1:-/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIMPLE HTTPS CAPTURE (MOST COMPATIBLE)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Create capture directory
mkdir -p captured

# Step 1: Start basic mitmproxy
echo -e "${YELLOW}Starting mitmproxy...${NC}"

docker run -d \
    --name proxy-simple \
    -p 8084:8080 \
    -v $(pwd)/captured:/home/mitmproxy/captured \
    mitmproxy/mitmproxy \
    mitmdump --set confdir=/home/mitmproxy/.mitmproxy

echo -e "${YELLOW}Waiting for proxy...${NC}"
sleep 5

# Get certificate
echo -e "${YELLOW}Getting certificate...${NC}"
docker exec proxy-simple cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || echo "Certificate will be generated on first use"

# Step 2: Test if we can run a basic Go app
echo -e "${YELLOW}Testing Go app setup...${NC}"

# First, let's just try to list what's in the temp directory
echo -e "${BLUE}Checking if ~/temp exists on host:${NC}"
if [ -d ~/temp ]; then
    echo -e "${GREEN}✅ Found ~/temp${NC}"
    ls -la ~/temp/aa/cmd/api/ 2>/dev/null || echo "Could not list ~/temp/aa/cmd/api/"
else
    echo -e "${RED}❌ ~/temp not found${NC}"
    echo "Creating a test app instead..."
    
    # Create a simple test app
    mkdir -p test-app
    cat > test-app/main.go << 'EOF'
package main

import (
    "fmt"
    "net/http"
    "io/ioutil"
    "crypto/tls"
)

func main() {
    fmt.Println("Test app starting on :8080")
    
    // Test handler
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from test app!\n")
    })
    
    // Test HTTPS call handler
    http.HandleFunc("/test-https", func(w http.ResponseWriter, r *http.Request) {
        // Create client that accepts any certificate
        client := &http.Client{
            Transport: &http.Transport{
                TLSClientConfig: &tls.Config{
                    InsecureSkipVerify: true,
                },
                Proxy: http.ProxyFromEnvironment,
            },
        }
        
        resp, err := client.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "Got response: %d bytes\n", len(body))
    })
    
    fmt.Println("Server starting on :8080...")
    http.ListenAndServe(":8080", nil)
}
EOF
    GO_APP_PATH="/app/main.go"
fi

# Step 3: Run app with explicit proxy
echo -e "${YELLOW}Starting Go app with proxy...${NC}"

# Determine what to mount
if [ -d ~/temp ]; then
    MOUNT_VOL="-v $HOME/temp:/temp:ro"
    WORK_DIR="/temp/aa/cmd/api"
    GO_CMD="go run main.go"
else
    MOUNT_VOL="-v $(pwd)/test-app:/app:ro"
    WORK_DIR="/app"
    GO_CMD="go run main.go"
fi

docker run -d \
    --name app-simple \
    -p 8080:8080 \
    $MOUNT_VOL \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -w $WORK_DIR \
    --add-host=host.docker.internal:host-gateway \
    alpine:latest \
    sh -c "
        echo 'Installing Go...'
        apk add --no-cache go git
        
        echo 'Testing Go installation...'
        go version
        
        echo 'Checking working directory...'
        pwd
        ls -la
        
        echo 'Starting app with proxy...'
        echo 'HTTP_PROXY=${HTTP_PROXY}'
        echo 'HTTPS_PROXY=${HTTPS_PROXY}'
        
        $GO_CMD
    "

echo -e "${YELLOW}Waiting for app to start...${NC}"
sleep 10

# Check status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

echo -e "${YELLOW}Proxy status:${NC}"
if docker ps | grep -q proxy-simple; then
    echo -e "${GREEN}✅ Proxy is running${NC}"
else
    echo -e "${RED}❌ Proxy failed${NC}"
    docker logs proxy-simple
fi

echo -e "${YELLOW}App status:${NC}"
if docker ps | grep -q app-simple; then
    echo -e "${GREEN}✅ App is running${NC}"
    echo ""
    echo -e "${GREEN}Test commands:${NC}"
    echo "1. Test app: curl http://localhost:8080/"
    echo "2. Test HTTPS capture: curl http://localhost:8080/test-https"
    echo "3. Check proxy logs: docker logs proxy-simple"
    echo "4. Check app logs: docker logs app-simple"
else
    echo -e "${RED}❌ App failed to start${NC}"
    echo ""
    echo -e "${YELLOW}App logs:${NC}"
    docker logs app-simple
fi

echo ""
echo -e "${YELLOW}To test HTTPS capture directly:${NC}"
echo "docker exec app-simple sh -c 'HTTP_PROXY=http://172.17.0.1:8084 HTTPS_PROXY=http://172.17.0.1:8084 wget -O- https://api.github.com'"