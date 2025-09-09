#!/bin/bash
# run-go-dev-with-ports.sh - Run Go dev container with exposed ports

# Default port mapping (change as needed)
APP_PORT="${1:-8080}"
APP_PATH="${2:-.}"

echo "🐹 Starting Go development container..."
echo "📂 Source: $APP_PATH"
echo "🔐 Proxy: http://localhost:8082 (trusted certificates)"
echo "🌐 App port mapping: localhost:$APP_PORT → container:$APP_PORT"
echo ""

docker run --rm -it \
    -v "$APP_PATH:/go/src/app" \
    -v go-dev-cache:/go/.cache \
    -v go-dev-modules:/go/pkg/mod \
    -p $APP_PORT:$APP_PORT \
    --add-host host.docker.internal:host-gateway \
    go-dev-alpine \
    sh -c "
        echo '🎯 Go Development Environment Ready!'
        echo ''
        echo 'Your app will be accessible at:'
        echo '  http://localhost:$APP_PORT'
        echo ''
        echo 'Start your app on port $APP_PORT:'
        echo '  go run main.go'
        echo '  go run cmd/api/main.go'
        echo ''
        echo 'From outside the container, test with:'
        echo '  curl http://localhost:$APP_PORT/health'
        echo '  curl http://localhost:$APP_PORT/api/endpoint'
        echo ''
        echo '🔐 All HTTPS traffic from your app is captured!'
        echo ''
        ls -la
        echo ''
        /bin/sh
    "