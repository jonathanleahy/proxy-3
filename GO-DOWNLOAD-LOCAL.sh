#!/bin/bash
# GO-DOWNLOAD-LOCAL.sh - Download Go dependencies locally, then use in container

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}📦 Download Go Dependencies Locally${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

PROJECT_DIR="${1:-.}"

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR]"
    echo ""
    echo "Download Go dependencies on your LOCAL machine first,"
    echo "then mount them into the container."
    echo ""
    echo "This solves network issues from within containers."
    echo ""
    exit 0
fi

# Validate project
PROJECT_DIR=$(eval echo "$PROJECT_DIR")
PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")

if [ ! -f "$PROJECT_DIR/go.mod" ]; then
    echo -e "${RED}❌ No go.mod found in: $PROJECT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}Project:${NC} $PROJECT_DIR"
echo ""

# Step 1: Check if Go is installed locally
if command -v go &> /dev/null; then
    echo -e "${GREEN}✅ Go is installed locally${NC}"
    GO_VERSION=$(go version)
    echo "Version: $GO_VERSION"
    
    # Download dependencies locally
    echo ""
    echo -e "${YELLOW}Downloading dependencies locally...${NC}"
    cd "$PROJECT_DIR"
    
    # Set GOPROXY to ensure we can download
    export GOPROXY=https://proxy.golang.org,direct
    
    # Download all dependencies
    go mod download -x
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Dependencies downloaded locally${NC}"
        
        # Show where they are
        echo ""
        echo "Local Go module cache:"
        echo "  ${GREEN}$HOME/go/pkg/mod${NC}"
        
        # Check size
        if [ -d "$HOME/go/pkg/mod" ]; then
            SIZE=$(du -sh "$HOME/go/pkg/mod" 2>/dev/null | cut -f1)
            echo "  Size: $SIZE"
        fi
    else
        echo -e "${YELLOW}Some dependencies may have failed, continuing...${NC}"
    fi
else
    echo -e "${YELLOW}Go not installed locally, using Docker...${NC}"
    
    # Use Docker to download to a local directory
    mkdir -p "$PROJECT_DIR/.go-cache"
    
    docker run --rm \
        -v "$PROJECT_DIR:/app" \
        -v "$PROJECT_DIR/.go-cache:/go/pkg/mod" \
        -w /app \
        golang:alpine \
        sh -c "go mod download"
    
    echo -e "${GREEN}✅ Dependencies downloaded to $PROJECT_DIR/.go-cache${NC}"
fi

# Step 2: Create script to run with local cache mounted
echo ""
echo -e "${YELLOW}Creating script to use local cache...${NC}"

# Determine cache location
if [ -d "$HOME/go/pkg/mod" ]; then
    CACHE_DIR="$HOME/go/pkg/mod"
    BUILD_CACHE="$HOME/.cache/go-build"
elif [ -d "$PROJECT_DIR/.go-cache" ]; then
    CACHE_DIR="$PROJECT_DIR/.go-cache"
    BUILD_CACHE="$PROJECT_DIR/.go-build-cache"
else
    echo -e "${RED}No cache directory found${NC}"
    exit 1
fi

cat > run-with-local-cache.sh << EOF
#!/bin/bash
# Run container with LOCAL Go cache mounted (no downloads needed!)

echo "🚀 Starting container with local Go cache"
echo "📦 Using cache from: $CACHE_DIR"
echo ""

# Ensure mitmproxy is running for HTTPS capture
if ! docker ps | grep -q mitmproxy; then
    echo "Starting mitmproxy..."
    docker run -d \\
        --name mitmproxy \\
        -p 8082:8082 \\
        mitmproxy/mitmproxy \\
        mitmdump --listen-port 8082 --ssl-insecure
    sleep 3
fi

# Get mitmproxy cert if needed
if [ ! -f mitmproxy-ca.pem ]; then
    docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || true
fi

# Build image if needed
if ! docker images | grep -q go-with-local-cache; then
    cat > Dockerfile.local-cache << 'DOCKERFILE'
FROM golang:alpine
RUN apk add --no-cache ca-certificates git
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates 2>/dev/null || true
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082
WORKDIR /app
CMD ["/bin/sh"]
DOCKERFILE
    docker build -t go-with-local-cache -f Dockerfile.local-cache .
    rm Dockerfile.local-cache
fi

# Run with local cache mounted
docker run --rm -it \\
    -v "$PROJECT_DIR:/app" \\
    -v "$CACHE_DIR:/go/pkg/mod:ro" \\
    -v "$BUILD_CACHE:/root/.cache/go-build" \\
    -p 8080:8080 \\
    --add-host host.docker.internal:host-gateway \\
    go-with-local-cache \\
    sh -c "
        echo '✅ Container started with local Go cache mounted!'
        echo '📦 No network downloads needed - using local cache'
        echo ''
        echo 'Your app is at: /app'
        echo 'Go cache is at: /go/pkg/mod (read-only)'
        echo ''
        echo 'Run your app:'
        echo '  go run ./cmd/api/main.go'
        echo ''
        echo 'The dependencies are already available locally!'
        echo ''
        ls -la
        echo ''
        /bin/sh
    "
EOF

chmod +x run-with-local-cache.sh

echo -e "${GREEN}✅ Created: run-with-local-cache.sh${NC}"

# Step 3: Alternative - vendor dependencies
echo ""
echo -e "${YELLOW}Alternative: Vendor dependencies into project...${NC}"

cat > vendor-deps.sh << 'EOF'
#!/bin/bash
# Vendor all dependencies into the project

cd "$PROJECT_DIR"
go mod vendor

echo "✅ Dependencies vendored to: $PROJECT_DIR/vendor"
echo ""
echo "Now you can run with -mod=vendor flag:"
echo "  go run -mod=vendor ./cmd/api/main.go"
EOF

chmod +x vendor-deps.sh

echo -e "${GREEN}✅ Created: vendor-deps.sh${NC}"

# Summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Local Dependencies Ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your dependencies are downloaded locally at:"
echo "  ${GREEN}$CACHE_DIR${NC}"
echo ""
echo "Option 1: Run with local cache mounted:"
echo "  ${GREEN}./run-with-local-cache.sh${NC}"
echo ""
echo "Option 2: Vendor dependencies (copy to project):"
echo "  ${GREEN}./vendor-deps.sh${NC}"
echo ""
echo "Both options work OFFLINE - no network needed in container!"
echo ""
echo "In the container, just run:"
echo "  ${GREEN}go run ./cmd/api/main.go${NC}"
echo ""
echo "The dependencies will load from local cache instantly! 🚀"