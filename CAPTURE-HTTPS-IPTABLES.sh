#!/bin/bash
# CAPTURE-HTTPS-IPTABLES.sh - Use iptables for transparent HTTPS capture
# Works if your Docker supports iptables in containers

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Source cleanup function
source ./cleanup-containers.sh

# Your Go app command
GO_APP_CMD="${1:-go run ~/temp/aa/cmd/api/main.go}"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  IPTABLES TRANSPARENT HTTPS CAPTURE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Using iptables for transparent interception${NC}"
echo -e "${YELLOW}App: $GO_APP_CMD${NC}"
echo ""

# Clean up first
cleanup_all_containers

# Step 1: Build and start the proxy
echo -e "${YELLOW}Building proxy image...${NC}"

cat > /tmp/Dockerfile.transparent << 'EOF'
FROM mitmproxy/mitmproxy

USER root
RUN apk add --no-cache iptables ca-certificates

# Create capture directory
RUN mkdir -p /captured

COPY scripts/capture_https.py /scripts/

# Enable IP forwarding
RUN echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
RUN echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

EXPOSE 8084 8090

CMD ["mitmdump", "--mode", "transparent", "--listen-port", "8084", "--scripts", "/scripts/capture_https.py"]
EOF

docker build -t transparent-capture -f /tmp/Dockerfile.transparent .

echo -e "${YELLOW}Starting transparent proxy...${NC}"

docker run -d \
    --name transparent-proxy \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.send_redirects=0 \
    -p 8084:8084 \
    -p 8090:8090 \
    -v $(pwd)/captured:/captured \
    transparent-capture

echo -e "${YELLOW}Waiting for proxy to start...${NC}"
sleep 5

# Get certificate
docker exec transparent-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true

# Step 2: Start app container with iptables rules
echo -e "${YELLOW}Starting app with transparent capture...${NC}"

# Check for golang image
if docker images | grep -q "golang"; then
    BASE_IMAGE="golang:1.23-alpine"
    INSTALL_CMD="apk add --no-cache ca-certificates iptables"
else
    BASE_IMAGE="alpine:latest"
    INSTALL_CMD="apk add --no-cache go git ca-certificates iptables"
fi

# Get proxy container IP
PROXY_IP=$(docker inspect transparent-proxy | grep '"IPAddress"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

docker run -d \
    --name app-transparent \
    --cap-add NET_ADMIN \
    -p 8080:8080 \
    -v ~/temp:/app:ro \
    -v $(pwd)/mitmproxy-ca.pem:/ca.pem:ro \
    --dns 8.8.8.8 \
    --dns 8.8.4.4 \
    $BASE_IMAGE \
    sh -c "
        echo '🔧 Setting up transparent capture...'
        $INSTALL_CMD
        
        # Add user
        addgroup -g 1000 -S appuser 2>/dev/null || true
        adduser -u 1000 -S appuser -G appuser 2>/dev/null || true
        
        # Install certificate
        cp /ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates
        
        # Setup iptables rules for transparent proxy
        echo '📡 Configuring iptables...'
        iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j DNAT --to-destination $PROXY_IP:8084
        iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j DNAT --to-destination $PROXY_IP:8084
        
        # Prevent loops
        iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner 0 -j ACCEPT
        
        echo '🚀 Starting app as appuser...'
        cd /app
        su appuser -c '${GO_APP_CMD#~/temp}'
    "

echo -e "${GREEN}✅ System starting...${NC}"
sleep 5

# Check status
if docker ps | grep -q app-transparent && docker ps | grep -q transparent-proxy; then
    echo -e "${GREEN}✅ Transparent capture is running!${NC}"
else
    echo -e "${RED}❌ Something failed to start${NC}"
    echo "Check logs:"
    echo "  docker logs transparent-proxy"
    echo "  docker logs app-transparent"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}READY! HTTPS capture active${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ NO code changes needed${NC}"
echo -e "${GREEN}✅ NO environment variables needed${NC}"
echo -e "${GREEN}✅ Transparent HTTPS interception active${NC}"
echo ""
echo "📍 Your app: http://localhost:8080"
echo "📍 Proxy IP: $PROXY_IP"
echo "📍 Captures: captured/*.json"
echo ""
echo -e "${YELLOW}Test capture:${NC}"
echo "docker exec app-transparent su appuser -c 'wget -O- https://api.github.com'"
echo ""
echo -e "${YELLOW}View captures:${NC}"
echo "ls -la captured/"
echo "cat captured/captures_summary.txt"