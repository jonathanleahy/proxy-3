#!/bin/bash
# TEST-WITH-PYTHON.sh - Test with Python JSON formatting

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROXY_PORT=8080

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING MITMPROXY WITH JSON FORMATTING${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if Python is available
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    echo -e "${GREEN}✅ Using python3${NC}"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
    echo -e "${GREEN}✅ Using python${NC}"
else
    echo -e "${YELLOW}Python not found, installing...${NC}"
    
    # Try to install Python based on the system
    if command -v apt-get &> /dev/null; then
        echo "Installing Python with apt..."
        sudo apt-get update && sudo apt-get install -y python3
        PYTHON_CMD="python3"
    elif command -v yum &> /dev/null; then
        echo "Installing Python with yum..."
        sudo yum install -y python3
        PYTHON_CMD="python3"
    elif command -v brew &> /dev/null; then
        echo "Installing Python with brew..."
        brew install python3
        PYTHON_CMD="python3"
    else
        echo -e "${RED}Cannot install Python automatically${NC}"
        echo "Please install Python manually"
        echo ""
        echo "But we can still test without formatting:"
        PYTHON_CMD="cat"
    fi
fi

# Test 1: HTTP request with formatted JSON
echo ""
echo -e "${YELLOW}Test 1: HTTP request (formatted JSON):${NC}"
curl -x http://localhost:$PROXY_PORT \
     -s --max-time 10 \
     http://httpbin.org/get | $PYTHON_CMD -m json.tool 2>/dev/null || \
curl -x http://localhost:$PROXY_PORT \
     -s --max-time 10 \
     http://httpbin.org/get

echo ""
echo "---"
echo ""

# Test 2: HTTPS request (decrypted by mitmproxy)
echo -e "${YELLOW}Test 2: HTTPS request (DECRYPTED by mitmproxy):${NC}"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://httpbin.org/json)

if [ -n "$response" ]; then
    echo -e "${GREEN}✅ HTTPS CONTENT DECRYPTED AND VISIBLE:${NC}"
    echo "$response" | $PYTHON_CMD -m json.tool 2>/dev/null || echo "$response"
else
    echo -e "${RED}❌ No response - check if mitmproxy is running${NC}"
fi

echo ""
echo "---"
echo ""

# Test 3: GitHub API with pretty formatting
echo -e "${YELLOW}Test 3: GitHub API (formatted):${NC}"
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://api.github.com/users/github | \
     $PYTHON_CMD -m json.tool 2>/dev/null | head -30 || \
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://api.github.com/users/github | head -30

echo ""
echo "---"
echo ""

# Test 4: Complex HTTPS POST request
echo -e "${YELLOW}Test 4: POST request with data:${NC}"
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"test": "data", "proxy": "mitmproxy"}' \
     https://httpbin.org/post | \
     $PYTHON_CMD -m json.tool 2>/dev/null | grep -A2 '"test"' || echo "POST test failed"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WHAT MITMPROXY CAPTURED${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "Recent captures in mitmproxy logs:"
docker logs --tail 20 mitmproxy 2>&1 | grep -E "GET|POST|https://|<<" || echo "No captures found"

echo ""
echo -e "${GREEN}If you see JSON data above, mitmproxy is successfully${NC}"
echo -e "${GREEN}decrypting and showing HTTPS traffic content!${NC}"
echo ""
echo "The proxy can see:"
echo "  • Request URLs"
echo "  • Request headers"
echo "  • Request bodies (POST data)"
echo "  • Response headers"
echo "  • Response bodies (the actual content)"
echo ""
echo -e "${YELLOW}This is what makes mitmproxy special - it can${NC}"
echo -e "${YELLOW}decrypt HTTPS to show you the actual content!${NC}"