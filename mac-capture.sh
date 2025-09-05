#!/bin/bash

# Helper script for Mac users to cross-compile and run in transparent capture

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-go-source>"
    echo "Example: $0 ~/work/test/main.go"
    exit 1
fi

SOURCE_PATH="$1"
SOURCE_DIR=$(dirname "$SOURCE_PATH")
SOURCE_FILE=$(basename "$SOURCE_PATH")
BINARY_NAME="${SOURCE_FILE%.go}-linux"

echo -e "${YELLOW}🔨 Cross-compiling for Linux...${NC}"

# Save current directory
ORIGINAL_DIR=$(pwd)

# Go to source directory and compile
cd "$SOURCE_DIR"
GOOS=linux GOARCH=amd64 go build -o "$BINARY_NAME" "$SOURCE_FILE"

echo -e "${GREEN}✅ Compiled to $BINARY_NAME${NC}"

# Return to proxy directory
cd "$ORIGINAL_DIR"

echo -e "${YELLOW}🚀 Running in transparent capture container...${NC}"

# Run the Linux binary in container
./transparent-capture.sh run "cd $SOURCE_DIR && ./$BINARY_NAME"