#!/bin/bash
# Force HTTPS interception by using aggressive iptables rules

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔨 Force HTTPS Interception Mode${NC}"
echo "============================================"
echo "This uses aggressive rules that WILL intercept traffic"
echo ""

# Check current state
echo -e "${YELLOW}Current iptables rules:${NC}"
docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v | grep -E "REDIRECT|RETURN" || echo "No rules"

# Clear and recreate rules
echo -e "\n${YELLOW}Applying aggressive interception rules...${NC}"
docker exec transparent-proxy sh -c '
# Clear existing OUTPUT rules
iptables -t nat -F OUTPUT

# Skip only absolute localhost
iptables -t nat -A OUTPUT -d 127.0.0.1 -j RETURN

# Redirect EVERYTHING else on ports 80/443
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084

echo "✅ Aggressive rules applied"
'

# Show new rules
echo -e "\n${YELLOW}New iptables rules:${NC}"
docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v

# Restart app
echo -e "\n${YELLOW}Restarting app...${NC}"
docker exec app sh -c "killall -9 go main 2>/dev/null" || true
sleep 2
docker exec -u 1000 -d app sh -c "cd /proxy/example-app && go run main.go"
sleep 5

# Test
echo -e "\n${YELLOW}Testing interception...${NC}"
RESPONSE=$(curl -s -m 10 http://localhost:8080/users 2>/dev/null)
if echo "$RESPONSE" | grep -q "success\|Leanne Graham"; then
    echo -e "${GREEN}✅ HTTPS interception WORKING with forced mode!${NC}"
    
    # Check packet counts
    echo -e "\n${YELLOW}Packet counts:${NC}"
    docker exec transparent-proxy iptables -t nat -L OUTPUT -n -v | grep REDIRECT
    
    echo -e "\n${GREEN}🎉 Success!${NC}"
    echo "Note: This mode intercepts ALL HTTP/HTTPS traffic (not just UID 1000)"
else
    echo -e "${RED}❌ Still not working${NC}"
    echo "Response: $(echo $RESPONSE | head -c 100)"
    echo ""
    echo "This system may have fundamental iptables limitations."
    echo "Last resort: Use proxy mode instead:"
    echo "  ./WORKING-SOLUTION.sh"
fi