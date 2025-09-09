#!/bin/bash
# START-FIX-4: Run your Go app with SIDECAR PATTERN
# Default app: ~/temp/aa/cmd/api/main.go
# Proxy and app run in the SAME container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

# Default to your specific app if no argument provided
GO_APP_CMD="${1:-go run ~/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STARTING FIX-4: SIDECAR PATTERN${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""
echo -e "${GREEN}Proxy and app in same container!${NC}"
echo ""

# Clean up first
cleanup_all_containers

# First ensure FIX-4 setup is ready
echo -e "${YELLOW}Setting up sidecar pattern...${NC}"
./FIX-4-SIDECAR.sh

echo ""
echo -e "${YELLOW}Waiting for setup...${NC}"
sleep 3

# Stop any existing sidecar container
docker stop app-sidecar-full 2>/dev/null || true
docker rm app-sidecar-full 2>/dev/null || true

# Create combined startup script
cat > /tmp/sidecar-full.sh << EOF
#!/bin/sh
echo "Starting sidecar container..."

# Start mitmproxy in background
echo "Starting proxy..."
mkdir -p ~/.mitmproxy /captured
mitmdump --quiet >/dev/null 2>&1 &
sleep 3
kill \$! 2>/dev/null || true

# Start actual proxy
mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy &
PROXY_PID=\$!
echo "✅ Proxy started (PID \$PROXY_PID)"

# Set up iptables
sleep 2
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
echo "✅ iptables rules set"

# Create appuser if needed
addgroup -g 1000 -S appuser 2>/dev/null || true
adduser -u 1000 -S appuser -G appuser 2>/dev/null || true

# Copy app files
cp -r /temp ~/temp 2>/dev/null || true
chown -R appuser:appuser ~/temp 2>/dev/null || true

# Run the Go app as appuser
echo "Starting Go app..."
su appuser -c "cd ~ && $GO_APP_CMD"
EOF

chmod +x /tmp/sidecar-full.sh

# Run everything in one container
echo -e "${YELLOW}Starting sidecar container with proxy + app...${NC}"

docker run -d \
    --name app-sidecar-full \
    --privileged \
    -p 8080:8080 \
    -v ~/temp:/temp:ro \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    -v /tmp/sidecar-full.sh:/sidecar.sh:ro \
    proxy-3-transparent-proxy \
    /sidecar.sh

echo -e "${GREEN}✅ Sidecar container starting...${NC}"
sleep 5

# Check if running
if docker ps | grep -q app-sidecar-full; then
    echo -e "${GREEN}✅ Sidecar container is running!${NC}"
    echo "Proxy and app are in the same container"
else
    echo -e "${RED}❌ Sidecar may have failed to start${NC}"
    echo "Check logs: docker logs app-sidecar-full"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! Test your app:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Call your app: curl http://localhost:8080/your-endpoint"
echo "2. View captures: http://localhost:8090/viewer"
echo "3. Check captures: ls -la captured/*.json"
echo "4. Monitor both: docker logs -f app-sidecar-full"
echo ""
echo -e "${GREEN}Everything runs in ONE container!${NC}"