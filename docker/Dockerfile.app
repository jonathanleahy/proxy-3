# Dockerfile for test application
FROM golang:1.21-alpine

WORKDIR /app

# Install git for go modules that need it
RUN apk update && apk add --no-cache git

# Default command - can be overridden
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]
