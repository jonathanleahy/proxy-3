#!/bin/bash
# BUILD-GO-IMAGE-WITH-DEPS.sh - Build a Docker image with all your deps pre-installed

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🏗️  Build Go Image with Dependencies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

PROJECT_DIR="${1:-.}"

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR]"
    echo ""
    echo "Build a custom Docker image with all your project dependencies pre-installed"
    echo ""
    echo "Benefits:"
    echo "  • Zero download time when starting containers"
    echo "  • Dependencies are baked into the image layers"
    echo "  • Perfect for CI/CD and team sharing"
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
IMAGE_NAME="go-dev-${PROJECT_NAME,,}"  # lowercase

echo -e "${GREEN}Project:${NC} $PROJECT_DIR"
echo -e "${GREEN}Image:${NC}   $IMAGE_NAME"
echo ""

# Copy go files
cp "$PROJECT_DIR/go.mod" .
cp "$PROJECT_DIR/go.sum" . 2>/dev/null || touch go.sum

# Check if mitmproxy cert exists
if [ ! -f mitmproxy-ca.pem ]; then
    echo "Creating placeholder certificate..."
    touch mitmproxy-ca.pem
fi

# Create optimized Dockerfile
cat > Dockerfile.go-with-deps << 'EOF'
# Multi-stage build for optimal caching
FROM golang:alpine AS deps

# Install build dependencies
RUN apk add --no-cache ca-certificates git

# Set up module cache
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

# Copy go mod files (this layer caches until go.mod changes)
WORKDIR /deps
COPY go.mod go.sum ./

# Download all dependencies (cached layer)
RUN go mod download

# Pre-build standard library (cached layer)
RUN go build -v std

# Optional: Pre-build some of your packages for faster compilation
# COPY . .
# RUN go build -v ./...

# Final stage
FROM golang:alpine

# Install runtime dependencies
RUN apk add --no-cache ca-certificates git

# Copy dependency cache from deps stage
COPY --from=deps /go/pkg /go/pkg
COPY --from=deps /go/.cache /go/.cache

# Install mitmproxy certificate for HTTPS capture
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates 2>/dev/null || true

# Set environment
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CGO_ENABLED=0
ENV GOOS=linux

WORKDIR /go/src/app

# Copy go.mod/go.sum to working directory too
COPY go.mod go.sum ./

# Your dependencies are now pre-installed!
CMD ["/bin/sh"]
EOF

echo -e "${YELLOW}Building image with dependencies...${NC}"
echo "This will take a moment but will make starts instant..."
echo ""

# Build the image
if docker build -t "$IMAGE_NAME" -f Dockerfile.go-with-deps . --progress=plain; then
    echo ""
    echo -e "${GREEN}✅ Image built successfully: $IMAGE_NAME${NC}"
    
    # Show image size
    SIZE=$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep "$IMAGE_NAME" | awk '{print $3}')
    echo -e "${GREEN}Image size:${NC} $SIZE"
    
    # Create optimized run script
    cat > "run-${PROJECT_NAME}-fast.sh" << EOF
#!/bin/bash
# Ultra-fast startup with pre-cached dependencies

echo "🚀 Starting $PROJECT_NAME (dependencies pre-loaded)"
docker run --rm -it \\
    -v "$PROJECT_DIR:/go/src/app" \\
    -p 8080:8080 \\
    --add-host host.docker.internal:host-gateway \\
    $IMAGE_NAME \\
    sh -c "
        echo '⚡ Dependencies are already installed!'
        echo 'No downloading needed - start coding immediately!'
        echo ''
        ls -la
        echo ''
        /bin/sh
    "
EOF
    chmod +x "run-${PROJECT_NAME}-fast.sh"
    
    echo ""
    echo -e "${GREEN}✅ Created fast-start script: run-${PROJECT_NAME}-fast.sh${NC}"
else
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Clean up
rm -f go.mod go.sum Dockerfile.go-with-deps

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ⚡ Optimized Image Ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your custom image '$IMAGE_NAME' includes:"
echo "  ✅ All Go dependencies from go.mod"
echo "  ✅ Pre-compiled standard library"
echo "  ✅ Trusted certificates for HTTPS"
echo "  ✅ Git for version control"
echo ""
echo "Start instantly with:"
echo "  ${GREEN}./run-${PROJECT_NAME}-fast.sh${NC}"
echo ""
echo "Or use directly:"
echo "  ${GREEN}docker run --rm -it -v $PROJECT_DIR:/go/src/app $IMAGE_NAME${NC}"
echo ""
echo "🎯 Container startup is now INSTANT - no downloads needed!"