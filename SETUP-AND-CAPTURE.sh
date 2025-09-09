#!/bin/bash
# SETUP-AND-CAPTURE.sh - Setup test app or find your real app, then capture HTTPS

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
echo -e "${BLUE}  SETUP APP AND CAPTURE HTTPS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Check for various possible app locations
echo -e "${YELLOW}Looking for Go applications...${NC}"

APP_FOUND=false
APP_PATH=""
APP_DIR=""

# Check common locations
POSSIBLE_PATHS=(
    "$HOME/temp/aa/cmd/api/main.go"
    "$HOME/temp/aa/main.go"
    "$HOME/aa/cmd/api/main.go"
    "$HOME/go/src/aa/cmd/api/main.go"
    "$HOME/projects/aa/cmd/api/main.go"
    "$HOME/code/aa/cmd/api/main.go"
    "$HOME/dev/aa/cmd/api/main.go"
    "$HOME/workspace/aa/cmd/api/main.go"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo -e "${GREEN}✅ Found app at: $path${NC}"
        APP_FOUND=true
        APP_PATH="$path"
        APP_DIR="$(dirname $path)"
        break
    else
        echo "   ❌ Not found: $path"
    fi
done

# If no app found, ask user or create test app
if [ "$APP_FOUND" = false ]; then
    echo ""
    echo -e "${YELLOW}No Go app found at expected locations.${NC}"
    echo ""
    echo "Options:"
    echo "1. I'll create a test app for you"
    echo "2. Tell me where your Go app is located"
    echo ""
    echo -e "${BLUE}Creating a test app to demonstrate HTTPS capture...${NC}"
    
    # Create test app
    mkdir -p test-app
    cat > test-app/main.go << 'EOF'
package main

import (
    "crypto/tls"
    "encoding/json"
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
    "time"
)

func main() {
    // Setup routes
    http.HandleFunc("/", handleHome)
    http.HandleFunc("/test-github", handleGitHub)
    http.HandleFunc("/test-multiple", handleMultiple)
    http.HandleFunc("/test-post", handlePost)
    
    log.Println("🚀 Test app starting on :8080")
    log.Println("Available endpoints:")
    log.Println("  GET /              - Home page")
    log.Println("  GET /test-github   - Test GitHub API call")
    log.Println("  GET /test-multiple - Test multiple HTTPS calls")
    log.Println("  GET /test-post     - Test POST request")
    
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleHome(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Test App Running! 🎉\n\n")
    fmt.Fprintf(w, "Try these endpoints:\n")
    fmt.Fprintf(w, "- /test-github   - Makes HTTPS call to GitHub\n")
    fmt.Fprintf(w, "- /test-multiple - Makes multiple HTTPS calls\n")
    fmt.Fprintf(w, "- /test-post     - Makes POST request\n")
}

func handleGitHub(w http.ResponseWriter, r *http.Request) {
    log.Println("Making GitHub API call...")
    
    // Create client that works with proxy
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment,
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true, // For testing with mitmproxy
            },
        },
        Timeout: 10 * time.Second,
    }
    
    resp, err := client.Get("https://api.github.com/users/github")
    if err != nil {
        fmt.Fprintf(w, "Error calling GitHub: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := ioutil.ReadAll(resp.Body)
    
    var result map[string]interface{}
    json.Unmarshal(body, &result)
    
    fmt.Fprintf(w, "GitHub API Response:\n")
    fmt.Fprintf(w, "Status: %d\n", resp.StatusCode)
    fmt.Fprintf(w, "User: %v\n", result["login"])
    fmt.Fprintf(w, "Company: %v\n", result["company"])
    fmt.Fprintf(w, "Response size: %d bytes\n", len(body))
}

func handleMultiple(w http.ResponseWriter, r *http.Request) {
    log.Println("Making multiple HTTPS calls...")
    
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment,
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true,
            },
        },
        Timeout: 10 * time.Second,
    }
    
    urls := []string{
        "https://api.github.com",
        "https://httpbin.org/get",
        "https://jsonplaceholder.typicode.com/posts/1",
    }
    
    fmt.Fprintf(w, "Making calls to multiple APIs:\n\n")
    
    for _, url := range urls {
        resp, err := client.Get(url)
        if err != nil {
            fmt.Fprintf(w, "❌ %s - Error: %v\n", url, err)
            continue
        }
        resp.Body.Close()
        fmt.Fprintf(w, "✅ %s - Status: %d\n", url, resp.StatusCode)
    }
}

