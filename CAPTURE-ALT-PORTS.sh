#!/bin/bash
# CAPTURE-ALT-PORTS.sh - Use alternative ports to avoid conflicts
# Uses ports 9080, 9084 instead of 8080, 8084

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
echo -e "${BLUE}  CAPTURE WITH ALTERNATIVE PORTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Using ports 9080 (app) and 9084 (proxy)${NC}"
echo "Since port 8080 is already in use"
echo ""

# Clean up old containers
cleanup_all_containers

# Kill anything on our alternative ports
echo -e "${YELLOW}Checking alternative ports...${NC}"
for port in 9080 9084; do
    if lsof -i :$port 2>/dev/null | grep -q LISTEN; then
        echo "Port $port is in use, trying to free it..."
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
    fi
done

# Create test app
echo -e "${YELLOW}Creating test app...${NC}"
mkdir -p alt-app
cat > alt-app/main.go << 'EOF'
package main

import (
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("APP_PORT")
    if port == "" {
        port = "9080"
    }
    
    log.Printf("Starting server on :%s...", port)
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Server running on port %s!\n", port)
        fmt.Fprintf(w, "\nTest endpoints:\n")
        fmt.Fprintf(w, "  /test-github - Make HTTPS call to GitHub\n")
        fmt.Fprintf(w, "  /test-google - Make HTTPS call to Google\n")
    })
    
    http.HandleFunc("/test-github", func(w http.ResponseWriter, r *http.Request) {
        log.Println("Making HTTPS call to GitHub...")
        
        resp, err := http.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "GitHub API Response:\n")
        fmt.Fprintf(w, "Status: %d\n", resp.StatusCode)
        fmt.Fprintf(w, "Size: %d bytes\n", len(body))
    })
    
    http.HandleFunc("/test-google", func(w http.ResponseWriter, r *http.Request) {
        log.Println("Making HTTPS call to Google...")
        
        resp, err := http.Get("https://www.google.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "Google Response:\n")
        fmt.Fprintf(w, "Status: %d\n", resp.StatusCode)
        fmt.Fprintf(w, "Size: %d bytes\n", len(body))
    })
    
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF

# Build the app
echo -e "${YELLOW}Building Go app...${NC}"
docker run --rm \
    -v $(pwd)/alt-app:/build \
    -w /build \
    golang:alpine \
    go build -o app main.go

if [ ! -f alt-app/app ]; then
    echo -e "${RED}Failed to build app${NC}"
    exit 1
fi

echo -e "${GREEN}✅ App built successfully${NC}"

# Start proxy on port 9084
echo -e "${YELLOW}Starting proxy on port 9084...${NC}"
docker run -d \
    --name proxy-alt \
    -p 9084:8080 \
    -p 9081:8081 \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --web-port 8081 \
        --web-host 0.0.0.0

sleep 3

# Start app on port 9080
echo -e "${YELLOW}Starting app on port 9080...${NC}"
docker run -d \
    --name app-alt \
    -p 9080:9080 \
    -v $(pwd)/alt-app:/app:ro \
    -e APP_PORT=9080 \
    -e HTTP_PROXY=http://172.17.0.1:9084 \
    -e HTTPS_PROXY=http://172.17.0.1:9084 \
    -w /app \
    alpine:latest \
    /app/app

sleep 3

# Check status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

SUCCESS=true

if docker ps | grep -q proxy-alt; then
    echo -e "${GREEN}✅ Proxy running on port 9084${NC}"
    echo "   Web UI: http://localhost:9081"
else
    echo -e "${RED}❌ Proxy failed${NC}"
    SUCCESS=false
fi

if docker ps | grep -q app-alt; then
    echo -e "${GREEN}✅ App running on port 9080${NC}"
else
    echo -e "${RED}❌ App failed${NC}"
    docker logs app-alt 2>&1 | tail -10
    SUCCESS=false
fi

if [ "$SUCCESS" = true ]; then
    echo ""
    echo -e "${YELLOW}Testing the app...${NC}"
    
    if curl -s http://localhost:9080/ 2>/dev/null | grep -q "Server running"; then
        echo -e "${GREEN}✅ App is accessible!${NC}"
        
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${GREEN}SUCCESS! System is working${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""
        echo "Access your app at: http://localhost:9080"
        echo ""
        echo "Test HTTPS capture:"
        echo "  curl http://localhost:9080/test-github"
        echo "  curl http://localhost:9080/test-google"
        echo ""
        echo "View proxy logs:"
        echo "  docker logs proxy-alt"
        echo ""
        echo "View proxy web UI:"
        echo "  http://localhost:9081"
    else
        echo -e "${RED}❌ App not responding${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Check what's using port 8080:"
    echo "   lsof -i :8080"
    echo ""
    echo "2. Stop whatever is using it, or"
    echo "3. Edit this script to use different ports"
fi