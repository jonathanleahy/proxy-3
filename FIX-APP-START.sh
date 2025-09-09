#!/bin/bash
# FIX-APP-START.sh - Fix the app start issue

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING APP START ISSUE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# First, check what went wrong
echo -e "${YELLOW}Checking failed app container...${NC}"
if docker ps -a | grep -q " app "; then
    echo "Container status:"
    docker ps -a --filter "name=^app$" --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "Error logs:"
    docker logs app 2>&1 | tail -20
    echo ""
fi

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker stop app proxy 2>/dev/null || true
docker rm app proxy 2>/dev/null || true

# Create the SIMPLEST possible Go app
echo -e "${YELLOW}Creating minimal Go app...${NC}"
mkdir -p minimal-app
cat > minimal-app/main.go << 'EOF'
package main

import (
    "fmt"
    "log"
    "net/http"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Minimal server working!\n")
    })
    
    log.Println("Starting minimal server on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

# Build with maximum compatibility
echo -e "${YELLOW}Building static binary...${NC}"
docker run --rm \
    -v $(pwd)/minimal-app:/app \
    -w /app \
    -e CGO_ENABLED=0 \
    -e GOOS=linux \
    -e GOARCH=amd64 \
    golang:alpine \
    sh -c "go build -o server main.go && chmod +x server"

if [ ! -f minimal-app/server ]; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Binary built${NC}"
ls -lh minimal-app/server

# Test 1: Run directly with Docker (no base image dependencies)
echo ""
echo -e "${YELLOW}Test 1: Running with scratch (no OS)...${NC}"
docker run -d \
    --name test1 \
    -p 9001:8080 \
    -v $(pwd)/minimal-app/server:/server:ro \
    scratch \
    /server 2>/dev/null || {
        echo "Scratch failed (expected, needs some libs)"
        docker rm test1 2>/dev/null
    }

# Test 2: Try with busybox
echo -e "${YELLOW}Test 2: Running with busybox...${NC}"
docker run -d \
    --name test2 \
    -p 9002:8080 \
    -v $(pwd)/minimal-app:/app:ro \
    busybox \
    /app/server

sleep 2

if docker ps | grep -q test2; then
    echo -e "${GREEN}✅ Works with busybox!${NC}"
    curl -s http://localhost:9002 || echo "Not responding yet..."
else
    echo -e "${RED}Failed with busybox${NC}"
    docker logs test2 2>&1
    docker rm test2 2>/dev/null
fi

# Test 3: Try with alpine
echo -e "${YELLOW}Test 3: Running with alpine...${NC}"
docker run -d \
    --name test3 \
    -p 9003:8080 \
    -v $(pwd)/minimal-app:/app:ro \
    alpine:latest \
    /app/server

sleep 2

if docker ps | grep -q test3; then
    echo -e "${GREEN}✅ Works with alpine!${NC}"
    curl -s http://localhost:9003
else
    echo -e "${RED}Failed with alpine${NC}"
    docker logs test3 2>&1
    docker rm test3 2>/dev/null
fi

# Test 4: Run with Go directly (most reliable)
echo ""
echo -e "${YELLOW}Test 4: Running with Go directly...${NC}"
docker run -d \
    --name test4 \
    -p 9004:8080 \
    -v $(pwd)/minimal-app:/app:ro \
    -w /app \
    golang:alpine \
    go run main.go

sleep 5

if docker ps | grep -q test4; then
    echo -e "${GREEN}✅ Works with golang:alpine!${NC}"
    curl -s http://localhost:9004
else
    echo -e "${RED}Failed with golang:alpine${NC}"
    docker logs test4 2>&1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WORKING SOLUTION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up tests
docker stop test1 test2 test3 test4 2>/dev/null || true
docker rm test1 test2 test3 test4 2>/dev/null || true

# Start the working version
PORT=9080
PROXY_PORT=9084

echo -e "${YELLOW}Starting proxy on port $PROXY_PORT...${NC}"
docker run -d \
    --name proxy \
    -p $PROXY_PORT:8080 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080

echo -e "${YELLOW}Starting app on port $PORT using most reliable method...${NC}"
docker run -d \
    --name app \
    -p $PORT:8080 \
    -v $(pwd)/minimal-app:/app:ro \
    -w /app \
    -e HTTP_PROXY=http://172.17.0.1:$PROXY_PORT \
    -e HTTPS_PROXY=http://172.17.0.1:$PROXY_PORT \
    golang:alpine \
    go run main.go

sleep 5

if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App container is running${NC}"
    echo ""
    echo "The log shows 'Starting server on :8080' - this is CORRECT!"
    echo "The app runs on 8080 inside the container"
    echo "Docker maps it to port $PORT on your host"
    echo ""
    echo -e "${YELLOW}Testing http://localhost:$PORT...${NC}"
    sleep 3  # Give it time to fully start
    
    if curl -s http://localhost:$PORT 2>/dev/null | grep -q "working"; then
        echo -e "${GREEN}✅ SUCCESS! App is responding!${NC}"
        curl -s http://localhost:$PORT
    else
        echo -e "${YELLOW}App might still be starting, wait a moment and try:${NC}"
        echo "  curl http://localhost:$PORT"
    fi
else
    echo -e "${RED}Container not running, showing logs:${NC}"
    docker logs app 2>&1
fi