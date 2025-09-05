#!/bin/bash

# HTTPS Capture Script - Works without admin rights!
# Uses Docker and environment variables to capture decrypted HTTPS traffic

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔐 HTTPS Capture System${NC}"
echo "================================"

# Step 1: Clean up any existing containers
echo -e "\n${YELLOW}Step 1: Cleaning up old containers...${NC}"
# Stop and remove any existing mitm-proxy containers
docker stop mitm-proxy 2>/dev/null || true
docker rm mitm-proxy 2>/dev/null || true
# Clean up any orphaned mitmproxy containers
docker ps -aq --filter "ancestor=mitmproxy/mitmproxy" | xargs -r docker rm -f 2>/dev/null || true
# Clean up mock server containers
docker stop mock-server-viewer 2>/dev/null || true
docker rm mock-server-viewer 2>/dev/null || true
echo "✅ Cleanup complete"

# Step 2: Start mitmproxy
echo -e "\n${YELLOW}Step 2: Starting MITM proxy...${NC}"
docker run -d \
  --name mitm-proxy \
  -p 8080:8080 \
  -v $(pwd)/captured:/captured \
  -v $(pwd)/scripts:/scripts \
  mitmproxy/mitmproxy \
  mitmdump -s /scripts/mitm_capture.py

echo "✅ MITM proxy started on port 8080"

# Step 3: Start viewer (optional but helpful)
echo -e "\n${YELLOW}Step 3: Starting web viewer...${NC}"
if [ -f "cmd/main.go" ]; then
    # Kill any existing process on port 8090
    lsof -ti:8090 | xargs kill -9 2>/dev/null || true
    sleep 1
    # If we have the mock server locally, use it
    PORT=8090 go run cmd/main.go &
    VIEWER_PID=$!
    echo "✅ Viewer started at http://localhost:8090/viewer"
else
    echo "⚠️  Viewer not available (cmd/main.go not found)"
fi

# Step 4: Wait for certificate generation
echo -e "\n${YELLOW}Step 4: Extracting CA certificate...${NC}"
echo "Waiting for mitmproxy to generate certificates..."
sleep 3  # Reduced wait time - mitmproxy generates certs quickly

# Create certs directory
mkdir -p certs

# Try multiple methods to extract certificate
echo "Attempting to extract certificate..."

# Method 1: Direct docker cp
if docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem 2>/dev/null; then
    echo "✅ Certificate extracted using docker cp"
else
    echo "First method failed, trying alternative..."
    
    # Method 2: Use docker exec to cat the file
    if docker exec mitm-proxy test -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem 2>/dev/null; then
        docker exec mitm-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > certs/mitmproxy-ca.pem 2>/dev/null
        if [ -s "certs/mitmproxy-ca.pem" ]; then
            echo "✅ Certificate extracted using docker exec"
        else
            echo "Certificate file is empty, waiting more..."
            sleep 2
            docker exec mitm-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > certs/mitmproxy-ca.pem
        fi
    else
        # Method 3: Force certificate generation by running mitmdump briefly
        echo "Certificate not found yet, forcing generation..."
        # Run mitmdump briefly inside the container to ensure cert generation
        docker exec mitm-proxy sh -c "mitmdump --version && sleep 1" >/dev/null 2>&1 || true
        sleep 2
        # Now try to get the certificate
        docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem 2>/dev/null || \
        docker exec mitm-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > certs/mitmproxy-ca.pem 2>/dev/null
    fi
fi

if [ -f "certs/mitmproxy-ca.pem" ]; then
    echo "✅ Certificate extracted to certs/mitmproxy-ca.pem"
else
    echo -e "${RED}❌ Failed to extract certificate${NC}"
    exit 1
fi

# Step 5: Show instructions
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ HTTPS Capture System Ready!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}To capture HTTPS traffic from your app:${NC}"
echo ""
echo "1. Copy and run these commands in your app's terminal:"
echo ""
echo -e "${GREEN}export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem${NC}"
echo -e "${GREEN}export HTTP_PROXY=http://localhost:8080${NC}"
echo -e "${GREEN}export HTTPS_PROXY=http://localhost:8080${NC}"
echo -e "${GREEN}./your-app${NC}"
echo ""
echo "2. View captured traffic:"
echo "   - Web viewer: http://localhost:8090/viewer (select 'Captured')"
echo "   - JSON files: ls -la captured/"
echo ""
echo "3. Test with curl:"
echo -e "${GREEN}curl --cacert certs/mitmproxy-ca.pem -x http://localhost:8080 https://api.github.com${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop capture${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    docker stop mitm-proxy 2>/dev/null || true
    docker rm mitm-proxy 2>/dev/null || true
    if [ -n "$VIEWER_PID" ]; then
        kill $VIEWER_PID 2>/dev/null || true
    fi
    echo -e "${GREEN}✅ Cleanup complete${NC}"
    exit 0
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Keep script running and show logs
echo -e "\n${YELLOW}📊 Live capture logs:${NC}"
echo "----------------------------------------"
docker logs -f mitm-proxy 2>&1 | while read line; do
    if [[ $line == *"Captured"* ]]; then
        echo -e "${GREEN}$line${NC}"
    else
        echo "$line"
    fi
done