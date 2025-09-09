#!/bin/bash
# GET-IT-WORKING.sh - Just get something working NOW

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GETTING A WORKING SETUP NOW${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Clean EVERYTHING
echo -e "${YELLOW}Step 1: Cleaning everything...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
echo -e "${GREEN}✅ Clean${NC}"

# Step 2: Find free ports
echo ""
echo -e "${YELLOW}Step 2: Finding free ports...${NC}"
APP_PORT=3000
while lsof -i :$APP_PORT 2>/dev/null | grep -q LISTEN; do
    APP_PORT=$((APP_PORT + 1))
done
echo "App will use port: $APP_PORT"

PROXY_PORT=3100
while lsof -i :$PROXY_PORT 2>/dev/null | grep -q LISTEN; do
    PROXY_PORT=$((PROXY_PORT + 1))
done
echo "Proxy will use port: $PROXY_PORT"

# Step 3: Start the simplest possible proxy
echo ""
echo -e "${YELLOW}Step 3: Starting proxy on port $PROXY_PORT...${NC}"
docker run -d \
    --name proxy \
    -p $PROXY_PORT:8080 \
    mitmproxy/mitmproxy \
    mitmdump

sleep 2

if docker ps | grep -q proxy; then
    echo -e "${GREEN}✅ Proxy running${NC}"
else
    echo -e "${RED}Proxy failed${NC}"
    docker logs proxy
fi

# Step 4: Create and run the SIMPLEST web server
echo ""
echo -e "${YELLOW}Step 4: Starting simple web server on port $APP_PORT...${NC}"

# Use Python http.server - almost always works
docker run -d \
    --name web \
    -p $APP_PORT:8000 \
    -w /usr \
    python:3-alpine \
    python -m http.server 8000

sleep 3

if docker ps | grep -q web; then
    echo -e "${GREEN}✅ Web server running${NC}"
    
    # Test it
    echo ""
    echo -e "${YELLOW}Testing web server...${NC}"
    if curl -s http://localhost:$APP_PORT | head -5 | grep -q "Directory"; then
        echo -e "${GREEN}✅ Web server is responding!${NC}"
    else
        echo "Response:"
        curl -s http://localhost:$APP_PORT | head -10
    fi
else
    echo -e "${RED}Web server failed, trying alternative...${NC}"
    
    # Alternative: Use nginx
    docker rm web 2>/dev/null
    docker run -d \
        --name web \
        -p $APP_PORT:80 \
        nginx:alpine
    
    sleep 2
    
    if docker ps | grep -q web; then
        echo -e "${GREEN}✅ Nginx running instead${NC}"
    fi
fi

# Step 5: Now try a Go app if the simple server works
if docker ps | grep -q web; then
    echo ""
    echo -e "${YELLOW}Step 5: Also starting a Go app on port $((APP_PORT+1))...${NC}"
    
    # Create simple Go app
    mkdir -p working-app
    cat > working-app/main.go << 'EOF'
package main

import (
    "fmt"
    "net/http"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Go app is working!\n")
    })
    fmt.Println("Starting on :8080")
    http.ListenAndServe(":8080", nil)
}
EOF
    
    # Run with golang image
    docker run -d \
        --name goapp \
        -p $((APP_PORT+1)):8080 \
        -v $(pwd)/working-app:/app:ro \
        -w /app \
        -e HTTP_PROXY=http://172.17.0.1:$PROXY_PORT \
        -e HTTPS_PROXY=http://172.17.0.1:$PROXY_PORT \
        golang:alpine \
        go run main.go
    
    echo "Go app starting on port $((APP_PORT+1)) (may take 10-15 seconds)..."
fi

# Final status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FINAL STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

echo ""
echo -e "${GREEN}WORKING SERVICES:${NC}"
echo ""

if docker ps | grep -q proxy; then
    echo "✅ Proxy: http://localhost:$PROXY_PORT"
fi

if docker ps | grep -q web; then
    echo "✅ Web server: http://localhost:$APP_PORT"
fi

echo ""
echo -e "${YELLOW}Go app (wait 10-15 seconds): http://localhost:$((APP_PORT+1))${NC}"
echo ""
echo "Test the Go app in a moment with:"
echo "  curl http://localhost:$((APP_PORT+1))"
echo ""
echo "To test proxy capture:"
echo "  curl -x http://localhost:$PROXY_PORT https://www.google.com"
echo "  docker logs proxy"