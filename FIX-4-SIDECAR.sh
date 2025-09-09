#!/bin/bash
# FIX 4: SIDECAR PATTERN
# Run proxy and app in the SAME container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 4: SIDECAR PROXY PATTERN${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ Everything in one container"
echo "  ✓ iptables work reliably (same container)"
echo "  ✓ No code changes needed"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ More complex container setup"
echo "  ✗ Proxy and app logs mixed"
echo ""

# Clean up
docker stop app-with-sidecar 2>/dev/null || true
docker rm -f app-with-sidecar 2>/dev/null || true

# Create sidecar startup script
cat > /tmp/sidecar-start.sh << 'EOF'
#!/bin/sh
# Start proxy in background
echo "Starting mitmproxy sidecar..."
mkdir -p ~/.mitmproxy /captured

# Generate certificate
mitmdump --quiet >/dev/null 2>&1 &
sleep 3
kill $! 2>/dev/null

# Start proxy
mitmdump -p 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy &
PROXY_PID=$!

# Set up iptables to redirect traffic
sleep 2
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
echo "✅ Proxy sidecar ready"

# Run the actual app command
echo "Starting app: $@"
exec "$@"
EOF

chmod +x /tmp/sidecar-start.sh

echo -e "${YELLOW}Sidecar script created${NC}"

# Start viewer
docker run -d \
    --name viewer \
    -p 8090:8090 \
    -v $(pwd)/configs:/app/configs \
    -v $(pwd)/captured:/app/captured \
    -v $(pwd)/viewer.html:/app/viewer.html:ro \
    -v $(pwd)/viewer-server.js:/app/viewer-server.js:ro \
    -e PORT=8090 \
    -e CAPTURED_DIR=/app/captured \
    proxy-3-viewer 2>/dev/null || true

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}NO CODE CHANGES NEEDED!${NC}"
echo ""
echo "Run proxy and app together:"
echo -e "${GREEN}docker run \\
    --name app-with-sidecar \\
    --privileged \\
    -p 8080:8080 \\
    -v \$(pwd):/app \\
    -v \$(pwd)/captured:/captured \\
    -v \$(pwd)/scripts:/scripts:ro \\
    -v /tmp/sidecar-start.sh:/sidecar.sh:ro \\
    -w /app \\
    proxy-3-transparent-proxy \\
    /sidecar.sh go run your-app.go${NC}"
echo ""
echo "The sidecar proxy will:"
echo "1. Start mitmproxy in the background"
echo "2. Set up iptables rules"
echo "3. Run your Go app"
echo "4. Capture ALL traffic automatically"
echo ""
echo "View captures at: http://localhost:8090/viewer"
echo "Check logs: docker logs app-with-sidecar"