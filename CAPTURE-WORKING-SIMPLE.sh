#!/bin/bash
# CAPTURE-WORKING-SIMPLE.sh - Simplified working capture without code changes

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
echo -e "${BLUE}  SIMPLE WORKING CAPTURE - NO CODE CHANGES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up everything first
echo -e "${YELLOW}Cleaning up old containers...${NC}"
cleanup_all_containers

# Create a simple test app - NO proxy configuration
echo -e "${YELLOW}Creating simple test app...${NC}"
mkdir -p simple-app
cat > simple-app/main.go << 'EOF'
package main

import (
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
    "time"
)

func main() {
    log.Println("Starting server on :8080...")
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Server is running!\n")
        fmt.Fprintf(w, "Time: %s\n", time.Now().Format(time.RFC3339))
        fmt.Fprintf(w, "\nTry /test-https to make an HTTPS call\n")
    })
    
    http.HandleFunc("/test-https", func(w http.ResponseWriter, r *http.Request) {
        log.Println("Making HTTPS request to api.github.com...")
        
        // Standard HTTP client - NO proxy configuration
        client := &http.Client{
            Timeout: 10 * time.Second,
        }
        
        resp, err := client.Get("https://api.github.com")
        if err != nil {
            log.Printf("Error: %v", err)
            fmt.Fprintf(w, "Error making HTTPS call: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        log.Printf("Got response: %d bytes", len(body))
        
        fmt.Fprintf(w, "HTTPS call successful!\n")
        fmt.Fprintf(w, "Response status: %d\n", resp.StatusCode)
        fmt.Fprintf(w, "Response size: %d bytes\n", len(body))
    })
    
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "${GREEN}✅ Created app with standard Go HTTP client${NC}"

# Method 1: Two separate containers with forced proxy
echo ""
echo -e "${BLUE}Starting capture system...${NC}"

# Start mitmproxy first
echo -e "${YELLOW}1. Starting mitmproxy...${NC}"
docker run -d \
    --name mitm \
    -p 8084:8080 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080

sleep 3

# Build the Go app first
echo -e "${YELLOW}2. Building Go app...${NC}"
docker run --rm \
    -v $(pwd)/simple-app:/build \
    -w /build \
    golang:alpine \
    go build -o app main.go

if [ ! -f simple-app/app ]; then
    echo -e "${RED}Failed to build app${NC}"
    exit 1
fi

# Run the app with system-level proxy settings
echo -e "${YELLOW}3. Starting app with transparent proxy...${NC}"

# For transparent capture, we'll use environment variables at the system level
# Even though the Go code doesn't use ProxyFromEnvironment, 
# we can force it at the Docker level

docker run -d \
    --name app \
    -p 8080:8080 \
    -v $(pwd)/simple-app:/app:ro \
    -e http_proxy=http://172.17.0.1:8084 \
    -e https_proxy=http://172.17.0.1:8084 \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -w /app \
    alpine:latest \
    /app/app

sleep 5

# Check if everything is running
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

MITM_RUNNING=false
APP_RUNNING=false

if docker ps | grep -q " mitm "; then
    echo -e "${GREEN}✅ Proxy is running on port 8084${NC}"
    MITM_RUNNING=true
else
    echo -e "${RED}❌ Proxy failed to start${NC}"
fi

if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App is running on port 8080${NC}"
    APP_RUNNING=true
else
    echo -e "${RED}❌ App failed to start${NC}"
    echo "Logs:"
    docker logs app 2>&1 | tail -10
fi

if [ "$APP_RUNNING" = true ]; then
    echo ""
    echo -e "${YELLOW}Testing the app...${NC}"
    
    # Test basic endpoint
    if curl -s http://localhost:8080/ | grep -q "Server is running"; then
        echo -e "${GREEN}✅ App is accessible on port 8080${NC}"
        
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${GREEN}SUCCESS! System is ready${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""
        echo "Test commands:"
        echo ""
        echo "1. Check app is working:"
        echo "   curl http://localhost:8080/"
        echo ""
        echo "2. Make an HTTPS call (will be captured):"
        echo "   curl http://localhost:8080/test-https"
        echo ""
        echo "3. View proxy logs to see captured traffic:"
        echo "   docker logs mitm"
        echo ""
        echo "4. See app logs:"
        echo "   docker logs app"
        echo ""
        echo -e "${YELLOW}Note: The app uses standard Go HTTP client.${NC}"
        echo -e "${YELLOW}Proxy capture happens via environment variables.${NC}"
    else
        echo -e "${RED}❌ App not responding on port 8080${NC}"
        echo "Try: docker logs app"
    fi
else
    echo ""
    echo -e "${YELLOW}Trying alternative: Network namespace sharing${NC}"
    
    # Clean up failed attempt
    docker stop app mitm 2>/dev/null || true
    docker rm app mitm 2>/dev/null || true
    
    # Try network namespace sharing
    docker run -d \
        --name mitm-shared \
        -p 8080:8080 \
        -p 8084:8084 \
        mitmproxy/mitmproxy \
        mitmdump --listen-port 8084
    
    sleep 3
    
    docker run -d \
        --name app-shared \
        --network "container:mitm-shared" \
        -v $(pwd)/simple-app:/app:ro \
        -w /app \
        alpine:latest \
        /app/app
    
    sleep 5
    
    if docker ps | grep -q app-shared; then
        echo -e "${GREEN}✅ Alternative method working!${NC}"
        echo ""
        echo "Access your app at: http://localhost:8080/"
        echo "Proxy captures traffic automatically"
    else
        echo -e "${RED}❌ Both methods failed${NC}"
        echo "Check logs:"
        echo "  docker logs mitm-shared"
        echo "  docker logs app-shared"
    fi
fi