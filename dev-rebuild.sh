#!/bin/bash

# Development rebuild script - rebuilds everything from scratch
# Use this when you've made changes to code or configuration

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔨 Development Rebuild Script${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Function to handle errors
handle_error() {
    echo -e "${RED}❌ Error occurred during rebuild${NC}"
    exit 1
}

# Set error handler
trap handle_error ERR

# Step 1: Stop all running containers
echo -e "${YELLOW}📦 Step 1: Stopping all containers...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker compose down 2>/dev/null || true
pkill -f "go run" 2>/dev/null || true
echo -e "${GREEN}✅ Containers stopped${NC}"
echo ""

# Step 2: Clean up old images (optional, commented out by default)
echo -e "${YELLOW}🧹 Step 2: Cleaning up...${NC}"
# Uncomment the next line to remove old images (takes longer but ensures clean build)
# docker compose -f docker-compose-transparent.yml rm -f 2>/dev/null || true
docker system prune -f 2>/dev/null || true
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 3: Build the example app
echo -e "${YELLOW}🔧 Step 3: Building example app...${NC}"
if [ -d "example-app" ]; then
    cd example-app
    if [ -f "build.sh" ]; then
        ./build.sh
    else
        GOOS=linux GOARCH=amd64 go build -o example-server main.go
    fi
    cd ..
    echo -e "${GREEN}✅ Example app built${NC}"
else
    echo -e "${BLUE}ℹ️  No example app to build${NC}"
fi
echo ""

# Step 4: Build main binaries
echo -e "${YELLOW}🔧 Step 4: Building main binaries...${NC}"
go build -o mock-server cmd/main.go
go build -o capture-proxy cmd/capture/main.go
echo -e "${GREEN}✅ Binaries built${NC}"
echo ""

# Step 5: Rebuild Docker images
echo -e "${YELLOW}🐳 Step 5: Rebuilding Docker images...${NC}"
docker compose -f docker-compose-transparent.yml build --no-cache
echo -e "${GREEN}✅ Docker images rebuilt${NC}"
echo ""

# Step 6: Start the system
echo -e "${YELLOW}🚀 Step 6: Starting the system...${NC}"
./transparent-capture.sh start
echo ""

# Step 7: Verify services
echo -e "${YELLOW}🔍 Step 7: Verifying services...${NC}"
sleep 3

# Check mock viewer
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/viewer 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Mock viewer is running at http://localhost:8090/viewer${NC}"
else
    echo -e "${RED}⚠️  Mock viewer may still be starting up${NC}"
fi

# Check if viewer-history.html is being served
if curl -s http://localhost:8090/viewer | grep -q "History View" 2>/dev/null; then
    echo -e "${GREEN}✅ New history viewer is being served${NC}"
else
    echo -e "${YELLOW}ℹ️  Using standard viewer (history viewer may need manual refresh)${NC}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✨ Rebuild complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. View the interface: http://localhost:8090/viewer"
echo "  2. Run example app: ./transparent-capture.sh run './example-app/example-server'"
echo "  3. Test endpoints: ./example-app/test.sh"
echo ""
echo "Alternative capture methods:"
echo "  • Transparent proxy: Already running (automatic)"
echo "  • Standard proxy: go run cmd/capture/main.go (port 8091)"
echo ""
echo "To view logs:"
echo "  • All containers: docker compose -f docker-compose-transparent.yml logs -f"
echo "  • Proxy only: docker logs transparent-proxy -f"
echo ""