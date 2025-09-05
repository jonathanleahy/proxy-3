# Dockerfile for test application
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install dependencies for network debugging
RUN apk update && apk add --no-cache curl wget netcat-openbsd

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o test-app cmd/test-outgoing/main.go 2>/dev/null || \
    echo "No test app found, using sleep"

# Runtime stage
FROM alpine:latest

RUN apk update && apk add --no-cache curl wget netcat-openbsd bash

WORKDIR /app

# Copy built binary if it exists
COPY --from=builder /app/test-app /app/test-app 2>/dev/null || true

# Copy any test scripts
COPY --from=builder /app/test-*.sh /app/ 2>/dev/null || true

# Default command - can be overridden
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]