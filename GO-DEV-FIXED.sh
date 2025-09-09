#!/bin/bash
# GO-DEV-FIXED.sh - Fixed Go development with trusted certificates (handles package errors)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🐹 Go Development with Trusted HTTPS Capture (Fixed)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Parse arguments
GO_APP_PATH="${1:-~/temp/aa}"
if [ "$GO_APP_PATH" = "--help" ] || [ "$GO_APP_PATH" = "-h" ]; then
    echo "Usage: $0 [GO_APP_PATH]"
    echo ""
    echo "GO_APP_PATH: Path to your Go application (default: ~/temp/aa)"
    exit 0
fi

# Expand tilde
GO_APP_PATH=$(eval echo "$GO_APP_PATH")

if [ ! -d "$GO_APP_PATH" ]; then
    echo -e "${RED}❌ Go app directory not found: $GO_APP_PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}🎯 Using Go app at: $GO_APP_PATH${NC}"

# Step 1: Start mitmproxy
echo ""
echo -e "${YELLOW}Step 1: Setting up trusted HTTPS proxy...${NC}"

docker stop mitmproxy 2>/dev/null || true
docker rm mitmproxy 2>/dev/null || true

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

# Step 2: Try multiple Docker build approaches
echo ""
echo -e "${YELLOW}Step 2: Building Go dev container (with fallbacks)...${NC}"

# Method 1: Try golang:alpine with explicit package versions
echo -e "${BLUE}Method 1: Trying golang:alpine...${NC}"

cat > Dockerfile.go-dev-alpine << 'EOF'
FROM golang:alpine

# Try installing packages one by one with error handling
RUN apk update && \
    apk add --no-cache ca-certificates || echo "ca-certificates failed" && \
    apk add --no-cache git || echo "git failed"

# Copy and install certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

WORKDIR /go/src/app

# Don't copy go.mod/go.sum yet - let user do it in container
ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082

CMD ["/bin/sh"]
EOF

if docker build -t go-dev-alpine -f Dockerfile.go-dev-alpine .; then
    echo -e "${GREEN}✅ Alpine build succeeded${NC}"
    GO_IMAGE="go-dev-alpine"
else
    echo -e "${YELLOW}Alpine build failed, trying alternative...${NC}"
    
    # Method 2: Try golang:1.21-bullseye (Debian-based, more reliable)
    echo -e "${BLUE}Method 2: Trying golang:bullseye (Debian)...${NC}"
    
    cat > Dockerfile.go-dev-debian << 'EOF'
FROM golang:1.21-bullseye

# Debian package installation (more reliable than Alpine)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy and install certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

WORKDIR /go/src/app

ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082

CMD ["/bin/bash"]
EOF

    if docker build -t go-dev-debian -f Dockerfile.go-dev-debian .; then
        echo -e "${GREEN}✅ Debian build succeeded${NC}"
        GO_IMAGE="go-dev-debian"
    else
        echo -e "${YELLOW}Debian build failed, trying minimal...${NC}"
        
        # Method 3: Minimal golang image (no git)
        echo -e "${BLUE}Method 3: Trying minimal golang...${NC}"
        
        cat > Dockerfile.go-dev-minimal << 'EOF'
FROM golang:alpine

# Skip git, only install ca-certificates
RUN apk update && apk add --no-cache ca-certificates

# Copy and install certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

WORKDIR /go/src/app

ENV HTTP_PROXY=http://host.docker.internal:8082
ENV HTTPS_PROXY=http://host.docker.internal:8082

CMD ["/bin/sh"]
EOF

        if docker build -t go-dev-minimal -f Dockerfile.go-dev-minimal .; then
            echo -e "${GREEN}✅ Minimal build succeeded${NC}"
            echo -e "${YELLOW}Note: git not available in minimal image${NC}"
            GO_IMAGE="go-dev-minimal"
        else
            echo -e "${RED}All build methods failed${NC}"
            exit 1
        fi
    fi
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
echo "📦 Using image: $GO_IMAGE"
echo ""

docker run --rm -it \\
    -v "$GO_APP_PATH:/go/src/app" \\
    -v go-dev-cache:/go/.cache \\
    -v go-dev-modules:/go/pkg/mod \\
    --add-host host.docker.internal:host-gateway \\
    $GO_IMAGE \\
    sh -c "
        echo '🎯 Go Development Environment Ready!'
        echo ''
        echo 'If you have go.mod/go.sum, run:'
        echo '  go mod download    # Download dependencies'
        echo '  go mod tidy        # Clean up dependencies'
        echo ''
        echo 'Available commands:'
        echo '  go run cmd/api/main.go   # Run your app'
        echo '  go build -o app cmd/api/main.go  # Build your app'
        echo '  go test ./...      # Run tests'
        echo ''
        echo '🔐 HTTPS traffic captured without InsecureSkipVerify!'
        echo '📦 Dependencies cached in Docker volumes'
        echo ''
        ls -la
        echo ''
        /bin/sh
    "
EOF

chmod +x run-go-dev.sh

# Create monitoring script
cat > monitor-captures.sh << 'EOF'
#!/bin/bash
echo "📡 Monitoring HTTPS captures..."
docker logs -f mitmproxy
EOF

chmod +x monitor-captures.sh

# Final summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Go Development Environment Ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Docker image built:${NC} $GO_IMAGE"
echo ""
echo -e "${YELLOW}🚀 Quick Start:${NC}"
echo ""
echo "1. Start your Go development environment:"
echo "   ${GREEN}./run-go-dev.sh${NC}"
echo ""
echo "2. In the container:"
echo "   a. If you have go.mod:"
echo "      ${GREEN}go mod download${NC}"
echo "   b. Run your app:"
echo "      ${GREEN}go run cmd/api/main.go${NC}"
echo ""
echo "3. Monitor captured HTTPS traffic:"
echo "   ${GREEN}./monitor-captures.sh${NC}"
echo ""
echo -e "${BLUE}📂 Your app:${NC} $GO_APP_PATH"
echo -e "${BLUE}🔐 Proxy:${NC} http://localhost:8082"
echo ""

# Clean up temp files
rm -f Dockerfile.go-dev-alpine Dockerfile.go-dev-debian Dockerfile.go-dev-minimal