#!/bin/bash
# CAPTURE-OFFLINE.sh - Works without internet access to Alpine repos
# Uses golang image which already has Go installed

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
echo -e "${BLUE}  OFFLINE HTTPS CAPTURE (No Alpine repos needed)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Create test app
echo -e "${YELLOW}Creating test app...${NC}"
mkdir -p test-app
cat > test-app/main.go << 'EOF'
package main

import (
    "crypto/tls"
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
    "os"
)

func main() {
    // Show proxy settings
    fmt.Println("Starting with proxy settings:")
    fmt.Printf("HTTP_PROXY: %s\n", os.Getenv("HTTP_PROXY"))
    fmt.Printf("HTTPS_PROXY: %s\n", os.Getenv("HTTPS_PROXY"))
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "App is running!\n")
        fmt.Fprintf(w, "Try /test to make an HTTPS call\n")
    })
    
    http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        client := &http.Client{
            Transport: &http.Transport{
                Proxy: http.ProxyFromEnvironment,
                TLSClientConfig: &tls.Config{
                    InsecureSkipVerify: true,
                },
            },
        }
        
        // Try a simple HTTPS request
        resp, err := client.Get("https://www.google.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "HTTPS call successful!\n")
        fmt.Fprintf(w, "Response status: %d\n", resp.StatusCode)
        fmt.Fprintf(w, "Response size: %d bytes\n", len(body))
    })
    
    log.Println("Server starting on :8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

# Create capture directory
mkdir -p captured

# Try different approaches
echo ""
echo -e "${BLUE}Trying Method 1: Using golang:alpine image${NC}"
echo "════════════════════════════════════════════"

# Start proxy first
docker run -d \
    --name proxy \
    -p 8084:8080 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080

sleep 3

# Try with golang:alpine (has Go pre-installed)
docker run -d \
    --name app-golang \
    -p 8080:8080 \
    -v $(pwd)/test-app:/app:ro \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    -w /app \
    golang:alpine \
    go run main.go

sleep 5

if docker ps | grep -q app-golang; then
    echo -e "${GREEN}✅ Method 1 worked!${NC}"
    echo ""
    echo "Test with:"
    echo "  curl http://localhost:8080/"
    echo "  curl http://localhost:8080/test"
    echo ""
    echo "View proxy logs:"
    echo "  docker logs proxy"
else
    echo -e "${RED}❌ Method 1 failed${NC}"
    docker logs app-golang 2>&1 | head -10
    
    # Clean up for next attempt
    docker stop app-golang proxy 2>/dev/null || true
    docker rm app-golang proxy 2>/dev/null || true
    
    echo ""
    echo -e "${BLUE}Trying Method 2: Using golang:latest image${NC}"
    echo "════════════════════════════════════════════"
    
    # Start proxy again
    docker run -d \
        --name proxy \
        -p 8084:8080 \
        mitmproxy/mitmproxy \
        mitmdump --listen-port 8080
    
    sleep 3
    
    # Try with golang:latest
    docker run -d \
        --name app-golang \
        -p 8080:8080 \
        -v $(pwd)/test-app:/app:ro \
        -e HTTP_PROXY=http://172.17.0.1:8084 \
        -e HTTPS_PROXY=http://172.17.0.1:8084 \
        -w /app \
        golang:latest \
        go run main.go
    
    sleep 5
    
    if docker ps | grep -q app-golang; then
        echo -e "${GREEN}✅ Method 2 worked!${NC}"
        echo ""
        echo "Test with:"
        echo "  curl http://localhost:8080/"
        echo "  curl http://localhost:8080/test"
    else
        echo -e "${RED}❌ Method 2 failed${NC}"
        docker logs app-golang 2>&1 | head -10
        
        echo ""
        echo -e "${BLUE}Trying Method 3: Build and run locally${NC}"
        echo "════════════════════════════════════════════"
        
        # Clean up
        docker stop app-golang proxy 2>/dev/null || true
        docker rm app-golang proxy 2>/dev/null || true
        
        # Build the app first
        echo "Building Go binary..."
        docker run --rm \
            -v $(pwd)/test-app:/app \
            -w /app \
            golang:alpine \
            go build -o app main.go
        
        if [ -f test-app/app ]; then
            echo -e "${GREEN}✅ Binary built successfully${NC}"
            
            # Start proxy
            docker run -d \
                --name proxy \
                -p 8084:8080 \
                mitmproxy/mitmproxy \
                mitmdump --listen-port 8080
            
            # Run the binary
            docker run -d \
                --name app-binary \
                -p 8080:8080 \
                -v $(pwd)/test-app:/app:ro \
                -e HTTP_PROXY=http://172.17.0.1:8084 \
                -e HTTPS_PROXY=http://172.17.0.1:8084 \
                -w /app \
                busybox \
                ./app
            
            sleep 3
            
            if docker ps | grep -q app-binary; then
                echo -e "${GREEN}✅ Method 3 worked!${NC}"
                echo ""
                echo "Test with:"
                echo "  curl http://localhost:8080/"
                echo "  curl http://localhost:8080/test"
            else
                echo -e "${RED}❌ Method 3 failed${NC}"
                docker logs app-binary 2>&1 | head -10
            fi
        fi
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TROUBLESHOOTING${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "If all methods failed, try:"
echo ""
echo "1. Check Docker network:"
echo "   docker run --rm alpine ping -c 1 google.com"
echo ""
echo "2. Check if you're behind a corporate proxy:"
echo "   echo \$HTTP_PROXY"
echo ""
echo "3. Try pulling images manually:"
echo "   docker pull golang:alpine"
echo "   docker pull golang:latest"
echo ""
echo "4. Use a different DNS:"
echo "   Add --dns 8.8.8.8 to docker run commands"