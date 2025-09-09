#!/bin/bash
# Shared cleanup function for all START scripts

cleanup_all_containers() {
    echo "🧹 Cleaning up existing containers..."
    
    # Stop all proxy-related containers
    docker stop \
        transparent-proxy app mock-viewer viewer proxy \
        go-proxy-transparent go-app-shared go-app-proxied \
        app-sidecar-full app-with-sidecar go-app-fix5 \
        2>/dev/null || true
    
    # Remove them
    docker rm -f \
        transparent-proxy app mock-viewer viewer proxy \
        go-proxy-transparent go-app-shared go-app-proxied \
        app-sidecar-full app-with-sidecar go-app-fix5 \
        2>/dev/null || true
    
    # Clean up networks
    docker network prune -f 2>/dev/null || true
    
    sleep 2
    echo "✅ Cleanup complete"
}