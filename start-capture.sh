#!/bin/bash
# start-capture.sh - Start the transparent HTTPS capture system

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
APP_DIR="${1:-}"
if [ -n "$APP_DIR" ] && [ "$APP_DIR" = "--help" ]; then
    echo "Usage: $0 [APP_DIRECTORY]"
    echo ""
    echo "Start the transparent HTTPS capture system"
    echo ""
    echo "Arguments:"
    echo "  APP_DIRECTORY  Optional: Path to your Go application directory"
    echo "                 If provided, this directory will be mounted in the container"
    echo ""
    echo "Examples:"
    echo "  $0                          # Start without specific app directory"
    echo "  $0 ~/projects/my-api        # Start with specific project mounted"
    echo ""
    exit 0
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🚀 Starting Transparent HTTPS Capture System${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Handle app directory if provided
if [ -n "$APP_DIR" ]; then
    # Expand path and make absolute
    APP_DIR=$(eval echo "$APP_DIR")
    APP_DIR=$(cd "$APP_DIR" 2>/dev/null && pwd || echo "$APP_DIR")
    
    if [ ! -d "$APP_DIR" ]; then
        echo -e "${RED}❌ Error: Directory not found: $APP_DIR${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}📁 App Directory:${NC} $APP_DIR"
    
    # Export for docker-compose to use
    export APP_MOUNT_DIR="$APP_DIR"
    
    # Check if it's a Go project
    if [ -f "$APP_DIR/go.mod" ]; then
        echo -e "${GREEN}✅ Found go.mod in project${NC}"
    elif [ -f "$APP_DIR/main.go" ]; then
        echo -e "${GREEN}✅ Found main.go in project${NC}"
    else
        echo -e "${YELLOW}⚠️  No go.mod or main.go found - ensure this is a Go project${NC}"
    fi
    echo ""
fi

# Check if already running
if docker ps | grep -q transparent-proxy; then
    echo -e "${YELLOW}System appears to be running. Checking status...${NC}"
    
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "transparent-proxy|app|mock-viewer"; then
        echo ""
        echo -e "${GREEN}✅ System is already running!${NC}"
        echo ""
        echo "To run your app, use:"
        echo -e "${YELLOW}  ./run-app.sh 'go run yourapp.go'${NC}"
        echo ""
        echo "To monitor captures:"
        echo -e "${YELLOW}  ./monitor-proxy.sh${NC}"
        echo ""
        echo "To stop the system:"
        echo -e "${YELLOW}  docker compose -f docker-compose-transparent.yml down${NC}"
        exit 0
    fi
fi

# Choose docker-compose file based on whether app directory is provided
if [ -n "$APP_DIR" ]; then
    COMPOSE_FILE="docker-compose-transparent-app.yml"
else
    COMPOSE_FILE="docker-compose-transparent.yml"
fi

# Clean up any stale containers
echo -e "${YELLOW}Cleaning up any stale containers...${NC}"
docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
docker compose -f docker-compose-transparent-app.yml down 2>/dev/null || true
docker stop app transparent-proxy mock-viewer 2>/dev/null || true
docker rm app transparent-proxy mock-viewer 2>/dev/null || true

# Start the system
echo -e "${YELLOW}Starting Docker containers...${NC}"
echo -e "${YELLOW}Using: $COMPOSE_FILE${NC}"
docker compose -f $COMPOSE_FILE up -d

# Wait for proxy to be ready
echo -e "${YELLOW}Waiting for proxy initialization...${NC}"
sleep 3

# Check certificate is available
MAX_WAIT=30
WAITED=0
while [ ! -f "/tmp/docker-certs-test" ] && [ $WAITED -lt $MAX_WAIT ]; do
    if docker exec transparent-proxy ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
        touch /tmp/docker-certs-test
        break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done
rm -f /tmp/docker-certs-test

if docker exec transparent-proxy ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate ready${NC}"
else
    echo -e "${RED}⚠️  Certificate not found, but continuing...${NC}"
fi

# Verify iptables rules
if docker exec transparent-proxy iptables -t nat -L OUTPUT -n | grep -q "owner UID match 1000"; then
    echo -e "${GREEN}✅ Iptables rules configured for appuser (UID 1000)${NC}"
else
    echo -e "${RED}⚠️  Iptables rules may not be properly configured${NC}"
fi

# Check proxy is listening
if docker exec transparent-proxy netstat -tln | grep -q ":8084"; then
    echo -e "${GREEN}✅ Proxy listening on port 8084${NC}"
else
    echo -e "${RED}⚠️  Proxy may not be listening properly${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 Capture System Ready!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The transparent HTTPS capture system is now running."
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Run your Go app with: ${GREEN}./run-app.sh 'go run yourapp.go'${NC}"
echo "  2. Monitor captures with: ${GREEN}./monitor-proxy.sh${NC}"
echo "  3. View captures in: ${GREEN}captured/*.json${NC}"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  • Your app MUST run as appuser (UID 1000) - the run-app.sh handles this"
echo "  • Only HTTP/HTTPS traffic on ports 80/443 is captured"
echo "  • Captures are saved automatically every 30 seconds"
echo ""
echo -e "${YELLOW}To stop the system:${NC}"
echo "  docker compose -f $COMPOSE_FILE down"
echo ""

# Store the compose file for later use
echo "$COMPOSE_FILE" > .current-compose-file

# Start health server automatically
echo -e "${YELLOW}Starting health check server...${NC}"
docker exec -d -u appuser app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    cd /proxy
    exec go run health-server.go
" 2>/dev/null || true

sleep 2
if curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Health server running on http://localhost:8080${NC}"
fi