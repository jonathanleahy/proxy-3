#!/bin/bash
# GO-QUICK-START.sh - Fastest way to run your Go app with pre-downloaded deps

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Go Quick Start - Run Your App with Pre-downloaded Dependencies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

PROJECT_DIR="${1:-.}"

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR]"
    echo ""
    echo "Quickest way to run your Go app with all dependencies pre-downloaded."
    echo ""
    echo "This script will:"
    echo "  1. Download all Go dependencies locally (on your host machine)"
    echo "  2. Create a Docker image with those dependencies baked in"
    echo "  3. Run your app instantly without any network downloads"
    echo ""
    echo "Example:"
    echo "  $0 ~/projects/my-api"
    echo ""
    echo "Then in the container:"
    echo "  go run ./cmd/api/main.go  # Runs instantly, no downloads!"
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

PROJECT_NAME=$(basename "$PROJECT_DIR")
echo -e "${GREEN}Project:${NC} $PROJECT_DIR"
echo -e "${GREEN}Name:${NC}    $PROJECT_NAME"
echo ""

# Step 1: Check if we already have a built image
if docker images | grep -q "go-quick-$PROJECT_NAME"; then
    echo -e "${GREEN}✅ Image already exists, starting container...${NC}"
else
    echo -e "${YELLOW}Building optimized image with dependencies...${NC}"
    echo "This is one-time setup, future starts will be instant!"
    echo ""
    
    # Copy go.mod and go.sum
    cp "$PROJECT_DIR/go.mod" .
    cp "$PROJECT_DIR/go.sum" . 2>/dev/null || touch go.sum
    
    # Ensure mitmproxy cert exists (for HTTPS interception)
    if [ ! -f mitmproxy-ca.pem ]; then
        # Check if mitmproxy is running
        if docker ps | grep -q mitmproxy; then
            docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null
        else
            # Create empty cert file if mitmproxy isn't running
            touch mitmproxy-ca.pem
        fi
    fi
    
    # Create optimized Dockerfile
    cat > Dockerfile.quick << 'EOF'
# Stage 1: Download all dependencies
FROM golang:alpine AS deps
RUN apk add --no-cache ca-certificates git
WORKDIR /deps
COPY go.mod go.sum ./
# This downloads ALL your dependencies during build
RUN go mod download && go build -v std

# Stage 2: Final image with dependencies
FROM golang:alpine
RUN apk add --no-cache ca-certificates git bash

# Copy all downloaded dependencies from stage 1
COPY --from=deps /go/pkg /go/pkg
COPY --from=deps /go/.cache /go/.cache

# Trust mitmproxy certificate for HTTPS capture
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates 2>/dev/null || true

# Environment setup
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082

WORKDIR /app

# Copy go.mod/go.sum to app directory
COPY go.mod go.sum ./

CMD ["/bin/bash"]
EOF
    
    # Build the image
    echo "Building image (this caches all dependencies)..."
    docker build -t "go-quick-$PROJECT_NAME" -f Dockerfile.quick . --progress=plain
    
    # Clean up
    rm -f go.mod go.sum Dockerfile.quick
    
    echo ""
    echo -e "${GREEN}✅ Image built with all dependencies cached!${NC}"
fi

# Step 2: Run the container
echo ""
echo -e "${YELLOW}Starting container with your app...${NC}"
echo ""

# Check if mitmproxy is running for HTTPS capture
if ! docker ps | grep -q mitmproxy; then
    echo "Starting mitmproxy for HTTPS capture..."
    docker run -d \
        --name mitmproxy \
        -p 8082:8082 \
        mitmproxy/mitmproxy \
        mitmdump --listen-port 8082 --ssl-insecure
    sleep 2
fi

# Run the container with your app mounted
docker run --rm -it \
    -v "$PROJECT_DIR:/app" \
    -p 8080:8080 \
    -p 8081:8081 \
    -p 8090:8090 \
    --add-host host.docker.internal:host-gateway \
    --name "go-app-$PROJECT_NAME" \
    "go-quick-$PROJECT_NAME" \
    bash -c "
        echo '═══════════════════════════════════════════════'
        echo '✅ Container Ready with Pre-downloaded Dependencies!'
        echo '═══════════════════════════════════════════════'
        echo ''
        echo '📦 ALL Go dependencies are already cached in this image!'
        echo '🚀 No network downloads needed - start coding immediately!'
        echo ''
        echo 'Your app is mounted at: /app'
        echo ''
        echo 'Run your app with:'
        echo '  ${GREEN}go run ./cmd/api/main.go${NC}'
        echo ''
        echo 'Or if your main is in a different location:'
        echo '  ${GREEN}go run main.go${NC}'
        echo '  ${GREEN}go run ./cmd/main.go${NC}'
        echo ''
        echo 'The app will start INSTANTLY - all deps are pre-downloaded! 🎉'
        echo ''
        echo 'Ports mapped:'
        echo '  • 8080 → 8080 (main app)'
        echo '  • 8081 → 8081 (alternative)'
        echo '  • 8090 → 8090 (mock server)'
        echo ''
        echo 'HTTPS traffic is automatically captured via mitmproxy'
        echo ''
        ls -la
        echo ''
        exec /bin/bash
    "