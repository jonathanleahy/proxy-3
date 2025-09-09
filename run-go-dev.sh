#!/bin/bash
echo "🐹 Starting Go development container..."
echo "📂 Source: ."
echo "🔐 Proxy: http://localhost:8082 (trusted certificates)"
echo "📦 Using image: go-dev-alpine"
echo ""

docker run --rm -it \
    -v ".:/go/src/app" \
    -v go-dev-cache:/go/.cache \
    -v go-dev-modules:/go/pkg/mod \
    --add-host host.docker.internal:host-gateway \
    go-dev-alpine \
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
