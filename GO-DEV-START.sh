#!/bin/bash
# GO-DEV-START.sh - Complete setup and run for Go development

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
PROJECT_DIR="${1:-.}"
APP_PORT="${2:-8080}"

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR] [PORT]"
    echo ""
    echo "Complete Go development environment setup and run"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_DIR  Path to your Go project (default: current directory)"
    echo "  PORT         Port to expose for your app (default: 8080)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Current directory, port 8080"
    echo "  $0 ~/projects/my-api         # Specific project"
    echo "  $0 ~/projects/my-api 3000    # Custom port"
    echo ""
    exit 0
fi

# Expand and validate path
PROJECT_DIR=$(eval echo "$PROJECT_DIR")
PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")

if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ Project directory not found: $PROJECT_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🐹 Go Development Environment Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Project:${NC} $PROJECT_DIR"
echo -e "${GREEN}Port:${NC}    $APP_PORT"
echo ""

# Step 1: Check if setup is needed
if ! docker images | grep -q go-dev-alpine; then
    echo -e "${YELLOW}Setting up Docker environment...${NC}"
    ./GO-DEV-FIXED.sh "$PROJECT_DIR"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Setup failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Docker image already exists${NC}"
    
    # Check if mitmproxy is running
    if ! docker ps | grep -q mitmproxy; then
        echo -e "${YELLOW}Starting mitmproxy...${NC}"
        docker run -d \
            --name mitmproxy \
            -p 8082:8082 \
            mitmproxy/mitmproxy \
            mitmdump --listen-port 8082 --ssl-insecure
        sleep 3
    else
        echo -e "${GREEN}✅ Mitmproxy already running${NC}"
    fi
fi

# Step 2: Run the development container
echo ""
echo -e "${YELLOW}Starting development container...${NC}"
echo ""

./go-dev-run.sh "$PROJECT_DIR" "$APP_PORT"