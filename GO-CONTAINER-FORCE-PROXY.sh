#!/bin/bash
# Force ANY Go app in a container to use proxy (even without code changes)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🎯 Force Go Container Through Proxy${NC}"
echo "====================================="
echo ""

# Clean up
docker stop go-app-proxy 2>/dev/null || true
docker rm go-app-proxy 2>/dev/null || true
docker network rm proxy-net 2>/dev/null || true

# Create isolated network
echo -e "${YELLOW}Creating isolated network...${NC}"
docker network create --driver bridge proxy-net

# Start proxy on the network
echo -e "${YELLOW}Starting proxy...${NC}"
docker run -d \
    --name go-app-proxy \
    --network proxy-net \
    --privileged \
    -p 8084:8084 \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    proxy-3-transparent-proxy \
    sh -c '
        # Get our IP on the network
        PROXY_IP=$(hostname -i)
        echo "Proxy IP: $PROXY_IP"
        
        # Set up iptables to force ALL traffic through proxy
        iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
        iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
        
        # Start mitmproxy in transparent mode
        mkdir -p ~/.mitmproxy
        mitmdump --mode transparent --listen-port 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
    '

sleep 5

echo -e "\n${GREEN}Now run your Go app container:${NC}"
echo "================================"
echo ""
echo "Option 1 - Using network namespace sharing (RECOMMENDED):"
cat << 'EOF'
docker run \
    --network container:go-app-proxy \
    your-go-app-image
EOF

echo ""
echo "This forces ALL traffic through the proxy, no code changes needed!"
echo ""
echo "Option 2 - Using the proxy network:"
cat << 'EOF'
docker run \
    --network proxy-net \
    --dns 8.8.8.8 \
    your-go-app-image
EOF

echo ""
echo "Option 3 - Using socat to redirect (for stubborn apps):"
cat << 'EOF'
docker run \
    --network proxy-net \
    --entrypoint sh \
    your-go-app-image \
    -c 'apk add socat && \
        socat TCP-LISTEN:443,fork TCP:go-app-proxy:8084 & \
        your-go-app'
EOF

echo ""
echo -e "${BLUE}Alternative: Use redsocks (TCP redirector)${NC}"
echo "==========================================="
cat << 'EOF'
# Create redsocks container that forces everything through proxy
docker run -d \
    --name redsocks \
    --network proxy-net \
    --privileged \
    -v $(pwd)/redsocks.conf:/etc/redsocks.conf \
    ncarlier/redsocks

# Run your app using redsocks network
docker run \
    --network container:redsocks \
    your-go-app-image
EOF

echo ""
echo -e "${GREEN}✅ Proxy is ready${NC}"
echo "Captures will appear in ./captured/"
echo ""
echo -e "${YELLOW}How this works:${NC}"
echo "1. The proxy container uses iptables to intercept ALL TCP traffic"
echo "2. Your app container shares the proxy's network namespace"
echo "3. ALL HTTPS calls are forced through the proxy"
echo "4. No code changes or environment variables needed!"