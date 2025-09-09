#!/bin/bash
# FIX 1: TRANSPARENT MODE (Original Design - Best if it works)
# This uses iptables to transparently intercept all HTTPS traffic
# NO code changes needed in your Go app!

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIX 1: TRANSPARENT MODE (iptables)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}PROS:${NC}"
echo "  ✓ No code changes needed"
echo "  ✓ Captures ALL HTTPS traffic automatically"
echo "  ✓ Works with any HTTP client"
echo ""
echo -e "${YELLOW}CONS:${NC}"
echo "  ✗ Requires iptables support (may fail on some machines)"
echo "  ✗ Needs privileged containers"
echo ""

# Clean up
docker compose down 2>/dev/null || true
docker stop transparent-proxy app mock-viewer 2>/dev/null || true
docker rm -f transparent-proxy app mock-viewer 2>/dev/null || true

# Use the original transparent mode
echo -e "${YELLOW}Starting transparent proxy system...${NC}"
docker compose -f docker-compose-transparent.yml up -d

# Wait for proxy to be ready
sleep 5

# Check if it's working
if docker logs transparent-proxy 2>&1 | grep -q "Owner matching supported"; then
    echo -e "${GREEN}✅ Transparent mode is working!${NC}"
else
    echo -e "${RED}❌ Transparent mode failed (iptables issue)${NC}"
    echo "Try FIX-2 or FIX-3 instead"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}HOW TO RUN YOUR GO APP WITH THIS FIX:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Option A - Run inside the app container:"
echo -e "${GREEN}docker exec -it app sh${NC}"
echo -e "${GREEN}cd /your/app/path${NC}"
echo -e "${GREEN}go run main.go${NC}"
echo ""
echo "Option B - Use start-proxy-system.sh:"
echo -e "${GREEN}./start-proxy-system.sh 'go run /path/to/your/app.go'${NC}"
echo ""
echo "Option C - Run directly (app must run as UID 1000):"
echo -e "${GREEN}docker exec -u 1000 app go run /path/to/your/app.go${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} App MUST run as user 1000 (appuser) for traffic to be intercepted!"
echo ""
echo "View captures at: http://localhost:8090/viewer"
echo "Check logs: docker logs transparent-proxy"