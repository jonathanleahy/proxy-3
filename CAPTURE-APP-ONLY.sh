#!/bin/bash
# CAPTURE-APP-ONLY.sh - Just run your Go app in a container with proxy settings
# Use this if you already have a proxy running elsewhere

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RUN YOUR GO APP IN CONTAINER${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Stop old app container if exists
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true

# Verify the app exists
APP_DIR="$HOME/temp"
if [ ! -d "$APP_DIR/aa" ]; then
    echo -e "${RED}❌ Directory not found: $APP_DIR/aa${NC}"
    echo "Creating test app instead..."
    
    mkdir -p test-app
    cat > test-app/main.go << 'EOF'
package main

import (
    "fmt"
    "net/http"
    "log"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello! Test app is working\n")
    })
    
    http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        // Make an HTTPS call
        resp, err := http.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error calling GitHub: %v\n", err)
            return
        }
        defer resp.Body.Close()
        fmt.Fprintf(w, "GitHub API returned: %d\n", resp.StatusCode)
    })
    
    log.Println("Starting server on :8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF
    APP_DIR="$(pwd)/test-app"
    APP_PATH="main.go"
    WORK_DIR="/app"
else
    echo -e "${GREEN}✅ Found app directory: $APP_DIR/aa${NC}"
    APP_PATH="aa/cmd/api/main.go"
    WORK_DIR="/app"
fi

# Get absolute path
TEMP_DIR="$(realpath $APP_DIR)"
echo -e "${BLUE}Mounting: $TEMP_DIR as /app${NC}"

# Check if proxy is running
PROXY_HOST="host.docker.internal"
PROXY_PORT="8084"

echo -e "${YELLOW}Starting Go app...${NC}"
echo "App location: $TEMP_DIR"
echo "Running: go run $APP_PATH"
echo ""

# Run the app
docker run -d \
    --name app \
    -p 8080:8080 \
    -v "$TEMP_DIR:/app:ro" \
    -e HTTP_PROXY=http://${PROXY_HOST}:${PROXY_PORT} \
    -e HTTPS_PROXY=http://${PROXY_HOST}:${PROXY_PORT} \
    -e NO_PROXY=localhost,127.0.0.1 \
    --add-host=host.docker.internal:host-gateway \
    -w "$WORK_DIR" \
    alpine:latest \
    sh -c "
        echo '📦 Installing Go...'
        apk add --no-cache go git ca-certificates
        
        echo ''
        echo '📁 Working directory:'
        pwd
        
        echo '📁 Directory contents:'
        ls -la
        
        echo ''
        echo '🔍 Looking for main.go:'
        find . -name 'main.go' -type f 2>/dev/null | head -5
        
        echo ''
        echo '🌐 Proxy settings:'
        echo \"HTTP_PROXY=\$HTTP_PROXY\"
        echo \"HTTPS_PROXY=\$HTTPS_PROXY\"
        
        echo ''
        echo '🚀 Starting app...'
        go run $APP_PATH
    "

echo -e "${YELLOW}Waiting for app to start...${NC}"
sleep 8

# Check if running
if docker ps | grep -q " app "; then
    echo ""
    echo -e "${GREEN}✅ App is running!${NC}"
    echo ""
    echo "Test with:"
    echo "  curl http://localhost:8080/"
    echo "  curl http://localhost:8080/test"
    echo ""
    echo "View logs:"
    echo "  docker logs app"
else
    echo ""
    echo -e "${RED}❌ App failed to start${NC}"
    echo ""
    echo -e "${YELLOW}Error logs:${NC}"
    docker logs app 2>&1 | tail -30
    echo ""
    echo -e "${YELLOW}Debug info:${NC}"
    echo "1. Check if ~/temp/aa/cmd/api/main.go exists"
    echo "2. Try running with test app:"
    echo "   docker rm app"
    echo "   ./CAPTURE-APP-ONLY.sh"
fi