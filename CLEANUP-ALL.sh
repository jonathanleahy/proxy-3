#!/bin/bash
# Clean up ALL containers and free up ports

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🧹 Cleaning up all proxy containers and ports${NC}"
echo "============================================="

# Stop all related containers
echo -e "${YELLOW}Stopping containers...${NC}"
docker stop \
    transparent-proxy \
    app \
    mock-viewer \
    viewer \
    proxy \
    go-proxy-transparent \
    go-app-shared \
    go-app-proxied \
    app-sidecar-full \
    app-with-sidecar \
    go-app-fix5 \
    2>/dev/null || true

# Remove them
echo -e "${YELLOW}Removing containers...${NC}"
docker rm -f \
    transparent-proxy \
    app \
    mock-viewer \
    viewer \
    proxy \
    go-proxy-transparent \
    go-app-shared \
    go-app-proxied \
    app-sidecar-full \
    app-with-sidecar \
    go-app-fix5 \
    2>/dev/null || true

# Clean up networks
echo -e "${YELLOW}Cleaning networks...${NC}"
docker network prune -f 2>/dev/null || true

# Check what's using port 8080
echo -e "${YELLOW}Checking port 8080...${NC}"
if lsof -i :8080 2>/dev/null; then
    echo -e "${YELLOW}Port 8080 is in use by above process${NC}"
    echo "You may need to stop it manually or use: sudo lsof -ti:8080 | xargs kill -9"
else
    echo -e "${GREEN}✅ Port 8080 is free${NC}"
fi

# Check what's using port 8084
echo -e "${YELLOW}Checking port 8084...${NC}"
if lsof -i :8084 2>/dev/null; then
    echo -e "${YELLOW}Port 8084 is in use${NC}"
else
    echo -e "${GREEN}✅ Port 8084 is free${NC}"
fi

# Check what's using port 8090
echo -e "${YELLOW}Checking port 8090...${NC}"
if lsof -i :8090 2>/dev/null; then
    echo -e "${YELLOW}Port 8090 is in use${NC}"
else
    echo -e "${GREEN}✅ Port 8090 is free${NC}"
fi

echo ""
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo "You can now run any FIX or START script"