#!/bin/bash
# FIX 1: TRANSPARENT MODE (Original Design - Best if it works)
# This uses iptables to transparently intercept all HTTPS traffic
# NO code changes needed in your Go app!

# Don't exit on error immediately
set +e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 1: TRANSPARENT MODE (iptables)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

# Check if Docker is running
echo -e "${YELLOW}Checking Docker...${NC}"
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker daemon is not running!${NC}"
    echo ""
    echo "Please start Docker first:"
    echo "  - On Linux: sudo systemctl start docker"
    echo "  - On Mac: Open Docker Desktop"
    echo "  - On Windows: Start Docker Desktop"
    echo ""
    echo "If Docker is installed but you lack permissions:"
    echo "  sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ No code changes needed"
echo "  ✓ Captures ALL HTTPS traffic automatically"
echo "  ✓ Works with any HTTP client"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ Requires iptables support (may fail on some machines)"
echo "  ✗ Needs privileged containers"
echo ""

# Clean up
docker compose down 2>/dev/null || true
docker stop transparent-proxy app mock-viewer 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true

# BUILD IMAGES FIRST
echo -e "${YELLOW}Building Docker images...${NC}"
docker build -t proxy-3-transparent-proxy -f docker/Dockerfile.mitmproxy-universal . || \
    docker build -t proxy-3-transparent-proxy -f docker/Dockerfile.mitmproxy .
docker build -t proxy-3-app -f docker/Dockerfile.app .
docker build -t proxy-3-mock-viewer -f docker/Dockerfile.viewer . || \
    docker build -t proxy-3-mock-viewer -f Dockerfile .
echo -e "${GREEN}✅ Images built${NC}"

# Use the original transparent mode
echo -e "${YELLOW}Starting transparent proxy system...${NC}"

# Check if docker-compose exists
if command -v docker-compose &> /dev/null; then
    echo "Using docker-compose..."
    docker-compose -f docker-compose-transparent.yml up -d
elif docker compose version &> /dev/null 2>&1; then
    echo "Using docker compose..."
    docker compose -f docker-compose-transparent.yml up -d
else
    echo -e "${YELLOW}docker-compose not found, starting containers manually...${NC}"
    
    # Start containers manually
    docker network create capture-net 2>/dev/null || true
    
    # Start proxy
    docker run -d \
        --name transparent-proxy \
        --network capture-net \
        --privileged \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        -v $(pwd)/captured:/captured \
        -v $(pwd)/scripts:/scripts:ro \
        -v $(pwd)/docker/transparent-entry-universal.sh:/entry.sh:ro \
        proxy-3-transparent-proxy \
        /entry.sh
    
    # Start app
    docker run -d \
        --name app \
        --network container:transparent-proxy \
        -p 8080:8080 \
        -v $(pwd):/proxy \
        proxy-3-app \
        sh -c "sleep 3600"
    
    # Start viewer
    docker run -d \
        --name mock-viewer \
        --network capture-net \
        -p 8090:8090 \
        -v $(pwd)/configs:/app/configs \
        -v $(pwd)/captured:/app/captured \
        proxy-3-mock-viewer
fi

# Wait for proxy to be ready
sleep 5

# Check if it's working
if docker logs transparent-proxy 2>&1 | grep -q "Owner matching supported"; then
    echo -e "${GREEN}✅ Transparent mode is working!${NC}"
else
    echo -e "${RED}❌ Transparent mode failed (iptables issue)${NC}"
    echo "Try FIX-2 or FIX-3 instead"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Option A - Run inside the app container:"
echo -e "${GREEN}docker exec -it app sh${NC}"
echo -e "${GREEN}cd /your/app/path${NC}"
echo -e "${GREEN}go run main.go${NC}"
echo ""
echo "Option B - Use start-proxy-system.sh:"
echo -e "${GREEN}./start-proxy-system.sh 'go run /path/to/your/app.go'${NC}"
echo ""
echo "Option C - Run directly (app must run as UID 1000):"
echo -e "${GREEN}docker exec -u 1000 app go run /path/to/your/app.go${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} App MUST run as user 1000 (appuser) for traffic to be intercepted!"
echo ""
echo "View captures at: http://localhost:8090/viewer"
echo "Check logs: docker logs transparent-proxy"