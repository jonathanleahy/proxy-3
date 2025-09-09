#!/bin/bash
# Fix Alpine Linux package fetching issues in Docker

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Alpine Linux Package Fetching Issues${NC}"
echo "============================================"

# Function to check Docker DNS
check_docker_dns() {
    echo -e "\n${YELLOW}1. Checking Docker DNS configuration...${NC}"
    
    # Test DNS resolution in Alpine container
    if docker run --rm alpine nslookup google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS resolution working${NC}"
    else
        echo -e "${RED}❌ DNS resolution failing${NC}"
        FIX_NEEDED=true
    fi
    
    # Test Alpine package fetch
    echo -e "\n${YELLOW}2. Testing Alpine package repository access...${NC}"
    if docker run --rm alpine sh -c "apk update" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Alpine packages accessible${NC}"
    else
        echo -e "${RED}❌ Cannot fetch Alpine packages${NC}"
        FIX_NEEDED=true
    fi
}

# Function to fix Docker daemon DNS
fix_docker_daemon() {
    echo -e "\n${YELLOW}3. Applying Docker daemon fixes...${NC}"
    
    # Create daemon.json with Google DNS
    DAEMON_CONFIG="/etc/docker/daemon.json"
    
    if [ "$EUID" -eq 0 ]; then
        # Running as root, can modify daemon config
        echo "Creating Docker daemon configuration with DNS..."
        
        cat > /tmp/daemon.json <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"],
  "dns-opts": ["ndots:0"],
  "dns-search": [],
  "default-address-pools": [
    {
      "base": "172.28.0.0/16",
      "size": 24
    }
  ]
}
EOF
        
        # Backup existing config if it exists
        if [ -f "$DAEMON_CONFIG" ]; then
            cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup"
            echo "Backed up existing daemon.json"
        fi
        
        # Install new config
        mv /tmp/daemon.json "$DAEMON_CONFIG"
        
        echo "Restarting Docker daemon..."
        systemctl restart docker || service docker restart
        
        echo -e "${GREEN}✅ Docker daemon configured with DNS${NC}"
    else
        echo -e "${YELLOW}Need root access to modify Docker daemon. Run:${NC}"
        echo "  sudo ./fix-alpine-dns.sh"
    fi
}

# Function to create Docker build with DNS args
create_build_wrapper() {
    echo -e "\n${YELLOW}4. Creating build wrapper with DNS fixes...${NC}"
    
    cat > docker-build-with-dns.sh <<'EOF'
#!/bin/bash
# Build wrapper that adds DNS configuration

# Build with DNS options
docker compose -f docker-compose-transparent.yml build \
  --build-arg DNS_SERVERS="8.8.8.8 8.8.4.4" \
  --build-arg HTTP_PROXY="${HTTP_PROXY}" \
  --build-arg HTTPS_PROXY="${HTTPS_PROXY}" \
  "$@"
EOF
    
    chmod +x docker-build-with-dns.sh
    echo -e "${GREEN}✅ Created docker-build-with-dns.sh${NC}"
}

# Function to test network connectivity
test_connectivity() {
    echo -e "\n${YELLOW}5. Testing network connectivity...${NC}"
    
    # Test general internet
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Internet connectivity OK${NC}"
    else
        echo -e "  ${RED}❌ No internet connectivity${NC}"
    fi
    
    # Test Alpine CDN
    if ping -c 1 dl-cdn.alpinelinux.org >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Alpine CDN reachable${NC}"
    else
        echo -e "  ${RED}❌ Alpine CDN not reachable${NC}"
    fi
}

# Function to fix with alternative Dockerfile
create_alternative_dockerfile() {
    echo -e "\n${YELLOW}6. Creating alternative Dockerfile with mirrors...${NC}"
    
    # Create modified Dockerfile.app with mirror configuration
    cat > docker/Dockerfile.app.fixed <<'EOF'
# Dockerfile for test application with DNS/mirror fixes
FROM golang:1.23-alpine

WORKDIR /app

# Configure Alpine mirrors and DNS
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf && \
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf && \
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories

# Install required packages with retry
RUN apk update --no-cache || \
    (sleep 2 && apk update --no-cache) || \
    (echo "Using mirror..." && \
     echo "http://mirror.leaseweb.com/alpine/v3.22/main" > /etc/apk/repositories && \
     echo "http://mirror.leaseweb.com/alpine/v3.22/community" >> /etc/apk/repositories && \
     apk update --no-cache)

RUN apk add --no-cache ca-certificates su-exec || \
    (sleep 2 && apk add --no-cache ca-certificates su-exec)

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

# Default command - can be overridden
ENTRYPOINT ["/app-entry.sh"]
CMD ["/bin/sh", "-c", "while true; do echo 'App container running. Override CMD to run your app.'; sleep 60; done"]
EOF
    
    echo -e "${GREEN}✅ Created docker/Dockerfile.app.fixed${NC}"
    echo "To use it, run:"
    echo "  mv docker/Dockerfile.app docker/Dockerfile.app.original"
    echo "  mv docker/Dockerfile.app.fixed docker/Dockerfile.app"
}

# Main execution
FIX_NEEDED=false

echo -e "\n${BLUE}Diagnosing Alpine package fetch issues...${NC}"

# Check current status
check_docker_dns
test_connectivity

# Apply fixes
if [ "$FIX_NEEDED" = true ] || [ "$1" = "--force" ]; then
    echo -e "\n${BLUE}Applying fixes...${NC}"
    
    # Try to fix Docker daemon if running as root
    if [ "$EUID" -eq 0 ]; then
        fix_docker_daemon
    fi
    
    # Create alternative files
    create_build_wrapper
    create_alternative_dockerfile
    
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BLUE}Fixes Applied!${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    echo -e "\n${GREEN}Try these solutions in order:${NC}"
    echo ""
    echo "1. ${YELLOW}Use the alternative Dockerfile:${NC}"
    echo "   mv docker/Dockerfile.app docker/Dockerfile.app.original"
    echo "   mv docker/Dockerfile.app.fixed docker/Dockerfile.app"
    echo "   ./rebuild-proxy.sh --clean"
    echo ""
    echo "2. ${YELLOW}Run with custom DNS (if running as root):${NC}"
    echo "   sudo ./fix-alpine-dns.sh"
    echo "   ./rebuild-proxy.sh --clean"
    echo ""
    echo "3. ${YELLOW}Use build wrapper:${NC}"
    echo "   ./docker-build-with-dns.sh"
    echo ""
    echo "4. ${YELLOW}Set proxy if behind corporate firewall:${NC}"
    echo "   export HTTP_PROXY=http://your-proxy:port"
    echo "   export HTTPS_PROXY=http://your-proxy:port"
    echo "   ./rebuild-proxy.sh --clean"
else
    echo -e "\n${GREEN}✅ No issues detected!${NC}"
fi

# Additional suggestions
echo -e "\n${YELLOW}Additional troubleshooting:${NC}"
echo "- Check firewall settings"
echo "- Verify Docker is not using a corporate proxy incorrectly"
echo "- Try: docker system prune -a (removes all cached images)"
echo "- Check: cat /etc/resolv.conf (on host system)"
echo "- Test: docker run --rm alpine ping -c 1 dl-cdn.alpinelinux.org"