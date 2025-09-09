#!/bin/bash
# RUN-YOUR-APP-SECURELY.sh - Run your app with trusted certificates

echo "🔐 Running your Go app with trusted HTTPS (no --insecure needed)..."

# Your app location
APP_PATH="${1:-~/temp/aa/cmd/api/main.go}"

# Build a container for your specific app
docker build -t your-secure-app -f Dockerfile.secure-go .

# Run your app with the secure setup
echo "Starting your app: $APP_PATH"

# Create temporary directory for your app
docker run --rm --network host \
    -v ~/temp/aa:/external-app \
    -e HTTP_PROXY=http://localhost:8082 \
    -e HTTPS_PROXY=http://localhost:8082 \
    -w /external-app \
    your-secure-app \
    go run cmd/api/main.go
