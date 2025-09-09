#!/bin/bash
# GO-DEV-WITH-TRUSTED-CERTS.sh - Go development with trusted certificates and persistent cache

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🐹 Go Development with Trusted HTTPS Capture${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "✅ No InsecureSkipVerify needed"
echo "✅ No Go package re-downloads" 
echo "✅ Full HTTPS body capture"
echo "✅ Easy development workflow"
echo ""

# Parse arguments
GO_APP_PATH="${1:-~/temp/aa}"
if [ "$GO_APP_PATH" = "--help" ] || [ "$GO_APP_PATH" = "-h" ]; then
    echo "Usage: $0 [GO_APP_PATH]"
    echo ""
    echo "GO_APP_PATH: Path to your Go application (default: ~/temp/aa)"
    echo ""
    echo "Examples:"
    echo "  $0                      # Use default ~/temp/aa"
    echo "  $0 ~/my-project        # Use custom path"
    echo ""
    exit 0
fi

# Expand tilde
GO_APP_PATH=$(eval echo "$GO_APP_PATH")

if [ ! -d "$GO_APP_PATH" ]; then
    echo -e "${RED}❌ Go app directory not found: $GO_APP_PATH${NC}"
    echo "Please provide the correct path to your Go application"
    exit 1
fi

echo -e "${YELLOW}🎯 Using Go app at: $GO_APP_PATH${NC}"

# Step 1: Start mitmproxy with certificate trust
echo ""
echo -e "${YELLOW}Step 1: Setting up trusted HTTPS proxy...${NC}"

# Clean up any existing mitmproxy
docker stop mitmproxy 2>/dev/null || true
docker rm mitmproxy 2>/dev/null || true

# Start mitmproxy on port 8082
docker run -d \
    --name mitmproxy \
    -p 8082:8082 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8082 --ssl-insecure

sleep 4

# Get certificate
echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

if [ ! -s mitmproxy-ca.pem ]; then
    echo -e "${RED}❌ Failed to get certificate${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Certificate ready ($(wc -c < mitmproxy-ca.pem) bytes)${NC}"

# Step 2: Create Go development container with certificate and cache
echo ""
echo -e "${YELLOW}Step 2: Creating Go dev container with trusted certificates...${NC}"

# Check if go.mod exists in the app directory
if [ -f "$GO_APP_PATH/go.mod" ]; then
    echo -e "${GREEN}✅ Found go.mod in $GO_APP_PATH${NC}"
    cp "$GO_APP_PATH/go.mod" .
    cp "$GO_APP_PATH/go.sum" . 2>/dev/null || touch go.sum
else
    echo -e "${YELLOW}⚠️  No go.mod found, creating minimal one...${NC}"
    echo -e "${BLUE}💡 You may need to run 'go mod init your-module-name' in your app directory${NC}"
    cat > go.mod << 'EOF'
module temp-app

go 1.21

require ()
EOF
    touch go.sum
fi

# Create Dockerfile for Go development with certificate trust and caching
cat > Dockerfile.go-dev-trusted << 'EOF'
FROM golang:1.21-alpine3.19

# Install ca-certificates and git
RUN apk add --no-cache ca-certificates git

# Copy and install mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Set up Go cache directories
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

# Create app directory
WORKDIR /go/src/app

# Copy go.mod and go.sum for better layer caching
COPY go.mod go.sum ./

# Download dependencies (this layer will be cached)
RUN go mod download

# Set proxy environment
ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082

# Set working directory
WORKDIR /go/src/app

CMD ["/bin/sh"]
EOF

echo -e "${YELLOW}Building Go dev container (this may take a moment)...${NC}"
docker build -t go-dev-trusted -f Dockerfile.go-dev-trusted .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Go dev container built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build Go dev container${NC}"
    exit 1
fi

# Step 3: Create persistent volumes
echo ""
echo -e "${YELLOW}Step 3: Setting up persistent Go cache...${NC}"
docker volume create go-dev-cache 2>/dev/null
docker volume create go-dev-modules 2>/dev/null
echo -e "${GREEN}✅ Persistent volumes created${NC}"

# Step 4: Create helper script
echo ""
echo -e "${YELLOW}Step 4: Creating helper script...${NC}"

cat > run-go-dev.sh << EOF
#!/bin/bash
echo "🐹 Starting Go development container..."
echo "📂 Source: $GO_APP_PATH"
echo "🔐 Proxy: http://localhost:8082 (trusted certificates)"
echo "📦 Modules cached in Docker volumes"
echo ""

docker run --rm -it \\
    -v "$GO_APP_PATH:/go/src/app" \\
    -v go-dev-cache:/go/.cache \\
    -v go-dev-modules:/go/pkg/mod \\
    --add-host host.docker.internal:host-gateway \\
    go-dev-trusted \\
    sh -c "
        echo '🎯 Go Development Environment Ready!'
        echo ''
        echo 'Available commands:'
        echo '  go run cmd/api/main.go       # Run your app'
        echo '  go build cmd/api/main.go     # Build your app'  
        echo '  go mod tidy                  # Tidy modules'
        echo '  go test ./...                # Run tests'
        echo ''
        echo '🔐 HTTPS traffic will be captured without InsecureSkipVerify!'
        echo '📦 Dependencies are cached and won\\'t be re-downloaded'
        echo ''
        echo 'Current directory contents:'
        ls -la
        echo ''
        /bin/sh
    "
EOF

chmod +x run-go-dev.sh

# Step 5: Create monitoring script
cat > monitor-captures.sh << 'EOF'
#!/bin/bash
echo "📡 Monitoring HTTPS captures..."
echo "Press Ctrl+C to stop"
echo ""
docker logs -f mitmproxy
EOF

chmod +x monitor-captures.sh

# Final summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Go Development Environment Ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}🚀 Quick Start:${NC}"
echo ""
echo "1. Start your Go development environment:"
echo "   ${GREEN}./run-go-dev.sh${NC}"
echo ""
echo "2. In the container, run your app:"
echo "   ${GREEN}go run cmd/api/main.go${NC}"
echo ""
echo "3. Monitor captured HTTPS traffic (in another terminal):"
echo "   ${GREEN}./monitor-captures.sh${NC}"
echo ""
echo -e "${BLUE}✅ Benefits:${NC}"
echo "• No InsecureSkipVerify needed in your Go code"
echo "• Go modules downloaded once, cached forever"
echo "• Full HTTPS request/response body capture"
echo "• Easy development workflow"
echo ""
echo -e "${BLUE}📂 Your app files:${NC} $GO_APP_PATH"
echo -e "${BLUE}🔐 Proxy running:${NC} http://localhost:8082"
echo -e "${BLUE}📊 Cache volumes:${NC} go-dev-cache, go-dev-modules"
echo ""
echo -e "${YELLOW}🎯 Ready to develop! Run './run-go-dev.sh' to get started.${NC}"

# Clean up temp files
rm -f go.mod go.sum Dockerfile.go-dev-trusted