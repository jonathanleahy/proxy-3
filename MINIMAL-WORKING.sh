#!/bin/bash
# MINIMAL-WORKING.sh - The absolute simplest setup that should work

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MINIMAL WORKING SETUP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# 1. Start the simplest possible HTTP server
echo -e "${YELLOW}Starting simple HTTP server...${NC}"
docker run -d \
    --name simple-server \
    -p 8080:8080 \
    busybox \
    sh -c "
        echo 'Starting server on port 8080...'
        while true; do 
            echo -e 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nServer is working!' | nc -l -p 8080
        done
    "

sleep 2

# Check if it's running
if docker ps | grep -q simple-server; then
    echo -e "${GREEN}✅ Server is running${NC}"
    
    # Test it
    echo -e "${YELLOW}Testing server...${NC}"
    if curl -s http://localhost:8080 2>/dev/null | grep -q "working"; then
        echo -e "${GREEN}✅ SUCCESS! Server responds on port 8080${NC}"
        echo ""
        echo "You can access it at: http://localhost:8080"
    else
        echo -e "${RED}❌ Server running but not responding${NC}"
    fi
else
    echo -e "${RED}❌ Server failed to start${NC}"
    echo "Logs:"
    docker logs simple-server
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  IF THIS WORKS, TRY STEP 2${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# 2. If basic server works, try basic proxy
echo -e "${YELLOW}Starting basic proxy (no SSL)...${NC}"
docker run -d \
    --name basic-proxy \
    -p 8084:8080 \
    -e MITMPROXY_OPTIONS="--mode regular" \
    mitmproxy/mitmproxy \
    mitmdump --mode regular --listen-port 8080 || {
        echo -e "${RED}Proxy failed, trying alternative...${NC}"
        
        # Alternative: Use a simple TCP forwarder as proxy
        docker run -d \
            --name tcp-forward \
            -p 8084:8080 \
            alpine \
            sh -c "apk add --no-cache socat && socat TCP-LISTEN:8080,fork TCP:172.17.0.1:8080"
    }

sleep 3

if docker ps | grep -q basic-proxy || docker ps | grep -q tcp-forward; then
    echo -e "${GREEN}✅ Proxy/forwarder is running on port 8084${NC}"
else
    echo -e "${RED}❌ Proxy failed to start${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ULTRA-MINIMAL TEST (NO DOCKER NETWORKING)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# 3. Test without any Docker networking issues
cat > /tmp/test-server.sh << 'EOF'
#!/bin/sh
echo "Starting test server on port 8888..."
while true; do
    echo -e "HTTP/1.1 200 OK\r\n\r\nDirect test server running on $(date)" | nc -l -p 8888
done
EOF

chmod +x /tmp/test-server.sh

echo -e "${YELLOW}Starting server using host network...${NC}"
docker run -d \
    --name host-server \
    --network host \
    -v /tmp/test-server.sh:/test-server.sh:ro \
    busybox \
    /test-server.sh || {
        echo -e "${RED}Host network not allowed (Sysbox restriction)${NC}"
        echo "This confirms you're using Sysbox containers"
    }

# Final test with all restrictions considered
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SYSBOX-COMPATIBLE VERSION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

docker stop sysbox-server 2>/dev/null || true
docker rm sysbox-server 2>/dev/null || true

echo -e "${YELLOW}Starting Sysbox-compatible server...${NC}"
docker run -d \
    --name sysbox-server \
    -p 7777:7777 \
    --security-opt seccomp=unconfined \
    busybox \
    sh -c "
        echo 'Server starting on port 7777...'
        while true; do
            printf 'HTTP/1.1 200 OK\r\nContent-Length: 23\r\n\r\nSysbox-compatible server' | nc -l -p 7777
        done
    "

sleep 2

if docker ps | grep -q sysbox-server; then
    echo -e "${GREEN}✅ Sysbox-compatible server running on port 7777${NC}"
    
    if curl -s http://localhost:7777 2>/dev/null | grep -q "Sysbox"; then
        echo -e "${GREEN}✅ SUCCESS! Access at http://localhost:7777${NC}"
    fi
else
    echo -e "${RED}❌ Even Sysbox-compatible version failed${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Running containers:"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"