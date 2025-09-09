#!/bin/bash
# Summary of all fixes - try them in order!

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          HTTPS CAPTURE FIXES - TRY IN ORDER                  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│ FIX 1: TRANSPARENT MODE (Best - No code changes!)          │${NC}"
echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${NC}"
echo "  ./FIX-1-TRANSPARENT-MODE.sh"
echo "  Then: docker exec -u 1000 app go run your-app.go"
echo "  ✅ NO code changes needed"
echo "  ❌ May fail with: 'iptables-restore failed'"
echo ""

echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ FIX 2: PROXY MODE (Reliable but needs code change)         │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
echo "  ./FIX-2-PROXY-MODE.sh"
echo "  Then: HTTP_PROXY=http://172.17.0.1:8084 go run your-app.go"
echo "  ✅ Works on ALL machines"
echo "  ❌ Needs: Proxy: http.ProxyFromEnvironment in Go code"
echo ""

echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ FIX 3: NETWORK SHARING (Forces all traffic through proxy)   │${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
echo "  ./FIX-3-NETWORK-SHARING.sh"
echo "  Then: docker run --network container:go-proxy-transparent your-app"
echo "  ✅ NO code changes, forces ALL traffic through proxy"
echo "  ❌ Complex networking"
echo ""

echo -e "${RED}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${RED}│ FIX 4: SIDECAR (Proxy and app in same container)           │${NC}"
echo -e "${RED}└─────────────────────────────────────────────────────────────┘${NC}"
echo "  ./FIX-4-SIDECAR.sh"
echo "  Then: Follow the script instructions"
echo "  ✅ Reliable, no code changes"
echo "  ❌ More complex setup"
echo ""

echo -e "${GREEN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│ FIX 5: PROVEN WORKING (Uses FINAL-CLEANUP-AND-RUN)         │${NC}"
echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${NC}"
echo "  ./FIX-5-WORKING-PROXY.sh"
echo "  ✅ Known to work"
echo "  ❌ Needs ProxyFromEnvironment in Go code"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}QUICK DECISION TREE:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. Can you modify Go code? → Use FIX 2 or 5"
echo "2. Can't modify code + iptables works? → Use FIX 1"
echo "3. Can't modify code + iptables broken? → Use FIX 3 or 4"
echo "4. Just want it to work? → Use FIX 5 + modify Go code"
echo ""
echo -e "${YELLOW}TEST YOUR APP:${NC}"
echo "After running a fix, test with:"
echo "  curl http://localhost:8080/your-endpoint"
echo "  Check captures: ls -la captured/"
echo "  View in browser: http://localhost:8090/viewer"
echo ""
echo -e "${GREEN}GO CODE CHANGE NEEDED FOR FIXES 2 & 5:${NC}"
cat << 'EOF'
// Replace this:
client := &http.Client{}

// With this:
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,
    },
}
EOF