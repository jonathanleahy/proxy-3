#!/bin/bash
# USE-SYSTEM-CERTS.sh - Use your system's CA certificates with mitmproxy

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  USING SYSTEM CA CERTIFICATES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Brew regenerated your CA bundle - let's use it!"
echo ""

# Find system CA bundle locations
echo -e "${YELLOW}Finding your system CA certificate bundle...${NC}"

# Common locations on macOS after brew Python install
CA_LOCATIONS=(
    "/usr/local/etc/ca-certificates/cert.pem"
    "/usr/local/etc/openssl/cert.pem"
    "/usr/local/etc/openssl@1.1/cert.pem"
    "/usr/local/etc/openssl@3/cert.pem"
    "/opt/homebrew/etc/ca-certificates/cert.pem"
    "/opt/homebrew/etc/openssl/cert.pem"
    "/opt/homebrew/etc/openssl@1.1/cert.pem"
    "/opt/homebrew/etc/openssl@3/cert.pem"
    "/etc/ssl/cert.pem"
    "/etc/ssl/certs/ca-certificates.crt"
    "$(brew --prefix 2>/dev/null)/etc/ca-certificates/cert.pem"
    "$(python3 -m certifi 2>/dev/null)"
)

SYSTEM_CA=""
for ca in "${CA_LOCATIONS[@]}"; do
    if [ -f "$ca" ]; then
        echo -e "${GREEN}✅ Found: $ca${NC}"
        SYSTEM_CA="$ca"
        break
    fi
done

if [ -z "$SYSTEM_CA" ]; then
    echo -e "${RED}Could not find system CA bundle${NC}"
    echo "Trying Python's certifi module..."
    SYSTEM_CA=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null)
    if [ -f "$SYSTEM_CA" ]; then
        echo -e "${GREEN}✅ Found via Python certifi: $SYSTEM_CA${NC}"
    fi
fi

# Get mitmproxy certificate
echo ""
echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"

if docker ps | grep -q mitmproxy; then
    docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null
    if [ -s mitmproxy-ca.pem ]; then
        echo -e "${GREEN}✅ Got mitmproxy certificate${NC}"
    fi
else
    echo "MITMProxy not running, checking for existing certificate..."
    if [ -f mitmproxy-ca.pem ]; then
        echo -e "${GREEN}✅ Using existing certificate${NC}"
    else
        echo -e "${RED}No mitmproxy certificate found${NC}"
        echo "Run ./WORKING-MITM.sh first"
        exit 1
    fi
fi

# Create combined certificate bundle
echo ""
echo -e "${YELLOW}Creating combined certificate bundle...${NC}"

if [ -f "$SYSTEM_CA" ]; then
    # Combine system certs with mitmproxy cert
    cat "$SYSTEM_CA" > combined-ca-bundle.pem
    echo "" >> combined-ca-bundle.pem
    cat mitmproxy-ca.pem >> combined-ca-bundle.pem
    echo -e "${GREEN}✅ Created combined-ca-bundle.pem${NC}"
    
    # Count certificates
    CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" combined-ca-bundle.pem)
    echo "   Contains $CERT_COUNT certificates"
else
    # Just use mitmproxy cert
    cp mitmproxy-ca.pem combined-ca-bundle.pem
    echo -e "${YELLOW}Using only mitmproxy certificate${NC}"
fi

# Test with different certificate configurations
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING CERTIFICATE CONFIGURATIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

PROXY_PORT=8080

# Test 1: With combined bundle
echo -e "${YELLOW}Test 1: Using combined certificate bundle:${NC}"
curl -x http://localhost:$PROXY_PORT \
     --cacert combined-ca-bundle.pem \
     -s --max-time 5 \
     https://api.github.com \
     -o /dev/null \
     -w "Status: %{http_code}, SSL Result: %{ssl_verify_result}\n" || echo "Failed"

# Test 2: With just mitmproxy cert
echo ""
echo -e "${YELLOW}Test 2: Using only mitmproxy certificate:${NC}"
curl -x http://localhost:$PROXY_PORT \
     --cacert mitmproxy-ca.pem \
     -s --max-time 5 \
     https://api.github.com \
     -o /dev/null \
     -w "Status: %{http_code}, SSL Result: %{ssl_verify_result}\n" || echo "Failed"

# Test 3: With system default (after brew update)
echo ""
echo -e "${YELLOW}Test 3: Using system default certificates:${NC}"
curl -x http://localhost:$PROXY_PORT \
     -s --max-time 5 \
     https://api.github.com \
     -o /dev/null \
     -w "Status: %{http_code}, SSL Result: %{ssl_verify_result}\n" 2>&1 | head -2

# Export for other tools
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  EXPORT SETTINGS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo "To use the combined certificate bundle:"
echo ""
echo "For curl:"
echo "  ${GREEN}export CURL_CA_BUNDLE=$(pwd)/combined-ca-bundle.pem${NC}"
echo ""
echo "For Python requests:"
echo "  ${GREEN}export REQUESTS_CA_BUNDLE=$(pwd)/combined-ca-bundle.pem${NC}"
echo ""
echo "For Node.js:"
echo "  ${GREEN}export NODE_EXTRA_CA_CERTS=$(pwd)/combined-ca-bundle.pem${NC}"
echo ""
echo "For Go:"
echo "  ${GREEN}export SSL_CERT_FILE=$(pwd)/combined-ca-bundle.pem${NC}"
echo ""
echo "For all applications:"
echo "  ${GREEN}export SSL_CERT_FILE=$(pwd)/combined-ca-bundle.pem${NC}"
echo "  ${GREEN}export SSL_CERT_DIR=/etc/ssl/certs${NC}"

# Create convenience script
cat > setup-certs.sh << EOF
#!/bin/bash
# Source this file to set up certificates: source ./setup-certs.sh

export CURL_CA_BUNDLE=$(pwd)/combined-ca-bundle.pem
export REQUESTS_CA_BUNDLE=$(pwd)/combined-ca-bundle.pem
export NODE_EXTRA_CA_CERTS=$(pwd)/combined-ca-bundle.pem
export SSL_CERT_FILE=$(pwd)/combined-ca-bundle.pem

echo "Certificate environment variables set!"
echo "Now curl and other tools will trust mitmproxy"
EOF

chmod +x setup-certs.sh

echo ""
echo -e "${GREEN}Run this to set up certificates for your session:${NC}"
echo "  ${GREEN}source ./setup-certs.sh${NC}"
echo ""
echo "Then all your tools will trust mitmproxy!"