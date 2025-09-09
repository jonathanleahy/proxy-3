#!/bin/bash
# Test what Docker images can be pulled

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Testing Docker image availability..."
echo "====================================="
echo ""

# Test alpine
echo -e "${YELLOW}Testing alpine:latest...${NC}"
if docker pull alpine:latest 2>/dev/null; then
    echo -e "${GREEN}✅ alpine:latest available${NC}"
else
    echo -e "${RED}❌ alpine:latest NOT available${NC}"
fi

# Test ubuntu
echo -e "${YELLOW}Testing ubuntu:latest...${NC}"
if docker pull ubuntu:latest 2>/dev/null; then
    echo -e "${GREEN}✅ ubuntu:latest available${NC}"
else
    echo -e "${RED}❌ ubuntu:latest NOT available${NC}"
fi

# Test busybox
echo -e "${YELLOW}Testing busybox:latest...${NC}"
if docker pull busybox:latest 2>/dev/null; then
    echo -e "${GREEN}✅ busybox:latest available${NC}"
else
    echo -e "${RED}❌ busybox:latest NOT available${NC}"
fi

# Check what images are already available locally
echo ""
echo -e "${YELLOW}Images already on your system:${NC}"
docker images | grep -E "alpine|golang|ubuntu|busybox" || echo "None of the common base images found"

echo ""
echo -e "${YELLOW}All available images:${NC}"
docker images