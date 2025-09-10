#!/bin/bash
# Fix DNS resolution for transparent proxy mode

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing DNS for Transparent Proxy${NC}"
echo "===================================="
echo ""

# Option 1: Add DNS forwarding in the proxy container
echo -e "${YELLOW}Setting up DNS forwarding in proxy container...${NC}"

# Create a DNS forwarder script
cat > dns-forwarder.sh << 'EOF'
#!/bin/sh
# Simple DNS forwarding using socat or iptables

# Install dnsmasq if available
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache dnsmasq 2>/dev/null || true
fi

# Configure dnsmasq as a forwarding DNS server
if command -v dnsmasq >/dev/null 2>&1; then
    echo "Starting dnsmasq DNS forwarder..."
    cat > /tmp/dnsmasq.conf << 'DNSCONF'
# Forward all DNS queries to Google DNS
server=8.8.8.8
server=8.8.4.4
# Also try Cloudflare
server=1.1.1.1
# Listen on Docker's DNS port
listen-address=127.0.0.11
port=53
# Don't read /etc/resolv.conf
no-resolv
# Log queries for debugging
log-queries
log-facility=/var/log/dnsmasq.log
DNSCONF
    
    # Start dnsmasq
    dnsmasq -C /tmp/dnsmasq.conf -k &
    echo "DNS forwarder started on 127.0.0.11:53"
else
    echo "Using iptables for DNS forwarding..."
    # Forward DNS traffic to external DNS
    iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 8.8.8.8:53
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination 8.8.8.8:53
fi
EOF

chmod +x dns-forwarder.sh

echo -e "${GREEN}✅ DNS forwarder script created${NC}"
echo ""

# Option 2: Create a modified docker-compose with DNS settings
echo -e "${YELLOW}Creating enhanced docker-compose with DNS fix...${NC}"

cat > docker-compose-transparent-dns.yml << 'EOF'
services:
  # Transparent MITM proxy with DNS fix
  transparent-proxy:
    build:
      context: .
      dockerfile: docker/Dockerfile.mitmproxy
    container_name: transparent-proxy
    privileged: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    dns:
      - 8.8.8.8
      - 8.8.4.4
    volumes:
      - ./captured:/captured
      - ./scripts:/scripts:ro
      - ./dns-forwarder.sh:/dns-forwarder.sh:ro
      - certs:/certs
    networks:
      capture-net:
        ipv4_address: 10.5.0.2
    ports:
      - "8080:8080"
      - "8084:8084"
    environment:
      - DNS_SERVERS=8.8.8.8,8.8.4.4
    entrypoint: |
      sh -c "
      # Start DNS forwarder first
      /dns-forwarder.sh &
      
      # Continue with normal startup
      /scripts/transparent-entrypoint.sh
      "

  # Application container with DNS fix
  app:
    build:
      context: .
      dockerfile: docker/Dockerfile.app
    container_name: app
    depends_on:
      - transparent-proxy
    network_mode: "service:transparent-proxy"
    volumes:
      - ./:/proxy
      - certs:/certs:ro
    working_dir: /proxy
    environment:
      TARGET_API: "https://api.github.com"
      # Force external DNS resolution
      GODEBUG: netdns=go
    dns_options:
      - use-vc
      - edns0
    command: |
      sh -c "
      # Add external DNS to resolv.conf
      echo 'nameserver 8.8.8.8' > /etc/resolv.conf
      echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
      
      echo '🚀 App container ready with fixed DNS...'
      echo '📡 DNS resolution should work now!'
      tail -f /dev/null
      "

  # Mock viewer remains the same
  mock-viewer:
    build:
      context: .
      dockerfile: docker/Dockerfile.viewer
    container_name: mock-viewer
    volumes:
      - ./configs:/configs:ro
      - ./captured:/captured:ro
    networks:
      capture-net:
        ipv4_address: 10.5.0.3
    ports:
      - "8090:8090"

networks:
  capture-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24

volumes:
  certs:
EOF

echo -e "${GREEN}✅ Enhanced docker-compose created${NC}"
echo ""

# Option 3: Create a wrapper script for Go apps with DNS fix
echo -e "${YELLOW}Creating Go app runner with DNS fix...${NC}"

cat > run-go-with-dns.sh << 'EOF'
#!/bin/sh
# Run Go app with fixed DNS resolution

# Set Go to use pure Go DNS resolver with custom servers
export GODEBUG=netdns=go
export GOPROXY=direct

# Create custom resolv.conf
cat > /tmp/resolv.conf << 'RESOLV'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
RESOLV

# Use the custom resolv.conf
export LOCALDOMAIN=
export RES_OPTIONS=
export HOSTALIASES=/dev/null
export RESOLV_HOST_CONF=/tmp/resolv.conf

# Run the Go app with custom DNS
exec "$@"
EOF

chmod +x run-go-with-dns.sh

echo -e "${GREEN}✅ Go app runner with DNS fix created${NC}"
echo ""

echo -e "${BLUE}📋 Instructions:${NC}"
echo ""
echo "Option 1: Use the enhanced docker-compose"
echo -e "${YELLOW}docker compose -f docker-compose-transparent-dns.yml up -d${NC}"
echo ""
echo "Option 2: Run in existing container with DNS fix"
echo -e "${YELLOW}docker exec -u appuser app /proxy/run-go-with-dns.sh go run your-app.go${NC}"
echo ""
echo "Option 3: Modify your Go code to use custom DNS"
echo "Add this to your Go app:"
echo -e "${YELLOW}
import \"context\"
import \"net\"

// Custom dialer with Google DNS
dialer := &net.Dialer{
    Resolver: &net.Resolver{
        PreferGo: true,
        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
            d := net.Dialer{}
            return d.DialContext(ctx, network, \"8.8.8.8:53\")
        },
    },
}
${NC}"

echo -e "${GREEN}✅ DNS fix solutions ready!${NC}"