#!/bin/bash
# VIEW-TRAFFIC.sh - View captured HTTPS traffic

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  VIEWING CAPTURED HTTPS TRAFFIC${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if mitmproxy is running
if docker ps | grep -q mitmproxy; then
    echo -e "${GREEN}✅ MITMProxy is running${NC}"
else
    echo -e "${RED}MITMProxy is not running${NC}"
    echo "Start it with: ./WORKING-MITM.sh"
    exit 1
fi

echo ""
echo -e "${YELLOW}Recent HTTP/HTTPS requests:${NC}"
docker logs mitmproxy 2>&1 | grep -E "GET|POST|PUT|DELETE|PATCH" | tail -20 || echo "No requests found"

echo ""
echo -e "${YELLOW}Response codes:${NC}"
docker logs mitmproxy 2>&1 | grep -E "<<.*[0-9]{3}" | tail -10 || echo "No responses found"

echo ""
echo -e "${YELLOW}To see EVERYTHING (including request/response bodies):${NC}"
echo "docker logs mitmproxy | less"

echo ""
echo -e "${YELLOW}To save all traffic to a file:${NC}"
echo "docker logs mitmproxy > traffic.log"

echo ""
echo -e "${YELLOW}To watch traffic in real-time:${NC}"
echo "docker logs -f mitmproxy"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MAKE A TEST REQUEST${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "Making a test HTTPS request now..."
curl -x http://localhost:8080 \
     --insecure \
     -s --max-time 5 \
     https://httpbin.org/json \
     -o /dev/null \
     -w "Status: %{http_code}\n"

echo ""
echo "Check the logs again:"
echo -e "${GREEN}docker logs --tail 5 mitmproxy${NC}"