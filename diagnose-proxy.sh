#!/bin/bash
# diagnose-proxy.sh - Diagnose 502 Bad Gateway and proxy issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔍 Proxy System Diagnostics${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""

# 1. Check containers are running
echo -e "${YELLOW}1. Checking containers...${NC}"
if docker ps | grep -q transparent-proxy; then
    echo -e "${GREEN}✅ Proxy container running${NC}"
else
    echo -e "${RED}❌ Proxy container not running${NC}"
    echo "   Run: ./start-capture.sh"
    exit 1
fi

if docker ps | grep -q app; then
    echo -e "${GREEN}✅ App container running${NC}"
else
    echo -e "${RED}❌ App container not running${NC}"
    exit 1
fi
echo ""

# 2. Check mitmproxy certificate
echo -e "${YELLOW}2. Checking mitmproxy certificate...${NC}"
if docker exec app ls /certs/mitmproxy-ca-cert.pem >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Certificate file exists${NC}"
    
    # Check certificate validity
    CERT_INFO=$(docker exec app sh -c "openssl x509 -in /certs/mitmproxy-ca-cert.pem -noout -subject 2>/dev/null || echo 'INVALID'")
    if [[ "$CERT_INFO" != "INVALID" ]]; then
        echo -e "${GREEN}✅ Certificate is valid${NC}"
        echo "   Subject: $CERT_INFO"
    else
        echo -e "${RED}❌ Certificate is invalid or unreadable${NC}"
    fi
else
    echo -e "${RED}❌ Certificate file missing${NC}"
    echo "   The proxy may need to regenerate it"
fi
echo ""

# 3. Check iptables rules
echo -e "${YELLOW}3. Checking iptables rules...${NC}"
IPTABLES_RULES=$(docker exec transparent-proxy iptables -t nat -L OUTPUT -n 2>/dev/null | grep -c "owner UID match 1000" || echo "0")
if [ "$IPTABLES_RULES" -gt "0" ]; then
    echo -e "${GREEN}✅ Iptables rules configured ($IPTABLES_RULES rules for UID 1000)${NC}"
else
    echo -e "${RED}❌ No iptables rules found${NC}"
    echo "   Traffic may not be intercepted"
fi
echo ""

# 4. Check proxy is listening
echo -e "${YELLOW}4. Checking proxy port...${NC}"
if docker exec transparent-proxy sh -c "ss -tln | grep -q :8084" 2>/dev/null; then
    echo -e "${GREEN}✅ Proxy listening on port 8084${NC}"
else
    echo -e "${RED}❌ Proxy not listening on port 8084${NC}"
fi
echo ""

# 5. Test DNS resolution
echo -e "${YELLOW}5. Testing DNS resolution...${NC}"
# Test from app container
DNS_TEST=$(docker exec app sh -c "nslookup api.github.com 8.8.8.8 2>&1 | grep -c 'Address:' || echo '0'")
if [ "$DNS_TEST" -gt "1" ]; then
    echo -e "${GREEN}✅ DNS resolution working (using 8.8.8.8)${NC}"
else
    echo -e "${RED}❌ DNS resolution failed${NC}"
    echo "   This is why we need custom DNS resolver in Go"
fi
echo ""

# 6. Test direct HTTPS without proxy
echo -e "${YELLOW}6. Testing direct HTTPS (as root, bypasses proxy)...${NC}"
DIRECT_TEST=$(docker exec -u root app sh -c "wget -q -O - https://api.github.com/meta 2>&1 | head -c 50")
if [[ "$DIRECT_TEST" == *"verifiable_password_authentication"* ]] || [[ "$DIRECT_TEST" == *"{"* ]]; then
    echo -e "${GREEN}✅ Direct HTTPS works (as root)${NC}"
else
    echo -e "${RED}❌ Direct HTTPS failed: $DIRECT_TEST${NC}"
fi
echo ""

# 7. Test proxy interception
echo -e "${YELLOW}7. Testing proxy interception (as appuser)...${NC}"
# First, try without certificate trust
PROXY_TEST=$(docker exec -u appuser app sh -c "wget -q -O - https://httpbin.org/get 2>&1 | head -c 100")
if [[ "$PROXY_TEST" == *"args"* ]] || [[ "$PROXY_TEST" == *"{"* ]]; then
    echo -e "${GREEN}✅ Proxy interception works${NC}"
else
    echo -e "${YELLOW}⚠️  Proxy test result: ${PROXY_TEST:0:50}...${NC}"
    
    # Try with certificate
    echo "   Retrying with certificate trust..."
    PROXY_TEST_CERT=$(docker exec -u appuser app sh -c "SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem wget -q -O - https://httpbin.org/get 2>&1 | head -c 100")
    if [[ "$PROXY_TEST_CERT" == *"args"* ]] || [[ "$PROXY_TEST_CERT" == *"{"* ]]; then
        echo -e "${GREEN}✅ Works with certificate trust${NC}"
    else
        echo -e "${RED}❌ Failed even with certificate${NC}"
        echo "   Error: ${PROXY_TEST_CERT:0:100}"
    fi
fi
echo ""

# 8. Check mitmproxy logs
echo -e "${YELLOW}8. Recent proxy logs...${NC}"
echo -e "${BLUE}Last 5 lines:${NC}"
docker logs transparent-proxy 2>&1 | tail -5
echo ""

# 9. Summary and recommendations
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  📋 Summary & Recommendations${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"

# Determine the most likely issue
if [ "$IPTABLES_RULES" -eq "0" ]; then
    echo -e "${RED}Main Issue: iptables rules not configured${NC}"
    echo "Fix: Restart the system with ./start-capture.sh"
elif [[ "$CERT_INFO" == "INVALID" ]]; then
    echo -e "${RED}Main Issue: Invalid certificate${NC}"
    echo "Fix: "
    echo "  1. Stop system: docker compose -f docker-compose-transparent.yml down"
    echo "  2. Remove cert volume: docker volume rm proxy-3_certs"
    echo "  3. Restart: ./start-capture.sh"
elif [[ "$PROXY_TEST" != *"{"* ]] && [[ "$PROXY_TEST_CERT" == *"{"* ]]; then
    echo -e "${YELLOW}Main Issue: Certificate trust needed${NC}"
    echo "Fix: Always run with SSL_CERT_FILE environment variable:"
    echo "  export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem"
else
    echo -e "${GREEN}System appears to be working correctly${NC}"
    echo "If you're still getting 502 errors, try:"
    echo "  1. Use the test-dns-fixed.go with custom DNS resolver"
    echo "  2. Check your firewall settings"
    echo "  3. Restart Docker: sudo systemctl restart docker"
fi

echo ""
echo -e "${YELLOW}Quick test command:${NC}"
echo 'docker exec -u appuser app sh -c "export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem && cd /proxy && go run test-dns-fixed.go"'
echo ""