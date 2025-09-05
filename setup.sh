#!/bin/bash

# Setup script for Transparent HTTPS Proxy System
# Run this once when setting up on a new machine

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Transparent HTTPS Proxy Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

MISSING_DEPS=()

if ! command_exists docker; then
    MISSING_DEPS+=("docker")
fi

if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
    MISSING_DEPS+=("docker-compose")
fi

if ! command_exists go; then
    MISSING_DEPS+=("go")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}✗ Missing dependencies:${NC}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Please install the missing dependencies and run this script again."
    echo ""
    echo "Installation guides:"
    echo "  Docker: https://docs.docker.com/get-docker/"
    echo "  Go: https://golang.org/dl/"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Build binaries for current architecture
echo -e "${YELLOW}Building binaries for your architecture...${NC}"
if [ -f "./build.sh" ]; then
    ./build.sh
else
    echo -e "${RED}✗ build.sh not found${NC}"
    echo "Creating build.sh..."
    cat > build.sh << 'EOF'
#!/bin/bash
set -e
echo "Building binaries..."
CGO_ENABLED=0 GOOS=linux go build -a -ldflags '-extldflags "-static"' -o main rest-server.go
CGO_ENABLED=0 GOOS=linux go build -a -ldflags '-extldflags "-static"' -o test-server test-server.go
chmod +x main test-server
echo "✓ Binaries built"
EOF
    chmod +x build.sh
    ./build.sh
fi

# Make all scripts executable
echo -e "\n${YELLOW}Setting up permissions...${NC}"
chmod +x transparent-capture.sh 2>/dev/null || true
chmod +x test-connection.sh 2>/dev/null || true
chmod +x build.sh 2>/dev/null || true
chmod +x setup.sh 2>/dev/null || true
echo -e "${GREEN}✓ Scripts are executable${NC}"

# Create necessary directories
echo -e "\n${YELLOW}Creating directories...${NC}"
mkdir -p captured configs scripts docker 2>/dev/null || true
echo -e "${GREEN}✓ Directories ready${NC}"

# Pull/Build Docker images
echo -e "\n${YELLOW}Building Docker images...${NC}"
echo "This may take a few minutes on first run..."
docker compose -f docker-compose-transparent.yml build
echo -e "${GREEN}✓ Docker images built${NC}"

# Display quick start guide
echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${BLUE}Quick Start Guide:${NC}"
echo ""
echo "1. Start the system:"
echo -e "   ${YELLOW}./transparent-capture.sh start${NC}"
echo ""
echo "2. Start the server:"
echo -e "   ${YELLOW}./transparent-capture.sh server${NC}"
echo ""
echo "3. Test the connection:"
echo -e "   ${YELLOW}curl http://localhost:8080/api/health${NC}"
echo ""
echo -e "${BLUE}Alternative - Start everything at once:${NC}"
echo -e "   ${YELLOW}./transparent-capture.sh start --with-server${NC}"
echo ""
echo -e "${BLUE}Other useful commands:${NC}"
echo "  • View logs: ./transparent-capture.sh app-logs"
echo "  • Run test: ./test-connection.sh"
echo "  • Stop server: ./transparent-capture.sh stop-server"
echo "  • Stop all: ./transparent-capture.sh stop"
echo ""
echo -e "${GREEN}Happy proxying! 🚀${NC}"