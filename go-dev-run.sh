#!/bin/bash
# go-dev-run.sh - Run Go development container with your project directory

# Parse arguments
PROJECT_DIR="${1:-.}"
APP_PORT="${2:-8080}"

# Show help if requested
if [ "$PROJECT_DIR" = "--help" ] || [ "$PROJECT_DIR" = "-h" ]; then
    echo "Usage: $0 [PROJECT_DIR] [PORT]"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_DIR  Path to your Go project (default: current directory)"
    echo "  PORT         Port to expose for your app (default: 8080)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use current directory, port 8080"
    echo "  $0 ~/projects/my-api         # Specific project, port 8080"
    echo "  $0 ~/projects/my-api 3000    # Specific project, port 3000"
    echo ""
    exit 0
fi

# Expand tilde and resolve absolute path
PROJECT_DIR=$(eval echo "$PROJECT_DIR")
PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")

# Verify project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Error: Project directory not found: $PROJECT_DIR"
    echo ""
    echo "Please specify a valid Go project directory:"
    echo "  $0 ~/path/to/your/project"
    exit 1
fi

# Check if Docker image exists
if ! docker images | grep -q go-dev-alpine; then
    echo "❌ Error: Docker image 'go-dev-alpine' not found"
    echo ""
    echo "Please run first:"
    echo "  ./GO-DEV-FIXED.sh $PROJECT_DIR"
    exit 1
fi

# Check if mitmproxy is running
if ! docker ps | grep -q mitmproxy; then
    echo "⚠️  Warning: mitmproxy not running. HTTPS capture won't work."
    echo "Run: ./GO-DEV-FIXED.sh to set it up"
    echo ""
fi

echo "🐹 Starting Go development container..."
echo "📂 Project: $PROJECT_DIR"
echo "🔐 Proxy: http://localhost:8082 (trusted certificates)"
echo "🌐 Port: localhost:$APP_PORT → container:$APP_PORT"
echo "📦 Image: go-dev-alpine"
echo ""

# Check for go.mod in project
if [ -f "$PROJECT_DIR/go.mod" ]; then
    echo "✅ Found go.mod in project"
else
    echo "⚠️  No go.mod found. You may need to run 'go mod init' in the container"
fi

echo ""
echo "Starting container..."
echo ""

docker run --rm -it \
    -v "$PROJECT_DIR:/go/src/app" \
    -v go-dev-cache:/go/.cache \
    -v go-dev-modules:/go/pkg/mod \
    -p $APP_PORT:$APP_PORT \
    --add-host host.docker.internal:host-gateway \
    -e PROJECT_NAME="$(basename $PROJECT_DIR)" \
    go-dev-alpine \
    sh -c "
        echo '🎯 Go Development Environment Ready!'
        echo '📁 Project mounted at: /go/src/app'
        echo ''
        echo 'Project contents:'
        ls -la
        echo ''
        
        if [ -f go.mod ]; then
            echo '📦 Found go.mod - downloading dependencies...'
            go mod download
            echo '✅ Dependencies ready!'
        else
            echo '⚠️  No go.mod found. Initialize with:'
            echo '  go mod init your-module-name'
        fi
        
        echo ''
        echo '🚀 Commands to run your app:'
        echo '  go run main.go                    # If main.go exists'
        echo '  go run cmd/api/main.go           # If using cmd structure'
        echo '  go run .'                        # Run package in current dir'
        echo ''
        echo '🧪 Other commands:'
        echo '  go test ./...                    # Run all tests'
        echo '  go build -o app                  # Build binary'
        echo ''
        echo '🌐 Your app will be accessible at:'
        echo '  http://localhost:$APP_PORT (from host machine)'
        echo ''
        echo '🔐 All outgoing HTTPS traffic is captured!'
        echo ''
        /bin/sh
    "