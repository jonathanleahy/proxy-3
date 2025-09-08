#!/bin/bash

# Build script for example-app
# Builds for Linux/AMD64 to run in Docker container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Building example-app for Linux/AMD64...${NC}"

# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Build for Linux/AMD64 (Docker container architecture)
GOOS=linux GOARCH=amd64 go build -o example-server main.go

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo -e "${GREEN}Binary: example-server (Linux/AMD64)${NC}"
    echo ""
    echo "To run with transparent capture:"
    echo -e "${YELLOW}  ../transparent-capture.sh start${NC}"
    echo -e "${YELLOW}  ../transparent-capture.sh run './example-app/example-server'${NC}"
else
    echo -e "${YELLOW}❌ Build failed${NC}"
    exit 1
fi