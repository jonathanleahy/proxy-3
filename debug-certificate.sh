#!/bin/bash
# Diagnostic script for certificate issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔍 Certificate Diagnostic Tool${NC}"
echo "============================================"

# Check if containers are running
echo -e "\n${YELLOW}1. Checking container status...${NC}"
docker ps | grep -E "transparent-proxy|app|viewer" || echo -e "${RED}❌ Containers not running${NC}"

# Check mitmproxy logs
echo -e "\n${YELLOW}2. Checking mitmproxy logs for errors...${NC}"
docker logs transparent-proxy 2>&1 | tail -20

# Check certificate generation in proxy container
echo -e "\n${YELLOW}3. Checking certificate locations in proxy container...${NC}"
echo "Checking /root/.mitmproxy/:"
docker exec transparent-proxy ls -la /root/.mitmproxy/ 2>&1 || echo "Not found"
echo -e "\nChecking /home/mitmproxy/.mitmproxy/:"
docker exec transparent-proxy ls -la /home/mitmproxy/.mitmproxy/ 2>&1 || echo "Not found"

# Check shared certificate volume
echo -e "\n${YELLOW}4. Checking shared /certs/ volume...${NC}"
echo "In proxy container:"
docker exec transparent-proxy ls -la /certs/ 2>&1 || echo "Not accessible"
echo -e "\nIn app container:"
docker exec app ls -la /certs/ 2>&1 || echo "Not accessible"

# Try to manually generate certificate
echo -e "\n${YELLOW}5. Attempting manual certificate generation...${NC}"
docker exec transparent-proxy sh -c "
    # Try to generate certificate manually
    timeout 5 mitmdump --mode transparent --listen-port 8087 >/dev/null 2>&1 &
    PID=\$!
    sleep 3
    kill \$PID 2>/dev/null || true
    
    # Check if it was created
    if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        echo '✅ Certificate generated at ~/.mitmproxy/'
        # Try to copy it
        cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/ 2>&1 && echo '✅ Copied to /certs/' || echo '❌ Failed to copy'
    elif [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        echo '✅ Certificate generated at /home/mitmproxy/.mitmproxy/'
        cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/ 2>&1 && echo '✅ Copied to /certs/' || echo '❌ Failed to copy'
    else
        echo '❌ Certificate generation failed'
        echo 'Checking mitmproxy version:'
        mitmdump --version
    fi
"

# Check volume mounts
echo -e "\n${YELLOW}6. Checking Docker volume configuration...${NC}"
docker inspect transparent-proxy | jq '.[0].Mounts[] | select(.Destination == "/certs")' 2>/dev/null || echo "Volume info not available"

# Check if it's a permissions issue
echo -e "\n${YELLOW}7. Checking permissions...${NC}"
docker exec transparent-proxy sh -c "
    echo 'User info:'
    id
    echo -e '\n/certs permissions:'
    ls -ld /certs/
    echo -e '\nCan write to /certs:'
    touch /certs/test 2>&1 && rm /certs/test && echo 'Yes' || echo 'No'
"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Diagnostic complete!${NC}"
echo -e "${BLUE}=========================================${NC}"

echo -e "\n${YELLOW}Recommended actions:${NC}"
echo "1. If certificate generation failed, try rebuilding:"
echo "   ./rebuild-proxy.sh --clean"
echo ""
echo "2. If it's a permissions issue, ensure Docker has proper access"
echo ""
echo "3. If mitmproxy version is old, update the base image"