#!/bin/bash

# Build script for transparent proxy servers
# Builds static binaries for any architecture

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   Building Transparent Proxy Servers${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Detect architecture
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

echo -e "${YELLOW}Detected OS: $OS, Architecture: $ARCH${NC}"

# Set GOARCH based on architecture
case "$ARCH" in
    x86_64)
        GOARCH="amd64"
        ;;
    aarch64|arm64)
        GOARCH="arm64"
        ;;
    armv7l)
        GOARCH="arm"
        ;;
    *)
        echo -e "${YELLOW}Unknown architecture: $ARCH, defaulting to amd64${NC}"
        GOARCH="amd64"
        ;;
esac

# Build main server
echo -e "\n${BLUE}Building main server...${NC}"
CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -a -ldflags '-extldflags "-static"' -o main rest-server.go
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ main server built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build main server${NC}"
    exit 1
fi

# Build test server
echo -e "\n${BLUE}Building test server...${NC}"
CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -a -ldflags '-extldflags "-static"' -o test-server test-server.go
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ test-server built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build test-server${NC}"
    exit 1
fi

# Build mock server for cmd/main.go if it exists
if [ -f "cmd/main.go" ]; then
    echo -e "\n${BLUE}Building mock server...${NC}"
    CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -a -ldflags '-extldflags "-static"' -o mock-server cmd/main.go
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ mock-server built successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to build mock-server (optional)${NC}"
    fi
fi

# Build capture proxy if it exists
if [ -f "cmd/capture/main.go" ]; then
    echo -e "\n${BLUE}Building capture proxy...${NC}"
    CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -a -ldflags '-extldflags "-static"' -o capture-proxy cmd/capture/main.go
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ capture-proxy built successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to build capture-proxy (optional)${NC}"
    fi
fi

# Make binaries executable
chmod +x main test-server 2>/dev/null || true
chmod +x mock-server capture-proxy 2>/dev/null || true

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}✅ Build complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Binaries built for: Linux $GOARCH"
echo "  • main - REST server"
echo "  • test-server - Test server"
if [ -f "mock-server" ]; then
    echo "  • mock-server - Mock API server"
fi
if [ -f "capture-proxy" ]; then
    echo "  • capture-proxy - Capture proxy"
fi
echo ""
echo "To use the system:"
echo "  1. ./transparent-capture.sh start"
echo "  2. ./transparent-capture.sh server"
echo "  3. curl http://localhost:8080/api/health"