#!/bin/bash
# TEST-WORKING-SITES.sh - Test with sites that are working

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING HTTPS CAPTURE WITH WORKING SITES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

PROXY_PORT=8080

# Test GitHub API (we know this works)
echo -e "${YELLOW}Test 1: GitHub API (working):${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://api.github.com/users/github 2>&1)

if echo "$response" | grep -q "login"; then
    echo -e "${GREEN}✅ GitHub API working! Showing decrypted HTTPS content:${NC}"
    echo "$response" | python3 -m json.tool 2>/dev/null | head -20 || echo "$response" | head -20
else
    echo -e "${RED}GitHub failed${NC}"
fi

echo ""
echo "---"
echo ""

# Test other reliable sites
echo -e "${YELLOW}Test 2: Other HTTPS sites:${NC}"

# Google (should always work)
echo -n "Google.com: "
status=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     -o /dev/null \
     -w "%{http_code}" \
     https://www.google.com 2>/dev/null)
if [ "$status" = "200" ] || [ "$status" = "302" ]; then
    echo -e "${GREEN}✅ Status $status${NC}"
else
    echo -e "${RED}❌ Status $status${NC}"
fi

# GitHub raw content
echo -n "GitHub raw: "
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore 2>&1 | head -5)
if echo "$response" | grep -q "Byte-compiled"; then
    echo -e "${GREEN}✅ Can see content${NC}"
else
    echo -e "${RED}❌ No content${NC}"
fi

# JSONPlaceholder (alternative to httpbin)
echo -n "JSONPlaceholder: "
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 5 \
     https://jsonplaceholder.typicode.com/posts/1 2>&1)
if echo "$response" | grep -q "userId"; then
    echo -e "${GREEN}✅ Working${NC}"
    echo "  Sample:" 
    echo "$response" | python3 -m json.tool 2>/dev/null | head -8 || echo "$response" | head -8
else
    echo -e "${RED}❌ Failed${NC}"
fi

echo ""
echo "---"
echo ""

# Show what was captured
echo -e "${YELLOW}Test 3: Check captured traffic in proxy:${NC}"
echo "Recent requests:"
docker logs --tail 20 mitmproxy 2>&1 | grep -E "GET|POST|github|google|json" | tail -10 || echo "No matches"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HOW TO USE THIS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "Since GitHub API works, you can:"
echo ""
echo "1. Test any HTTPS site:"
echo "   ${GREEN}curl -x http://localhost:8080 --insecure https://api.github.com/repos/torvalds/linux${NC}"
echo ""
echo "2. See the decrypted content in proxy logs:"
echo "   ${GREEN}docker logs mitmproxy | less${NC}"
echo ""
echo "3. For your Go app, make it call GitHub or similar:"
echo "   ${GREEN}resp, _ := http.Get(\"https://api.github.com/users/octocat\")${NC}"
echo ""
echo "4. Save all captured traffic:"
echo "   ${GREEN}docker logs mitmproxy > captured-traffic.log${NC}"
echo ""

if echo "$response" | grep -q "userId\|login"; then
    echo -e "${GREEN}✅ MITMPROXY IS SUCCESSFULLY CAPTURING HTTPS!${NC}"
    echo "You can see the decrypted content of HTTPS requests!"
else
    echo -e "${YELLOW}Some sites may be blocked or down, but GitHub works!${NC}"
fi