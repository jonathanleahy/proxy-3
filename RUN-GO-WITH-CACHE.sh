#!/bin/bash
# RUN-GO-WITH-CACHE.sh - Run Go app with persistent module cache (no re-downloads)

echo "📦 Running Go app with persistent module cache..."

# Create persistent volumes for Go cache and modules
docker volume create go-module-cache 2>/dev/null
docker volume create go-build-cache 2>/dev/null

# Start mitmproxy if not running
if ! docker ps | grep -q mitmproxy-trusted; then
    echo "Starting mitmproxy..."
    docker run -d \
        --name mitmproxy-trusted \
        -p 8083:8083 \
        mitmproxy/mitmproxy \
        mitmdump --listen-port 8083 --ssl-insecure
    sleep 3
fi

# Get certificate if not exists
if [ ! -f mitmproxy-ca.pem ]; then
    docker exec mitmproxy-trusted cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem
fi

# Create Go container with certificate
if ! docker images | grep -q go-with-cert; then
    cat > Dockerfile.go-with-cert << 'EOF'
FROM golang:alpine
RUN apk add --no-cache ca-certificates
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
WORKDIR /go/src/app
EOF
    docker build -t go-with-cert -f Dockerfile.go-with-cert .
fi

echo "🚀 Starting Go container with:"
echo "  ✅ Certificate trust (no InsecureSkipVerify needed)"
echo "  ✅ Persistent Go module cache"
echo "  ✅ Persistent build cache"
echo "  ✅ Source code mounted from ~/temp/aa"

# Run the container
docker run --rm -it \
    -v ~/temp/aa:/go/src/app \
    -v go-module-cache:/go/pkg/mod \
    -v go-build-cache:/root/.cache/go-build \
    -e HTTP_PROXY=http://host.docker.internal:8083 \
    -e HTTPS_PROXY=http://host.docker.internal:8083 \
    -e GOPROXY=https://proxy.golang.org,direct \
    --add-host host.docker.internal:host-gateway \
    go-with-cert \
    sh -c "
        echo '📦 Go modules will be cached in persistent volume'
        echo '🔐 HTTPS traffic will be captured without --insecure'
        echo ''
        echo 'Commands available:'
        echo '  go run cmd/api/main.go   # Run your app'
        echo '  go build cmd/api/main.go # Build your app'
        echo '  go mod tidy              # Tidy modules (cached)'
        echo ''
        echo 'First run will download dependencies, subsequent runs will be fast!'
        /bin/sh
    "

echo ""
echo "📈 Monitor captured traffic:"
echo "  docker logs -f mitmproxy-trusted"