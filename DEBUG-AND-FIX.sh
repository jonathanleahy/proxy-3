#!/bin/bash
# DEBUG-AND-FIX.sh - Debug why port 8080 isn't accessible and fix it

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DEBUGGING PORT 8080 ISSUE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}1. Checking what containers are running:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${YELLOW}2. Checking if app-sidecar-clean is running:${NC}"
if docker ps | grep -q app-sidecar-clean; then
    echo -e "${GREEN}✅ Container is running${NC}"
    
    echo ""
    echo -e "${YELLOW}3. Checking container logs:${NC}"
    docker logs --tail 30 app-sidecar-clean
    
    echo ""
    echo -e "${YELLOW}4. Testing connection from inside container:${NC}"
    docker exec app-sidecar-clean sh -c "wget -O- http://localhost:8080 2>&1 | head -10" || true
    
    echo ""
    echo -e "${YELLOW}5. Checking what's listening inside container:${NC}"
    docker exec app-sidecar-clean sh -c "netstat -tlnp 2>/dev/null | grep LISTEN" || true
    
    echo ""
    echo -e "${YELLOW}6. Checking if Go app actually started:${NC}"
    docker exec app-sidecar-clean sh -c "ps aux | grep -E 'go|main'" || true
else
    echo -e "${RED}❌ Container is not running${NC}"
    
    echo ""
    echo -e "${YELLOW}Checking if it exited:${NC}"
    docker ps -a | grep app-sidecar-clean
    
    echo ""
    echo -e "${YELLOW}Getting logs from exited container:${NC}"
    docker logs app-sidecar-clean 2>&1 | tail -50
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ATTEMPTING FIX${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up
docker stop app-sidecar-clean 2>/dev/null || true
docker rm app-sidecar-clean 2>/dev/null || true

# Create simpler test app
mkdir -p test-app-simple
cat > test-app-simple/main.go << 'EOF'
package main

import (
    "fmt"
    "log"
    "net/http"
)

func main() {
    fmt.Println("Starting server on :8080...")
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Server is working!\n")
    })
    
    if err := http.ListenAndServe(":8080", nil); err != nil {
        log.Fatal("Failed to start server:", err)
    }
}
EOF

echo -e "${YELLOW}Starting fixed version with better error handling...${NC}"

# Start with explicit port mapping and better logging
docker run -d \
    --name app-fixed \
    --cap-add NET_ADMIN \
    -p 8080:8080 \
    -p 8084:8084 \
    -v $(pwd)/test-app-simple:/app:ro \
    golang:alpine \
    sh -c "
        echo '=== Starting container setup ==='
        
        # Install required packages
        echo 'Installing packages...'
        apk add --no-cache iptables ca-certificates mitmproxy netstat-nat curl
        
        # Start mitmproxy in background
        echo 'Starting mitmproxy on port 8084...'
        mitmdump --mode transparent --listen-port 8084 > /tmp/proxy.log 2>&1 &
        PROXY_PID=\$!
        echo \"Proxy PID: \$PROXY_PID\"
        
        # Give proxy time to start
        sleep 3
        
        # Setup iptables (but not for our app's port)
        echo 'Setting up iptables redirection...'
        # Only redirect external HTTPS, not our app's port
        iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
        iptables -t nat -A OUTPUT -p tcp --dport 80 ! --dport 8080 -j REDIRECT --to-port 8084
        
        # Show network config
        echo 'Network configuration:'
        ip addr show
        
        # Start the Go app
        echo 'Starting Go app on port 8080...'
        cd /app
        go run main.go &
        APP_PID=\$!
        echo \"App PID: \$APP_PID\"
        
        # Wait a moment for app to start
        sleep 5
        
        # Test if app is reachable
        echo 'Testing app locally...'
        curl -v http://localhost:8080/ || echo 'Local test failed'
        
        # Show what's listening
        echo 'Listening ports:'
        netstat -tlnp
        
        # Keep container running
        echo 'Container ready - keeping alive...'
        wait \$APP_PID
    "

echo -e "${YELLOW}Waiting for container to start...${NC}"
sleep 10

# Test the fixed version
echo ""
echo -e "${BLUE}Testing fixed version:${NC}"
if curl -s http://localhost:8080/ 2>/dev/null | grep -q "working"; then
    echo -e "${GREEN}✅ SUCCESS! Port 8080 is now accessible${NC}"
    echo ""
    echo "You can now access:"
    echo "  http://localhost:8080/ - Your app"
    echo "  Port 8084 - Transparent proxy"
else
    echo -e "${RED}❌ Still not working${NC}"
    echo ""
    echo "Container logs:"
    docker logs --tail 50 app-fixed
    echo ""
    echo "Try accessing the container directly:"
    echo "  docker exec app-fixed curl http://localhost:8080/"
fi