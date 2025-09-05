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

# Build the application (create empty file if doesn't exist)
RUN go build -o test-app cmd/test-outgoing/main.go 2>/dev/null || touch test-app

# Runtime stage
FROM alpine:latest

RUN apk update && apk add --no-cache curl wget netcat-openbsd bash

WORKDIR /app

# Copy built binary (will exist even if empty)
COPY --from=builder /app/test-app /app/test-app

# Default command - can be overridden
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]
