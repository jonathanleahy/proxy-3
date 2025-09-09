#!/bin/bash
# Last trick: Use macvlan network driver to bypass iptables issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🎩 Last Trick: Macvlan Network Mode${NC}"
echo "============================================"
echo "This bypasses Docker's bridge network entirely"
echo ""

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker compose -f docker-compose-universal.yml down -v 2>/dev/null || true
docker network rm macvlan-net 2>/dev/null || true

# Try creating a macvlan network (doesn't require iptables)
echo -e "\n${YELLOW}Creating macvlan network...${NC}"
if docker network create -d macvlan \
    --subnet=192.168.50.0/24 \
    --gateway=192.168.50.1 \
    -o parent=eth0 \
    macvlan-net 2>/dev/null; then
    
    echo -e "${GREEN}✅ Macvlan network created${NC}"
    
    # Start with macvlan
    docker run -d \
        --name transparent-proxy \
        --network macvlan-net \
        --ip 192.168.50.10 \
        --privileged \
        -v $(pwd)/captured:/captured \
        -v $(pwd)/scripts:/scripts:ro \
        proxy-3-transparent-proxy
        
    echo "This might work but is complex..."
else
    echo -e "${YELLOW}⚠️  Macvlan not available${NC}"
fi

# If that doesn't work, try null network driver
echo -e "\n${YELLOW}Alternative: Using none network driver...${NC}"
docker rm -f transparent-proxy 2>/dev/null || true

# Start with no network, then add manually
docker run -d \
    --name transparent-proxy \
    --network none \
    --privileged \
    --cap-add NET_ADMIN \
    -v $(pwd)/captured:/captured \
    -v $(pwd)/scripts:/scripts:ro \
    -v $(pwd)/certs:/certs \
    proxy-3-transparent-proxy \
    sh -c "
        echo 'Starting without network...'
        # Manually configure network inside container
        ip link add dummy0 type dummy 2>/dev/null || true
        ip addr add 192.168.100.1/24 dev dummy0
        ip link set dummy0 up
        
        # Now set up iptables without Docker interference
        iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
        iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
        
        echo 'Manual network configured'
        exec mitmdump --mode transparent --listen-port 8084
    " 2>/dev/null || echo "Network isolation approach failed"

# Last resort: Just tell them to use the working solution
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${YELLOW}If none of these tricks work...${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "The iptables issues on that machine are fundamental."
echo "Docker's network stack is conflicting with iptables."
echo ""
echo -e "${GREEN}GUARANTEED SOLUTION: Use proxy mode${NC}"
echo "  ./NO-ADMIN-SOLUTION.sh"
echo ""
echo "Or if you have admin access:"
echo "  1. sudo sysctl -w net.ipv4.ip_forward=1"
echo "  2. sudo iptables -P FORWARD ACCEPT"
echo "  3. Then try: ./UNIVERSAL-FIX.sh"