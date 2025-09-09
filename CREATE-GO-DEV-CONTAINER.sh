#!/bin/bash
# CREATE-GO-DEV-CONTAINER.sh - Create a Go dev container with pre-downloaded dependencies

echo "🐹 Creating Go development container with your app's dependencies..."

# Create Dockerfile that pre-downloads your Go modules
cat > Dockerfile.go-dev << 'EOF'
FROM golang:alpine

# Install ca-certificates and git
RUN apk add --no-cache ca-certificates git

# Set up Go module cache directory
ENV GOCACHE=/go/.cache
ENV GOMODCACHE=/go/pkg/mod

# Create app directory
WORKDIR /go/src/app

# Copy go.mod and go.sum first (for better caching)
# This will be mounted from your actual app directory
COPY go.mod go.sum ./

# Download dependencies (this layer will be cached)
RUN go mod download

# Copy certificate for HTTPS trust
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Set proxy environment for capturing
ENV HTTP_PROXY=http://host.docker.internal:8083
ENV HTTPS_PROXY=http://host.docker.internal:8083

WORKDIR /go/src/app
CMD ["/bin/sh"]
EOF

# Check if go.mod exists in your app directory
if [ -f ~/temp/aa/go.mod ]; then
    echo "✅ Found go.mod, copying for dependency pre-download..."
    cp ~/temp/aa/go.mod .
    cp ~/temp/aa/go.sum . 2>/dev/null || touch go.sum
else
    echo "⚠️  No go.mod found, creating minimal one..."
    cat > go.mod << 'EOF'
module your-app

go 1.21

require ()
EOF
    touch go.sum
fi

# Make sure we have the certificate
if [ ! -f mitmproxy-ca.pem ]; then
    echo "Getting mitmproxy certificate..."
    docker exec mitmproxy-trusted cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null || {
        echo "No mitmproxy running, creating placeholder cert..."
        touch mitmproxy-ca.pem
    }
fi

echo "🔨 Building Go dev container..."
docker build -t go-dev-trusted -f Dockerfile.go-dev .

echo ""
echo "✅ Go development container ready!"
echo ""
echo "🚀 Usage:"
echo "1. Start the container with your source code:"
echo "   docker run --rm -it -v ~/temp/aa:/go/src/app -v go-cache:/go/.cache -v go-modules:/go/pkg/mod --add-host host.docker.internal:host-gateway go-dev-trusted"
echo ""
echo "2. Your dependencies are already downloaded! Just run:"
echo "   go run cmd/api/main.go"
echo ""
echo "3. Or build once and reuse:"
echo "   go build -o myapp cmd/api/main.go"
echo "   ./myapp"
echo ""
echo "📦 Go modules and build cache are persisted in Docker volumes!"

# Create the volumes
docker volume create go-cache 2>/dev/null
docker volume create go-modules 2>/dev/null