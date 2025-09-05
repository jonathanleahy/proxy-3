# Dockerfile for test application
FROM golang:1.21-alpine

WORKDIR /app

# Git is already included in golang:alpine image

# Default command - can be overridden
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]
