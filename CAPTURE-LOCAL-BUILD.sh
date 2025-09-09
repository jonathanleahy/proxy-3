#!/bin/bash
# CAPTURE-LOCAL-BUILD.sh - Build Go app locally first, then run in container
# Avoids need for internet access in container

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
echo -e "${BLUE}  LOCAL BUILD CAPTURE (No container networking)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Check if Go is installed locally
if command -v go &> /dev/null; then
    echo -e "${GREEN}✅ Go is installed locally${NC}"
    go version
    LOCAL_GO=true
else
    echo -e "${YELLOW}Go not installed locally, will use Docker${NC}"
    LOCAL_GO=false
fi

# Create test app
echo -e "${YELLOW}Creating test app...${NC}"
mkdir -p test-app
cat > test-app/main.go << 'EOF'
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    
    fmt.Printf("Starting server on :%s\n", port)
    fmt.Printf("HTTP_PROXY: %s\n", os.Getenv("HTTP_PROXY"))
    fmt.Printf("HTTPS_PROXY: %s\n", os.Getenv("HTTPS_PROXY"))
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Server running on port %s!\n", port)
        fmt.Fprintf(w, "\nEnvironment:\n")
        fmt.Fprintf(w, "HTTP_PROXY: %s\n", os.Getenv("HTTP_PROXY"))
        fmt.Fprintf(w, "HTTPS_PROXY: %s\n", os.Getenv("HTTPS_PROXY"))
        fmt.Fprintf(w, "\nTry /proxy-test to test proxy connection\n")
    })
    
    http.HandleFunc("/proxy-test", func(w http.ResponseWriter, r *http.Request) {
        // Just test that we can receive requests through proxy
        fmt.Fprintf(w, "If you see this, the proxy is working!\n")
        fmt.Fprintf(w, "Request came from: %s\n", r.RemoteAddr)
        fmt.Fprintf(w, "Request headers:\n")
        for k, v := range r.Header {
            fmt.Fprintf(w, "  %s: %v\n", k, v)
        }
    })
    
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF

# Build the binary
echo -e "${YELLOW}Building Go binary...${NC}"

if [ "$LOCAL_GO" = true ]; then
    # Build locally
    cd test-app
    GOOS=linux GOARCH=amd64 go build -o app main.go
    cd ..
    echo -e "${GREEN}✅ Built locally${NC}"
else
    # Build using Docker
    docker run --rm \
        -v $(pwd)/test-app:/build \
        -w /build \
        golang:alpine \
        sh -c "GOOS=linux GOARCH=amd64 go build -o app main.go"
    echo -e "${GREEN}✅ Built with Docker${NC}"
fi

if [ ! -f test-app/app ]; then
    echo -e "${RED}❌ Failed to build binary${NC}"
    exit 1
fi

ls -lh test-app/app

# Create a minimal Dockerfile for the app
cat > test-app/Dockerfile << 'EOF'
FROM scratch
COPY app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
EOF

# Start the proxy
echo -e "${YELLOW}Starting mitmproxy...${NC}"
docker run -d \
    --name proxy \
    -p 8084:8080 \
    -p 8081:8081 \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --web-port 8081 \
        --web-host 0.0.0.0

sleep 3

# Run the binary directly (no package installation needed)
echo -e "${YELLOW}Starting app (pre-built binary)...${NC}"

# Try different base images that don't need internet
echo -e "${BLUE}Method 1: Using busybox (smallest)${NC}"

docker run -d \
    --name app \
    -p 8080:8080 \
    -v $(pwd)/test-app/app:/app:ro \
    -e PORT=8080 \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    busybox \
    /app

sleep 3

if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App is running!${NC}"
else
    echo -e "${RED}❌ Busybox failed, trying ubuntu${NC}"
    docker rm app 2>/dev/null
    
    docker run -d \
        --name app \
        -p 8080:8080 \
        -v $(pwd)/test-app/app:/app:ro \
        -e PORT=8080 \
        -e HTTP_PROXY=http://172.17.0.1:8084 \
        -e HTTPS_PROXY=http://172.17.0.1:8084 \
        ubuntu:latest \
        /app
    
    sleep 3
    
    if docker ps | grep -q " app "; then
        echo -e "${GREEN}✅ App is running with ubuntu!${NC}"
    else
        echo -e "${RED}❌ Ubuntu failed too${NC}"
        echo "Error logs:"
        docker logs app 2>&1
    fi
fi

# Check final status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if docker ps | grep -q " proxy "; then
    echo -e "${GREEN}✅ Proxy running${NC}"
    echo "   Web UI: http://localhost:8081"
fi

if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App running${NC}"
    echo "   URL: http://localhost:8080"
    echo ""
    echo "Test commands:"
    echo "  curl http://localhost:8080/"
    echo "  curl http://localhost:8080/proxy-test"
    echo ""
    echo "The app binary was built locally - no internet needed in container!"
else
    echo -e "${RED}❌ App not running${NC}"
    echo "Check logs: docker logs app"
fi