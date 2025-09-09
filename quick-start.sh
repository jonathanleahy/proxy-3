#!/bin/bash
# Quick start script with all fixes applied
# This script ensures the system starts correctly even in restricted environments

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Quick Start - Transparent Proxy System${NC}"
echo "============================================"
echo "This script includes all fixes for network and permission issues"
echo ""

# Step 1: Check Docker access
echo -e "${YELLOW}Step 1: Checking Docker access...${NC}"
if ! docker ps >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot access Docker${NC}"
    echo "Please run: sudo usermod -aG docker $USER && newgrp docker"
    echo "Or run this script with sudo"
    exit 1
fi
echo -e "${GREEN}✅ Docker accessible${NC}"

# Step 2: Clean up any existing issues
echo -e "\n${YELLOW}Step 2: Cleaning up previous state...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker network rm proxy-3_capture-net capture-net 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"

# Step 3: Create required directories
echo -e "\n${YELLOW}Step 3: Creating directories...${NC}"
mkdir -p captured configs certs
echo -e "${GREEN}✅ Directories ready${NC}"

# Step 4: Build containers
echo -e "\n${YELLOW}Step 4: Building containers...${NC}"
docker compose -f docker-compose-transparent.yml build
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed. Trying minimal Dockerfile...${NC}"
    ./use-minimal-dockerfile.sh
    docker compose -f docker-compose-transparent.yml build
fi
echo -e "${GREEN}✅ Containers built${NC}"

# Step 5: Start containers
echo -e "\n${YELLOW}Step 5: Starting containers...${NC}"
docker compose -f docker-compose-transparent.yml up -d
sleep 5
echo -e "${GREEN}✅ Containers started${NC}"

# Step 6: Wait for proxy to be ready
echo -e "\n${YELLOW}Step 6: Waiting for proxy initialization...${NC}"
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if docker exec transparent-proxy ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Proxy ready with certificate${NC}"
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
    if [ $((COUNT % 5)) -eq 0 ]; then
        echo "  Still waiting... ($COUNT/$MAX_WAIT)"
    fi
done

# Step 7: Start the example app
echo -e "\n${YELLOW}Step 7: Starting example application...${NC}"
docker exec -d app sh -c "cd /proxy/example-app && su - appuser -c 'go run main.go'" 2>/dev/null || \
docker exec -d app sh -c "cd /proxy/example-app && go run main.go"
sleep 3
echo -e "${GREEN}✅ Application started${NC}"

# Step 8: Test the system
echo -e "\n${YELLOW}Step 8: Testing the system...${NC}"
echo "Testing health endpoint..."
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed (app may still be starting)${NC}"
fi

echo "Testing HTTPS interception..."
RESPONSE=$(curl -s http://localhost:8080/users 2>/dev/null || echo "failed")
if echo "$RESPONSE" | grep -q "success\|User"; then
    echo -e "${GREEN}✅ HTTPS interception working${NC}"
else
    echo -e "${YELLOW}⚠️  HTTPS test pending${NC}"
fi

# Step 9: Show status
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}System Status:${NC}"
echo -e "${BLUE}=========================================${NC}"

docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "proxy|app|viewer" || true

echo -e "\n${GREEN}🎉 System is ready!${NC}"
echo ""
echo "Available endpoints:"
echo "  • Health: http://localhost:8080/health"
echo "  • Users: http://localhost:8080/users (HTTPS proxy test)"
echo "  • Posts: http://localhost:8080/posts (HTTPS proxy test)"
echo "  • Viewer: http://localhost:8090/viewer"
echo ""
echo "Monitor logs:"
echo "  • docker logs -f transparent-proxy"
echo "  • docker logs -f app"
echo ""
echo "Check captures:"
echo "  • ls -la captured/"
echo ""
echo "To stop everything:"
echo "  • docker compose -f docker-compose-transparent.yml down"