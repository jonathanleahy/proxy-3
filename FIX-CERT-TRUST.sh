#!/bin/bash
# Fix x509 certificate trust issues for Go apps

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing x509 Certificate Trust${NC}"
echo "=================================="
echo ""

# Get or generate certificate
if [ ! -f mitmproxy-ca.pem ]; then
    echo -e "${YELLOW}Getting mitmproxy certificate...${NC}"
    
    # Try to get from running proxy
    if docker exec proxy cat /root/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem 2>/dev/null; then
        echo -e "${GREEN}✅ Got certificate from proxy${NC}"
    else
        # Generate one
        echo -e "${YELLOW}Generating certificate...${NC}"
        docker run --rm -v $(pwd):/certs mitmproxy/mitmproxy sh -c "
            mitmdump --quiet &
            PID=\$!
            sleep 3
            kill \$PID 2>/dev/null
            cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/mitmproxy-ca.pem
        "
    fi
fi

echo -e "${GREEN}Certificate available: $(ls -lh mitmproxy-ca.pem)${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}SOLUTION 1: Disable Certificate Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Add this to your Go code (FOR TESTING ONLY):"
echo ""
cat << 'EOF'
import (
    "crypto/tls"
    "net/http"
)

client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: true,  // Skip certificate verification
        },
    },
}
EOF
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}SOLUTION 2: Trust Certificate in Container${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Run your app with certificate mounted and trusted:"
echo ""
cat << 'EOF'
docker run \
    -v $(pwd)/mitmproxy-ca.pem:/usr/local/share/ca-certificates/mitmproxy.crt:ro \
    -e HTTP_PROXY=http://172.17.0.1:8084 \
    -e HTTPS_PROXY=http://172.17.0.1:8084 \
    your-app-image \
    sh -c "
        # Install certificate
        update-ca-certificates
        
        # Run your app
        go run your-app.go
    "
EOF
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}SOLUTION 3: Use System Certificate Pool${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Set these environment variables when running your app:"
echo ""
echo "export SSL_CERT_FILE=$(pwd)/mitmproxy-ca.pem"
echo "export SSL_CERT_DIR=/etc/ssl/certs"
echo "export CA_BUNDLE=$(pwd)/mitmproxy-ca.pem"
echo "export REQUESTS_CA_BUNDLE=$(pwd)/mitmproxy-ca.pem"
echo "export NODE_EXTRA_CA_CERTS=$(pwd)/mitmproxy-ca.pem"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}QUICK FIX for START scripts:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "If using START-FIX scripts, add this to your Go code:"
echo ""
echo -e "${YELLOW}Option 1 - Skip verification (easiest):${NC}"
cat << 'EOF'
TLSClientConfig: &tls.Config{
    InsecureSkipVerify: true,
}
EOF
echo ""
echo -e "${YELLOW}Option 2 - Load certificate:${NC}"
cat << 'EOF'
import (
    "crypto/x509"
    "io/ioutil"
)

// Load mitmproxy certificate
caCert, _ := ioutil.ReadFile("/ca.pem")
caCertPool := x509.NewCertPool()
caCertPool.AppendCertsFromPEM(caCert)

client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,
        TLSClientConfig: &tls.Config{
            RootCAs: caCertPool,
        },
    },
}
EOF
echo ""
echo -e "${GREEN}The certificate is at: $(pwd)/mitmproxy-ca.pem${NC}"