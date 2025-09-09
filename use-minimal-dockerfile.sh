#!/bin/bash
# Switch to minimal Dockerfile for restricted environments

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔄 Switching to Minimal Dockerfile${NC}"
echo "============================================"
echo "This version works in restricted environments without package installation"
echo ""

# Backup original files
echo -e "${YELLOW}Backing up original files...${NC}"
cp docker/Dockerfile.app docker/Dockerfile.app.original 2>/dev/null || true
cp docker/app-entry.sh docker/app-entry.sh.original 2>/dev/null || true

# Switch to minimal version
echo -e "${YELLOW}Switching to minimal version...${NC}"
cp docker/Dockerfile.app.minimal docker/Dockerfile.app
cp docker/app-entry-minimal.sh docker/app-entry.sh

echo -e "${GREEN}✅ Switched to minimal Dockerfile${NC}"
echo ""
echo -e "${YELLOW}Now rebuild and start:${NC}"
echo "  ./rebuild-proxy.sh --clean"
echo "  ./start-proxy-system.sh"
echo ""
echo -e "${YELLOW}To restore original version:${NC}"
echo "  mv docker/Dockerfile.app.original docker/Dockerfile.app"
echo "  mv docker/app-entry.sh.original docker/app-entry.sh"