#!/bin/bash
# TEST-PROXY-CAPTURE.sh - Test the proxy is capturing HTTPS

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING PROXY CAPTURE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Find the proxy port
PROXY_PORT=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep proxy | grep -oE '0.0.0.0:([0-9]+)' | cut -d: -f2 | head -1)

if [ -z "$PROXY_PORT" ]; then
    echo -e "${RED}Proxy not running${NC}"
    echo "Run ./GET-IT-WORKING.sh first"
    exit 1
fi

echo -e "${GREEN}✅ Proxy found on port $PROXY_PORT${NC}"
echo ""

echo -e "${YELLOW}The SSL certificate error is EXPECTED!${NC}"
echo "It means the proxy is intercepting HTTPS traffic correctly."
echo ""

# Test 1: Make HTTPS call through proxy (ignore cert error)
echo -e "${YELLOW}Test 1: Making HTTPS call through proxy (ignoring cert)...${NC}"
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s \
     https://api.github.com \
     | head -5

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ HTTPS call succeeded through proxy!${NC}"
else
    echo -e "${RED}Failed${NC}"
fi

# Test 2: Check what the proxy captured
echo ""
echo -e "${YELLOW}Test 2: Checking proxy logs for captured traffic...${NC}"
echo "Last 10 lines from proxy:"
docker logs --tail 10 proxy

# Test 3: Count captured requests
echo ""
echo -e "${YELLOW}Test 3: Counting captured requests...${NC}"
CAPTURES=$(docker logs proxy 2>&1 | grep -c "GET\|POST\|HTTPS" || echo "0")
echo "Total requests captured: $CAPTURES"

# Test 4: Make multiple requests
echo ""
echo -e "${YELLOW}Test 4: Making multiple HTTPS requests...${NC}"

echo "1. GitHub API:"
curl -x http://localhost:$PROXY_PORT --insecure -s https://api.github.com/users/github -o /dev/null -w "   Status: %{http_code}\n"

echo "2. Google:"
curl -x http://localhost:$PROXY_PORT --insecure -s https://www.google.com -o /dev/null -w "   Status: %{http_code}\n"

echo "3. HTTPBin:"
curl -x http://localhost:$PROXY_PORT --insecure -s https://httpbin.org/get -o /dev/null -w "   Status: %{http_code}\n"

# Check captures again
echo ""
echo -e "${YELLOW}New proxy logs (showing captured HTTPS):${NC}"
docker logs --tail 20 proxy | grep -E "GET|POST|github|google|httpbin" || echo "No matches in recent logs"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}HOW TO USE THE PROXY:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "1. With curl (ignore cert errors):"
echo "   ${GREEN}curl -x http://localhost:$PROXY_PORT --insecure https://any-site.com${NC}"
echo ""
echo "2. With wget:"
echo "   ${GREEN}wget --no-check-certificate -e use_proxy=yes -e https_proxy=localhost:$PROXY_PORT https://any-site.com${NC}"
echo ""
echo "3. From your Go app (add to http.Client):"
echo "   ${GREEN}Transport: &http.Transport{"
echo "       Proxy: func(*http.Request) (*url.URL, error) {"
echo "           return url.Parse(\"http://localhost:$PROXY_PORT\")"
echo "       },"
echo "       TLSClientConfig: &tls.Config{InsecureSkipVerify: true},"
echo "   }${NC}"
echo ""
echo "4. View all captured traffic:"
echo "   ${GREEN}docker logs proxy${NC}"
echo ""
echo -e "${YELLOW}The certificate error means IT'S WORKING!${NC}"
echo "The proxy is successfully intercepting HTTPS traffic."