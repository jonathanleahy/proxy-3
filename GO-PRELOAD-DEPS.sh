#!/bin/bash
# GO-PRELOAD-DEPS.sh - Pre-download all Go dependencies for faster development

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}📦 Go Dependencies Pre-loader${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Parse arguments
PROJECT_DIR="${1:-.}"

if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR]"
    echo ""
    echo "Pre-download all Go dependencies from your project"
    echo ""
    echo "This script will:"
    echo "  1. Read your go.mod file"
    echo "  2. Download all dependencies to Docker volumes"
    echo "  3. Optionally build a custom image with deps baked in"
    echo ""
    echo "Examples:"
    echo "  $0                    # Current directory"
    echo "  $0 ~/projects/my-api  # Specific project"
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

# Check for go.mod
if [ ! -f "$PROJECT_DIR/go.mod" ]; then
    echo -e "${RED}❌ No go.mod found in: $PROJECT_DIR${NC}"
    echo "This script requires a go.mod file to know which dependencies to download"
    exit 1
fi

echo -e "${GREEN}✅ Found go.mod in: $PROJECT_DIR${NC}"

# Method 1: Pre-warm the cache volumes
echo ""
echo -e "${YELLOW}Method 1: Pre-warming Docker cache volumes...${NC}"

# Create volumes if they don't exist
docker volume create go-dev-cache 2>/dev/null
docker volume create go-dev-modules 2>/dev/null

# Check if base image exists
if ! docker images | grep -q go-dev-alpine; then
    echo "Building base Go development image..."
    cat > Dockerfile.go-base << 'EOF'
FROM golang:alpine
RUN apk add --no-cache ca-certificates git
WORKDIR /go/src/app
EOF
    docker build -t go-dev-alpine -f Dockerfile.go-base .
    rm Dockerfile.go-base
fi

# Run container to download dependencies
echo "Downloading dependencies to cache volumes..."
docker run --rm \
    -v "$PROJECT_DIR:/go/src/app" \
    -v go-dev-cache:/go/.cache \
    -v go-dev-modules:/go/pkg/mod \
    go-dev-alpine \
    sh -c "
        echo 'Downloading all dependencies...'
        go mod download
        echo ''
        echo 'Building packages to populate build cache...'
        go build -v ./... 2>/dev/null || true
        echo ''
        echo 'Dependencies cached successfully!'
        echo ''
        echo 'Cached modules:'
        ls -la /go/pkg/mod/cache/download/ 2>/dev/null | head -20
    "

echo -e "${GREEN}✅ Dependencies cached in Docker volumes${NC}"

# Method 2: Create custom image with dependencies baked in
echo ""
echo -e "${YELLOW}Method 2: Creating custom image with dependencies...${NC}"

# Copy go.mod and go.sum to temp location
cp "$PROJECT_DIR/go.mod" .
cp "$PROJECT_DIR/go.sum" . 2>/dev/null || touch go.sum

# Get project name from go.mod
PROJECT_NAME=$(grep "^module " go.mod | awk '{print $2}' | sed 's/[^a-zA-Z0-9-]/-/g')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="go-app"
fi

echo "Creating custom image: go-dev-$PROJECT_NAME"

# Create Dockerfile with dependencies pre-downloaded
cat > Dockerfile.go-preloaded << 'EOF'
FROM golang:alpine

# Install required packages
RUN apk add --no-cache ca-certificates git

# Set up cache directories
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

# Copy go.mod and go.sum
WORKDIR /tmp/deps
COPY go.mod go.sum ./

# Download all dependencies (this layer will be cached)
RUN go mod download

# Pre-compile standard library and common packages
RUN go build -v std 2>/dev/null || true

# Set final working directory
WORKDIR /go/src/app

# Copy go.mod/go.sum to app directory too
COPY go.mod go.sum ./

CMD ["/bin/sh"]
EOF

# Build the custom image
docker build -t "go-dev-$PROJECT_NAME" -f Dockerfile.go-preloaded .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Custom image built: go-dev-$PROJECT_NAME${NC}"
    
    # Create custom run script
    cat > "run-$PROJECT_NAME.sh" << EOF
#!/bin/bash
# Auto-generated script to run $PROJECT_NAME with pre-loaded dependencies

docker run --rm -it \\
    -v "$PROJECT_DIR:/go/src/app" \\
    -v go-dev-cache:/go/.cache \\
    -v go-dev-modules:/go/pkg/mod \\
    -p 8080:8080 \\
    --add-host host.docker.internal:host-gateway \\
    go-dev-$PROJECT_NAME \\
    sh -c "
        echo '🚀 $PROJECT_NAME Development Environment'
        echo '📦 Dependencies are pre-loaded!'
        echo ''
        ls -la
        echo ''
        /bin/sh
    "
EOF
    chmod +x "run-$PROJECT_NAME.sh"
    echo -e "${GREEN}✅ Created run script: run-$PROJECT_NAME.sh${NC}"
else
    echo -e "${YELLOW}Custom image build failed, but cache volumes are ready${NC}"
fi

# Clean up temp files
rm -f go.mod go.sum Dockerfile.go-preloaded

# Method 3: Vendor dependencies (optional)
echo ""
echo -e "${YELLOW}Method 3: Vendor dependencies locally (optional)...${NC}"
echo "Would you like to vendor dependencies? (y/n)"
read -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker run --rm \
        -v "$PROJECT_DIR:/go/src/app" \
        go-dev-alpine \
        sh -c "go mod vendor"
    
    if [ -d "$PROJECT_DIR/vendor" ]; then
        echo -e "${GREEN}✅ Dependencies vendored to: $PROJECT_DIR/vendor${NC}"
        echo "Your app can now use -mod=vendor flag for offline builds"
    fi
fi

# Summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  📦 Dependencies Pre-loaded Successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Your dependencies are now cached in THREE ways:"
echo ""
echo "1. ${GREEN}Docker Volumes${NC} - Persistent cache across containers"
echo "   Volumes: go-dev-cache, go-dev-modules"
echo ""
echo "2. ${GREEN}Custom Image${NC} - Image with deps baked in"
echo "   Image: go-dev-$PROJECT_NAME"
if [ -f "run-$PROJECT_NAME.sh" ]; then
    echo "   Run: ./run-$PROJECT_NAME.sh"
fi
echo ""
if [ -d "$PROJECT_DIR/vendor" ]; then
    echo "3. ${GREEN}Vendored${NC} - Local vendor directory"
    echo "   Path: $PROJECT_DIR/vendor"
    echo "   Use: go build -mod=vendor"
    echo ""
fi
echo "🚀 Starting your container will now be MUCH faster!"
echo ""
echo "Next steps:"
echo "  ./GO-DEV-START.sh $PROJECT_DIR    # Dependencies will load instantly!"