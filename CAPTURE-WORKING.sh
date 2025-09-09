#!/bin/bash
# CAPTURE-WORKING.sh - Fixed version that properly mounts your Go app
# Correctly handles ~/temp directory mounting

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
echo -e "${BLUE}  WORKING HTTPS CAPTURE FOR YOUR APP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Verify the app exists
APP_DIR="$HOME/temp/aa"
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}❌ Directory not found: $APP_DIR${NC}"
    echo "Please ensure ~/temp/aa exists on your host machine"
    exit 1
fi

echo -e "${GREEN}✅ Found app directory: $APP_DIR${NC}"
ls -la "$APP_DIR/cmd/api/" | head -5

# Create capture directory
mkdir -p captured

# Step 1: Start mitmproxy
echo -e "${YELLOW}Starting mitmproxy...${NC}"

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
        --set save_stream_file=/home/mitmproxy/captured/stream.mitm

echo -e "${YELLOW}Waiting for proxy to start...${NC}"
sleep 5

# Get certificate
echo -e "${YELLOW}Getting certificate...${NC}"
docker exec proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# Step 2: Run your Go app with proper mounting
echo -e "${YELLOW}Starting your Go app with HTTPS capture...${NC}"

# Get absolute path
TEMP_DIR="$(realpath $HOME/temp)"
echo -e "${BLUE}Mounting: $TEMP_DIR as /workspace${NC}"

docker run -d \
    --name app \
    -p 8080:8080 \
    -v "$TEMP_DIR:/workspace:ro" \
    -v "$(pwd)/mitmproxy-ca.pem:/ca.pem:ro" \
    -e HTTP_PROXY=http://host.docker.internal:8084 \
    -e HTTPS_PROXY=http://host.docker.internal:8084 \
    -e SSL_CERT_FILE=/ca.pem \
    --add-host=host.docker.internal:host-gateway \
    -w /workspace/aa/cmd/api \
    alpine:latest \
    sh -c "
        echo '📦 Installing Go and dependencies...'
        apk add --no-cache go git ca-certificates curl
        
        echo '📁 Current directory:'
        pwd
        echo '📁 Files in current directory:'
        ls -la
        
        echo '🔐 Installing certificate...'
        cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates
        
        echo '🌐 Testing proxy connection...'
        curl -x http://host.docker.internal:8084 http://httpbin.org/ip || true
        
        echo '🚀 Starting Go app...'
        echo 'HTTP_PROXY=\$HTTP_PROXY'
        echo 'HTTPS_PROXY=\$HTTPS_PROXY'
        
        go run main.go
    "

echo -e "${YELLOW}Waiting for app to start...${NC}"
sleep 10

# Step 3: Create a simple viewer
echo -e "${YELLOW}Starting capture viewer...${NC}"

docker run -d \
    --name viewer \
    -p 8090:8080 \
    -v $(pwd)/captured:/usr/share/nginx/html:ro \
    nginx:alpine

# Check status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STATUS CHECK${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if docker ps | grep -q proxy; then
    echo -e "${GREEN}✅ Proxy is running${NC}"
    echo "   Web interface: http://localhost:8081"
else
    echo -e "${RED}❌ Proxy failed${NC}"
    docker logs proxy | tail -10
fi

if docker ps | grep -q app; then
    echo -e "${GREEN}✅ App is running${NC}"
    echo "   Your app: http://localhost:8080"
else
    echo -e "${RED}❌ App failed to start${NC}"
    echo -e "${YELLOW}App logs:${NC}"
    docker logs app | tail -20
fi

if docker ps | grep -q viewer; then
    echo -e "${GREEN}✅ Viewer is running${NC}"
    echo "   View captures: http://localhost:8090"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}COMMANDS TO TEST:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Test your app endpoint:"
echo "   curl http://localhost:8080/your-endpoint"
echo ""
echo "2. Test HTTPS capture from inside container:"
echo "   docker exec app curl https://api.github.com"
echo ""
echo "3. View proxy web interface:"
echo "   http://localhost:8081"
echo ""
echo "4. Check captured traffic:"
echo "   ls -la captured/"
echo ""
echo "5. View logs:"
echo "   docker logs app"
echo "   docker logs proxy"