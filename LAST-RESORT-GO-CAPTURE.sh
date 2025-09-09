#!/bin/bash
# Last resort: Force Go app traffic through proxy using network-level tricks

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🎯 Last Resort: Network-Level Go App Capture${NC}"
echo "============================================="
echo ""

if [ $# -eq 0 ]; then
    echo "Usage: $0 'your-go-app-command'"
    echo "Example: $0 'go run main.go'"
    exit 1
fi

GO_APP_CMD="$*"

# Clean up
docker stop proxy-sidecar app-with-proxy 2>/dev/null || true
docker rm proxy-sidecar app-with-proxy 2>/dev/null || true

echo -e "${YELLOW}Option 1: Sidecar Proxy Pattern${NC}"
echo "================================"
echo "Run proxy and app in same container:"
echo ""

cat << 'EOF' > /tmp/sidecar-entrypoint.sh
#!/bin/sh
# Start mitmproxy in background
mitmdump -p 8084 -s /scripts/mitm_capture_improved.py &
PROXY_PID=$!

# Wait for proxy to start
sleep 3

# Set up iptables to redirect all traffic through proxy
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084

# Run the Go app
$@

# Keep proxy running
wait $PROXY_PID
EOF

chmod +x /tmp/sidecar-entrypoint.sh

echo "Starting combined container with proxy + app..."
docker run -d \
    --name app-with-proxy \
    --privileged \
    -p 8080:8080 \
    -v $(pwd):/app \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    -v /tmp/sidecar-entrypoint.sh:/entrypoint.sh:ro \
    -w /app \
    proxy-3-transparent-proxy \
    /entrypoint.sh $GO_APP_CMD

echo ""
echo -e "${YELLOW}Option 2: DNS Hijacking${NC}"
echo "========================"
echo "Redirect all HTTPS domains to proxy:"
echo ""

cat << 'EOF'
# Add to your container:
echo "127.0.0.1 api.example.com" >> /etc/hosts
echo "127.0.0.1 jsonplaceholder.typicode.com" >> /etc/hosts

# Run socat to forward to proxy
socat TCP-LISTEN:443,fork TCP:proxy:8084 &
EOF

echo ""
echo -e "${YELLOW}Option 3: LD_PRELOAD Hook${NC}"
echo "========================="
echo "Use proxychains to force proxy usage:"
echo ""

cat << 'EOF'
# Install proxychains in container
apk add proxychains-ng

# Configure it
echo "http 172.17.0.1 8084" > /etc/proxychains.conf

# Run Go app through proxychains
proxychains4 -q go run main.go
EOF

echo ""
echo -e "${YELLOW}Option 4: Binary Patching${NC}"
echo "========================="
echo "If Go app is compiled, patch the binary:"
echo ""

cat << 'EOF'
# Use goproxy to inject proxy
go get -u github.com/elazarl/goproxy

# Or use a LD_PRELOAD library that intercepts connect() calls
EOF

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${RED}The Reality:${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Without iptables (transparent mode) or code changes, capturing"
echo "HTTPS content from a Go app is extremely difficult because:"
echo ""
echo "1. Go binaries are statically linked (can't use LD_PRELOAD easily)"
echo "2. Go's net/http ignores proxy env vars by default"
echo "3. Go doesn't use system proxy settings"
echo ""
echo -e "${GREEN}The only reliable solutions are:${NC}"
echo "1. Modify the Go source code to use proxy"
echo "2. Fix iptables/Docker on the other machine"
echo "3. Use a different programming language"
echo "4. Use Wireshark with TLS keys (requires SSLKEYLOGFILE support)"
echo ""
echo -e "${YELLOW}Want to try the sidecar approach?${NC}"
echo "Check if it's running: docker logs app-with-proxy"
echo "Captures will be in: ./captured/"