func handlePost(w http.ResponseWriter, r *http.Request) {
    log.Println("Making POST request...")
    
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment,
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true,
            },
        },
    }
    
    resp, err := client.Post(
        "https://httpbin.org/post",
        "application/json",
        nil,
    )
    
    if err != nil {
        fmt.Fprintf(w, "Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    fmt.Fprintf(w, "POST Response: %d\n", resp.StatusCode)
}
EOF
    
    APP_DIR="$(pwd)/test-app"
    APP_PATH="$APP_DIR/main.go"
    echo -e "${GREEN}✅ Created test app at: $APP_PATH${NC}"
fi

# Create capture directory
mkdir -p captured

# Start the capture system
echo ""
echo -e "${YELLOW}Starting HTTPS capture system...${NC}"

# 1. Start mitmproxy
echo -e "${BLUE}Starting mitmproxy...${NC}"
docker run -d \
    --name proxy \
    -p 8084:8080 \
    -p 8081:8081 \
    -v $(pwd)/captured:/home/mitmproxy/captured \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --web-port 8081 \
        --web-host 0.0.0.0 \
        --set confdir=/home/mitmproxy/.mitmproxy \
        --save-stream-file /home/mitmproxy/captured/stream.mitm

sleep 5

# Get certificate
docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# 2. Start the Go app
echo -e "${BLUE}Starting Go app...${NC}"

# Get the parent directory to mount
MOUNT_DIR="$(dirname $APP_DIR)"
REL_PATH="${APP_DIR#$MOUNT_DIR/}"

echo "  Mounting: $MOUNT_DIR as /workspace"
echo "  App path: /workspace/$REL_PATH"

docker run -d \
    --name app \
    -p 8080:8080 \
    -v "$MOUNT_DIR:/workspace:ro" \
    -v "$(pwd)/mitmproxy-ca.pem:/ca.pem:ro" \
    -e HTTP_PROXY=http://host.docker.internal:8084 \
    -e HTTPS_PROXY=http://host.docker.internal:8084 \
    --add-host=host.docker.internal:host-gateway \
    -w "/workspace/$REL_PATH" \
    alpine:latest \
    sh -c "
        echo '📦 Installing Go...'
        apk add --no-cache go git ca-certificates
        
        echo '📁 Working directory:'
        pwd
        ls -la
        
        echo '🚀 Starting app...'
        go run main.go
    "

sleep 8

# 3. Check status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  CAPTURE SYSTEM STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if docker ps | grep -q " proxy"; then
    echo -e "${GREEN}✅ Proxy is running${NC}"
    echo "   Web UI: http://localhost:8081"
else
    echo -e "${RED}❌ Proxy failed${NC}"
fi

if docker ps | grep -q " app"; then
    echo -e "${GREEN}✅ App is running${NC}"
    echo "   App URL: http://localhost:8080"
    echo ""
    echo -e "${GREEN}TEST THE CAPTURE:${NC}"
    echo ""
    echo "1. Test the app:"
    echo "   curl http://localhost:8080/"
    echo ""
    echo "2. Trigger HTTPS capture:"
    echo "   curl http://localhost:8080/test-github"
    echo "   curl http://localhost:8080/test-multiple"
    echo ""
    echo "3. View captures in mitmproxy:"
    echo "   http://localhost:8081"
    echo ""
    echo "4. Check capture files:"
    echo "   ls -la captured/"
else
    echo -e "${RED}❌ App failed to start${NC}"
    echo ""
    echo "App logs:"
    docker logs app 2>&1 | tail -20
fi

echo ""
echo -e "${YELLOW}If you have your own Go app, place it at:${NC}"
echo "  ~/temp/aa/cmd/api/main.go"
echo "Then run this script again."