#!/bin/bash
# Fix Docker networking and iptables issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Docker Network and iptables Issues${NC}"
echo "============================================"

# Function to clean Docker networks
clean_docker_networks() {
    echo -e "\n${YELLOW}1. Cleaning Docker networks...${NC}"
    
    # Stop all containers first
    echo "Stopping all containers..."
    docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    # Remove the problematic network
    echo "Removing capture-net network..."
    docker network rm proxy-3_capture-net 2>/dev/null || true
    docker network rm capture-net 2>/dev/null || true
    
    # Prune unused networks
    echo "Pruning unused networks..."
    docker network prune -f
    
    echo -e "${GREEN}✅ Networks cleaned${NC}"
}

# Function to reset Docker
reset_docker() {
    echo -e "\n${YELLOW}2. Resetting Docker state...${NC}"
    
    # Clean up everything
    docker system prune -af --volumes 2>/dev/null || true
    
    # Restart Docker service if possible
    if command -v systemctl >/dev/null 2>&1; then
        echo "Restarting Docker service..."
        sudo systemctl restart docker 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        sudo service docker restart 2>/dev/null || true
    fi
    
    sleep 5
    echo -e "${GREEN}✅ Docker reset${NC}"
}

# Function to create simplified docker-compose
create_simple_compose() {
    echo -e "\n${YELLOW}3. Creating simplified docker-compose...${NC}"
    
    cat > docker-compose-simple.yml <<'EOF'
version: '3.8'

services:
  # Transparent MITM proxy
  transparent-proxy:
    build:
      context: .
      dockerfile: docker/Dockerfile.mitmproxy
    container_name: transparent-proxy
    privileged: true
    volumes:
      - ./captured:/captured
      - ./scripts:/scripts:ro
      - certs:/certs
    network_mode: bridge
    ports:
      - "8080:8080"
      - "8084:8084"
    environment:
      - TRANSPARENT_MODE=true

  # Application container
  app:
    build:
      context: .
      dockerfile: docker/Dockerfile.app.minimal
    container_name: app
    depends_on:
      - transparent-proxy
    network_mode: "service:transparent-proxy"
    volumes:
      - ./:/proxy
      - certs:/certs:ro
    working_dir: /proxy
    command: tail -f /dev/null

  # Mock viewer
  viewer:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mock-viewer
    network_mode: bridge
    ports:
      - "8090:8090"
    volumes:
      - ./configs:/app/configs
      - ./captured:/app/captured
    environment:
      - PORT=8090

volumes:
  certs:
EOF
    
    echo -e "${GREEN}✅ Created docker-compose-simple.yml${NC}"
}

# Function to fix iptables issues
fix_iptables() {
    echo -e "\n${YELLOW}4. Fixing iptables configuration...${NC}"
    
    # Create a modified entry script without complex iptables
    cat > docker/transparent-entry-simple.sh <<'EOF'
#!/bin/bash
# Simplified entry point without complex iptables rules

echo "🔐 Starting mitmproxy in simplified mode"

# Try to enable IP forwarding (ignore if fails)
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# Simple iptables rules (ignore failures)
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084 2>/dev/null || true
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084 2>/dev/null || true

# Generate certificate
mkdir -p ~/.mitmproxy /certs
timeout 5 mitmdump --mode transparent --listen-port 8086 >/dev/null 2>&1 &
sleep 3
kill %1 2>/dev/null || true

# Copy certificate if generated
if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/
    echo "✅ Certificate ready"
fi

# Start mitmproxy
echo "🚀 Starting mitmproxy..."
exec mitmdump --mode transparent --listen-port 8084 -s /scripts/mitm_capture_improved.py --set confdir=~/.mitmproxy
EOF
    
    chmod +x docker/transparent-entry-simple.sh
    echo -e "${GREEN}✅ Created simplified entry script${NC}"
}

# Function to use host networking
use_host_networking() {
    echo -e "\n${YELLOW}5. Alternative: Use host networking...${NC}"
    
    cat > docker-compose-host.yml <<'EOF'
version: '3.8'

services:
  transparent-proxy:
    build:
      context: .
      dockerfile: docker/Dockerfile.mitmproxy
    container_name: transparent-proxy
    network_mode: host
    privileged: true
    volumes:
      - ./captured:/captured
      - ./scripts:/scripts:ro
      - ./certs:/certs

  app:
    build:
      context: .
      dockerfile: docker/Dockerfile.app.minimal
    container_name: app
    network_mode: host
    volumes:
      - ./:/proxy
      - ./certs:/certs:ro
    working_dir: /proxy
    command: tail -f /dev/null

volumes:
  certs:
EOF
    
    echo -e "${GREEN}✅ Created docker-compose-host.yml (uses host networking)${NC}"
}

# Main execution
echo -e "\n${BLUE}Applying fixes...${NC}"

# Clean networks
clean_docker_networks

# Create alternatives
create_simple_compose
fix_iptables
use_host_networking

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Fixes Applied!${NC}"
echo -e "${BLUE}=========================================${NC}"

echo -e "\n${GREEN}Try these solutions in order:${NC}"
echo ""
echo "1. ${YELLOW}Use simplified docker-compose:${NC}"
echo "   docker compose -f docker-compose-simple.yml build"
echo "   docker compose -f docker-compose-simple.yml up -d"
echo ""
echo "2. ${YELLOW}Use host networking (Linux only):${NC}"
echo "   docker compose -f docker-compose-host.yml build"
echo "   docker compose -f docker-compose-host.yml up -d"
echo ""
echo "3. ${YELLOW}Full reset and rebuild:${NC}"
echo "   docker system prune -af --volumes"
echo "   docker compose -f docker-compose-simple.yml build --no-cache"
echo "   docker compose -f docker-compose-simple.yml up -d"
echo ""
echo "4. ${YELLOW}If still failing, check Docker daemon:${NC}"
echo "   sudo journalctl -u docker -n 100"
echo "   docker version"
echo "   docker info"

# Additional checks
echo -e "\n${YELLOW}Diagnostic Info:${NC}"
docker version --format 'Docker version: {{.Server.Version}}' 2>/dev/null || echo "Docker not accessible"
echo "Current networks:"
docker network ls 2>/dev/null || echo "Cannot list networks"