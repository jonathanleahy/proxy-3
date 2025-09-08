# Dockerfile for test application
FROM golang:1.23-alpine

WORKDIR /app

# Install ca-certificates package for certificate management
RUN apk add --no-cache ca-certificates

# Create directory for custom certificates
RUN mkdir -p /usr/local/share/ca-certificates

# Create non-root user for running applications
RUN addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

# Copy entry script
COPY docker/app-entry.sh /app-entry.sh
RUN chmod +x /app-entry.sh

# Set ownership for the app directory
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Default command - can be overridden
ENTRYPOINT ["/app-entry.sh"]
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]
