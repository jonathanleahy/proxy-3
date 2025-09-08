#!/bin/bash
# Rebuild script for transparent proxy system

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔨 Rebuilding Transparent Proxy System${NC}"
echo "========================================="

# Parse arguments
RESTART=true
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-restart)
            RESTART=false
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Rebuild Docker containers for the transparent proxy system."
            echo ""
            echo "OPTIONS:"
            echo "  --no-restart   Don't restart containers after rebuild"
            echo "  --clean        Clean build (no cache)"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Stop existing containers
echo -e "${YELLOW}Stopping existing containers...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true

# Build containers
echo -e "${YELLOW}Building containers...${NC}"
if [ "$CLEAN" = true ]; then
    echo "Performing clean build (no cache)..."
    docker compose -f docker-compose-transparent.yml build --no-cache
else
    docker compose -f docker-compose-transparent.yml build
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

# Restart if requested
if [ "$RESTART" = true ]; then
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose -f docker-compose-transparent.yml up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Containers started${NC}"
        echo ""
        echo "Run ./start-proxy-system.sh to start your application"
    else
        echo -e "${RED}❌ Failed to start containers${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}ℹ️  Containers not started (--no-restart flag used)${NC}"
    echo "Run 'docker compose -f docker-compose-transparent.yml up -d' to start"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 Rebuild complete!${NC}"
echo -e "${BLUE}=========================================${NC}"