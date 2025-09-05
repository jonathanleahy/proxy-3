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
echo -e "\n${YELLOW}Step 1: Cleaning up...${NC}"
docker stop mitm-proxy 2>/dev/null || true
docker rm mitm-proxy 2>/dev/null || true
docker stop mock-server-viewer 2>/dev/null || true
docker rm mock-server-viewer 2>/dev/null || true

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
    # If we have the mock server locally, use it
    PORT=8090 go run cmd/main.go &
    VIEWER_PID=$!
    echo "✅ Viewer started at http://localhost:8090/viewer"
else
    echo "⚠️  Viewer not available (cmd/main.go not found)"
fi

# Step 4: Wait for certificate generation
echo -e "\n${YELLOW}Step 4: Extracting CA certificate...${NC}"
sleep 5  # Give mitmproxy time to generate certs

# Create certs directory
mkdir -p certs

# Extract certificate from container
docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem 2>/dev/null || {
    echo -e "${RED}❌ Failed to extract certificate. Trying alternative method...${NC}"
    docker exec mitm-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > certs/mitmproxy-ca.pem
}

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