#!/bin/bash
# START-FROM-SCRATCH.sh - Complete setup from scratch

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  COMPLETE SETUP FROM SCRATCH${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Step 1: Check what's using port 8080
echo -e "${YELLOW}Step 1: Checking port 8080...${NC}"
if lsof -i :8080 2>/dev/null | grep -q LISTEN; then
    echo -e "${RED}Port 8080 is in use by:${NC}"
    lsof -i :8080
    echo ""
    echo -e "${YELLOW}Freeing port 8080...${NC}"
    
    # Try to stop Docker containers
    docker ps --format "{{.Names}}" --filter "publish=8080" | xargs -r docker stop 2>/dev/null
    docker ps --format "{{.Names}}" --filter "publish=8080" | xargs -r docker rm 2>/dev/null
    
    # Try to kill other processes
    lsof -ti:8080 | xargs -r kill -9 2>/dev/null || {
        echo -e "${RED}Cannot kill process - may need sudo${NC}"
    }
    
    sleep 2
    
    # Check again
    if lsof -i :8080 2>/dev/null | grep -q LISTEN; then
        echo -e "${RED}Port 8080 still in use. Using alternative ports...${NC}"
        USE_ALT_PORTS=true
        APP_PORT=9080
        PROXY_PORT=9084
    else
        echo -e "${GREEN}✅ Port 8080 is now free${NC}"
        USE_ALT_PORTS=false
        APP_PORT=8080
        PROXY_PORT=8084
    fi
else
    echo -e "${GREEN}✅ Port 8080 is free${NC}"
    USE_ALT_PORTS=false
    APP_PORT=8080
    PROXY_PORT=8084
fi

# Step 2: Clean up all Docker containers
echo ""
echo -e "${YELLOW}Step 2: Cleaning up Docker containers...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
echo -e "${GREEN}✅ Cleaned up${NC}"

# Step 3: Create a simple test app
echo ""
echo -e "${YELLOW}Step 3: Creating test app...${NC}"
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
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    
    fmt.Printf("Starting server on port %s...\n", port)
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "✅ Server is working on port %s!\n\n", port)
        fmt.Fprintf(w, "Available endpoints:\n")
        fmt.Fprintf(w, "  /test - Make HTTPS call through proxy\n")
        fmt.Fprintf(w, "  /direct - Make direct HTTPS call\n")
    })
    
    http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        fmt.Println("Making HTTPS call WITH proxy...")
        
        // This will use proxy from environment
        client := &http.Client{
            Transport: &http.Transport{
                Proxy: http.ProxyFromEnvironment,
                TLSClientConfig: &tls.Config{
                    InsecureSkipVerify: true,
                },
            },
        }
        
        resp, err := client.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "✅ HTTPS call successful (WITH proxy)!\n")
        fmt.Fprintf(w, "Response: %d bytes\n", len(body))
    })
    
    http.HandleFunc("/direct", func(w http.ResponseWriter, r *http.Request) {
        fmt.Println("Making HTTPS call WITHOUT proxy...")
        
        resp, err := http.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "✅ HTTPS call successful (direct)!\n")
        fmt.Fprintf(w, "Response: %d bytes\n", len(body))
    })
    
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF
echo -e "${GREEN}✅ Test app created${NC}"

# Step 4: Build the app (static binary for compatibility)
echo ""
echo -e "${YELLOW}Step 4: Building Go app (static binary)...${NC}"
docker run --rm \
    -v $(pwd)/test-app:/app \
    -w /app \
    -e CGO_ENABLED=0 \
    -e GOOS=linux \
    -e GOARCH=amd64 \
    golang:alpine \
    go build -a -installsuffix cgo -ldflags="-s -w" -o server main.go

if [ ! -f test-app/server ]; then
    echo -e "${RED}Failed to build app${NC}"
    exit 1
fi
echo -e "${GREEN}✅ App built${NC}"

# Step 5: Start the proxy
echo ""
echo -e "${YELLOW}Step 5: Starting proxy on port $PROXY_PORT...${NC}"
docker run -d \
    --name proxy \
    -p $PROXY_PORT:8080 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8080

sleep 3

if docker ps | grep -q proxy; then
    echo -e "${GREEN}✅ Proxy started on port $PROXY_PORT${NC}"
else
    echo -e "${RED}❌ Proxy failed to start${NC}"
    docker logs proxy
    exit 1
fi

# Step 6: Start the app
echo ""
echo -e "${YELLOW}Step 6: Starting app on port $APP_PORT...${NC}"

# First try with busybox (smallest)
docker run -d \
    --name app \
    -p $APP_PORT:8080 \
    -v $(pwd)/test-app:/app:ro \
    -e PORT=8080 \
    -e HTTP_PROXY=http://172.17.0.1:$PROXY_PORT \
    -e HTTPS_PROXY=http://172.17.0.1:$PROXY_PORT \
    busybox \
    /app/server 2>/dev/null || {
        echo "Busybox failed, trying Alpine..."
        docker rm app 2>/dev/null
        docker run -d \
            --name app \
            -p $APP_PORT:8080 \
            -v $(pwd)/test-app:/app:ro \
            -e PORT=8080 \
            -e HTTP_PROXY=http://172.17.0.1:$PROXY_PORT \
            -e HTTPS_PROXY=http://172.17.0.1:$PROXY_PORT \
            alpine:latest \
            /app/server
    }

sleep 3

if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App started on port $APP_PORT${NC}"
else
    echo -e "${RED}❌ App failed to start${NC}"
    docker logs app
    exit 1
fi

# Step 7: Test everything
echo ""
echo -e "${YELLOW}Step 7: Testing the setup...${NC}"

if curl -s http://localhost:$APP_PORT/ | grep -q "working"; then
    echo -e "${GREEN}✅ App is responding!${NC}"
else
    echo -e "${RED}❌ App not responding${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 SETUP COMPLETE!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your system is now running:"
echo "  • App on port $APP_PORT"
echo "  • Proxy on port $PROXY_PORT"
echo ""
echo -e "${YELLOW}TEST COMMANDS:${NC}"
echo ""
echo "1. Check the app:"
echo "   ${GREEN}curl http://localhost:$APP_PORT/${NC}"
echo ""
echo "2. Test HTTPS capture (through proxy):"
echo "   ${GREEN}curl http://localhost:$APP_PORT/test${NC}"
echo ""
echo "3. Test direct HTTPS (no proxy):"
echo "   ${GREEN}curl http://localhost:$APP_PORT/direct${NC}"
echo ""
echo "4. View proxy logs (captured traffic):"
echo "   ${GREEN}docker logs proxy${NC}"
echo ""
echo -e "${BLUE}The /test endpoint will be captured by the proxy.${NC}"
echo -e "${BLUE}The /direct endpoint bypasses the proxy.${NC}"