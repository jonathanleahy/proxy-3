#!/bin/bash
# run-health.sh - Start the health check server

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Starting Health Check Server${NC}"
echo "============================"
echo ""

# Check if capture system is running
if ! docker ps | grep -q transparent-proxy; then
    echo -e "${RED}❌ Error: Capture system is not running${NC}"
    echo ""
    echo "Please start it first with:"
    echo -e "${YELLOW}  ./start-capture.sh${NC}"
    echo ""
    exit 1
fi

# Check if health server is already running
if docker exec app sh -c "ps aux | grep -v grep | grep -q health-server"; then
    echo -e "${YELLOW}⚠️  Health server is already running${NC}"
    echo ""
    echo "Test it with:"
    echo -e "${GREEN}  curl http://localhost:8080/health${NC}"
    echo ""
    echo "To restart, first stop it:"
    echo -e "${YELLOW}  docker exec app pkill -f health-server${NC}"
    exit 0
fi

echo -e "${YELLOW}Starting health server on port 8080...${NC}"

# Start the health server in background
docker exec -d -u appuser app sh -c "
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    cd /proxy
    exec go run health-server.go
"

# Wait for it to start
sleep 3

# Test if it's working
if curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Health server started successfully!${NC}"
    echo ""
    echo "Available endpoints:"
    echo -e "  ${GREEN}http://localhost:8080/health${NC} - Health check (JSON)"
    echo -e "  ${GREEN}http://localhost:8080/status${NC} - Detailed status"
    echo -e "  ${GREEN}http://localhost:8080/${NC}       - Usage info"
    echo ""
    echo "Test with:"
    echo -e "  ${YELLOW}curl http://localhost:8080/health${NC}"
    echo -e "  ${YELLOW}curl http://localhost:8080/status | jq${NC}"
else
    echo -e "${RED}❌ Failed to start health server${NC}"
    echo "Check logs with:"
    echo -e "  ${YELLOW}docker logs app${NC}"
    exit 1
fi