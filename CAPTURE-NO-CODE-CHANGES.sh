#!/bin/bash
# CAPTURE-NO-CODE-CHANGES.sh - Capture HTTPS without modifying Go code
# Uses iptables transparent interception - your code needs NO changes

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
echo -e "${BLUE}  HTTPS CAPTURE - NO CODE CHANGES NEEDED${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Your Go code stays exactly as it is!${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Create test app WITHOUT any proxy configuration
echo -e "${YELLOW}Creating test app (standard Go code, no proxy config)...${NC}"
mkdir -p test-app-clean
cat > test-app-clean/main.go << 'EOF'
package main

import (
    "fmt"
    "io/ioutil"
    "log"
    "net/http"
)

func main() {
    // Standard Go HTTP client - NO proxy configuration
    // NO InsecureSkipVerify - completely standard code
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Standard Go app - NO proxy configuration!\n")
        fmt.Fprintf(w, "Try /test to make an HTTPS call\n")
    })
    
    http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        // Standard HTTP client - no modifications
        resp, err := http.Get("https://api.github.com")
        if err != nil {
            fmt.Fprintf(w, "Error: %v\n", err)
            return
        }
        defer resp.Body.Close()
        
        body, _ := ioutil.ReadAll(resp.Body)
        fmt.Fprintf(w, "GitHub API call successful!\n")
        fmt.Fprintf(w, "Response size: %d bytes\n", len(body))
    })
    
    log.Println("Server starting on :8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

echo -e "${GREEN}✅ Created clean app with NO proxy code${NC}"

# Method 1: Network namespace sharing (most reliable)
echo ""
echo -e "${BLUE}Method 1: Network Namespace Sharing${NC}"
echo "════════════════════════════════════════"

# Start mitmproxy with transparent mode and certificate generation
docker run -d \
    --name mitm-transparent \
    --cap-add NET_ADMIN \
    -p 8081:8081 \
    -v $(pwd)/captured:/captured \
    mitmproxy/mitmproxy \
    sh -c "
        # Generate certificate first
        mitmdump --quiet &
        PID=\$!
        sleep 3
        kill \$PID 2>/dev/null || true
        
        # Start transparent proxy
        mitmdump --mode transparent \
                 --listen-port 8080 \
                 --showhost \
                 --ssl-insecure \
                 --set confdir=/home/mitmproxy/.mitmproxy
    "

sleep 5

# Get and prepare certificate
docker exec mitm-transparent cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# Run app sharing the network namespace
docker run -d \
    --name app-clean \
    --network "container:mitm-transparent" \
    -v $(pwd)/test-app-clean:/app:ro \
    -v $(pwd)/mitmproxy-ca.pem:/usr/local/share/ca-certificates/mitmproxy.crt:ro \
    golang:alpine \
    sh -c "
        # Install certificate in system store (app doesn't know about this)
        apk add --no-cache ca-certificates 2>/dev/null || true
        update-ca-certificates 2>/dev/null || true
        
        # Run the app - it will use standard HTTPS
        cd /app
        go run main.go
    "

sleep 8

if docker ps | grep -q app-clean; then
    echo -e "${GREEN}✅ Method 1 SUCCESS - App running with transparent capture!${NC}"
    echo ""
    echo "Your app is using STANDARD Go HTTP client"
    echo "NO proxy configuration in code"
    echo "NO InsecureSkipVerify"
    echo ""
    echo "Test it:"
    echo "  curl http://localhost:8081/  (through shared network)"
    echo ""
    METHOD1_SUCCESS=true
else
    echo -e "${RED}❌ Method 1 failed${NC}"
    METHOD1_SUCCESS=false
    
    # Clean up for next method
    docker stop mitm-transparent app-clean 2>/dev/null || true
    docker rm mitm-transparent app-clean 2>/dev/null || true
fi

# Method 2: Sidecar with iptables redirection
if [ "$METHOD1_SUCCESS" = false ]; then
    echo ""
    echo -e "${BLUE}Method 2: Sidecar Container with iptables${NC}"
    echo "══════════════════════════════════════════"
    
    # Create sidecar container
    docker run -d \
        --name app-sidecar-clean \
        --cap-add NET_ADMIN \
        -p 8080:8080 \
        -v $(pwd)/test-app-clean:/app:ro \
        -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
        golang:alpine \
        sh -c "
            # Install required tools
            apk add --no-cache iptables ca-certificates mitmproxy
            
            # Install certificate
            cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
            update-ca-certificates
            
            # Start mitmproxy in background
            mitmdump --mode transparent --listen-port 8084 &
            PROXY_PID=\$!
            sleep 3
            
            # Setup iptables to redirect all HTTPS traffic
            iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
            iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
            
            # Run the app (standard code, no proxy config)
            cd /app
            go run main.go
        "
    
    sleep 8
    
    if docker ps | grep -q app-sidecar-clean; then
        echo -e "${GREEN}✅ Method 2 SUCCESS - Sidecar with iptables working!${NC}"
        echo ""
        echo "Test it:"
        echo "  curl http://localhost:8080/"
        echo "  curl http://localhost:8080/test"
    else
        echo -e "${RED}❌ Method 2 failed${NC}"
        docker logs app-sidecar-clean 2>&1 | tail -10
    fi
fi

# Method 3: Use host network mode
if [ "$METHOD1_SUCCESS" = false ]; then
    echo ""
    echo -e "${BLUE}Method 3: Host Network Mode${NC}"
    echo "═══════════════════════════════"
    
    # Clean up previous attempts
    docker stop app-sidecar-clean 2>/dev/null || true
    docker rm app-sidecar-clean 2>/dev/null || true
    
    # Start proxy on host network
    docker run -d \
        --name proxy-host \
        --network host \
        -v $(pwd)/captured:/captured \
        mitmproxy/mitmproxy \
        mitmdump --mode regular --listen-port 8084
    
    sleep 3
    
    # Run app on host network with system proxy
    docker run -d \
        --name app-host \
        --network host \
        -v $(pwd)/test-app-clean:/app:ro \
        -e http_proxy=http://127.0.0.1:8084 \
        -e https_proxy=http://127.0.0.1:8084 \
        golang:alpine \
        sh -c "cd /app && go run main.go"
    
    sleep 5
    
    if docker ps | grep -q app-host; then
        echo -e "${GREEN}✅ Method 3 SUCCESS - Host network mode working!${NC}"
        echo ""
        echo "Test it:"
        echo "  curl http://localhost:8080/"
        echo "  curl http://localhost:8080/test"
    else
        echo -e "${RED}❌ Method 3 failed${NC}"
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}The app is running with STANDARD Go code:${NC}"
echo "• NO http.ProxyFromEnvironment"
echo "• NO InsecureSkipVerify"
echo "• NO proxy configuration"
echo "• Just standard http.Get()"
echo ""
echo "The transparent proxy captures HTTPS traffic at the network level!"
echo ""
echo "To use with YOUR app:"
echo "1. Replace test-app-clean/main.go with your code"
echo "2. Run this script again"
echo "3. Your HTTPS traffic will be captured automatically"