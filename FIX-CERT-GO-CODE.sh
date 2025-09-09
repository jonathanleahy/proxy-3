#!/bin/bash
# Instructions for fixing x509 certificate issues in Go code

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GO CODE CHANGES FOR CERTIFICATE TRUST${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Your Go app at ~/temp/aa/cmd/api/main.go needs one of these changes:${NC}"
echo ""

echo -e "${GREEN}OPTION 1: Quick Testing Fix (Add InsecureSkipVerify)${NC}"
echo "════════════════════════════════════════════════════"
echo ""
echo "Find where you create your http.Client and add InsecureSkipVerify:"
echo ""
cat << 'EOF'
import (
    "crypto/tls"
    "net/http"
)

client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,  // Use proxy settings
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: true,      // Skip certificate verification (TESTING ONLY!)
        },
    },
}
EOF
echo ""
echo -e "${RED}⚠️  WARNING: This skips ALL certificate verification - testing only!${NC}"
echo ""

echo -e "${GREEN}OPTION 2: Proper Certificate Loading${NC}"
echo "══════════════════════════════════════"
echo ""
echo "Load the mitmproxy certificate properly:"
echo ""
cat << 'EOF'
import (
    "crypto/tls"
    "crypto/x509"
    "io/ioutil"
    "net/http"
    "log"
)

// Load the mitmproxy certificate
caCert, err := ioutil.ReadFile("/ca.pem")
if err != nil {
    log.Fatal("Error loading certificate:", err)
}

// Create certificate pool
caCertPool := x509.NewCertPool()
if !caCertPool.AppendCertsFromPEM(caCert) {
    log.Fatal("Failed to parse certificate")
}

// Create HTTP client with certificate
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,  // Use proxy settings
        TLSClientConfig: &tls.Config{
            RootCAs: caCertPool,            // Use our certificate pool
        },
    },
}
EOF
echo ""

echo -e "${GREEN}OPTION 3: Use Default Transport (Simplest)${NC}"
echo "═══════════════════════════════════════════"
echo ""
echo "If your app doesn't explicitly create an http.Client, it might work with just:"
echo ""
cat << 'EOF'
// The START-FIX-2.sh script sets SSL_CERT_FILE=/ca.pem
// Go's default HTTP client will respect this environment variable

// Just use http.Get, http.Post, etc. directly:
resp, err := http.Get("https://api.example.com/data")

// Or if you need a client, use the default transport:
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,
    },
}
EOF
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WHICH OPTION TO CHOOSE?${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}For quick testing:${NC} Use Option 1 (InsecureSkipVerify)"
echo -e "${YELLOW}For production-like:${NC} Use Option 2 (Load certificate)"
echo -e "${YELLOW}If not sure:${NC} Try Option 3 first, then Option 1"
echo ""
echo -e "${GREEN}After making the change:${NC}"
echo "1. Save your Go file"
echo "2. Run: ./START-FIX-2.sh"
echo "3. Your app should now work with HTTPS!"
echo ""
echo -e "${YELLOW}The proxy will capture all HTTPS traffic at:${NC}"
echo "  http://localhost:8090/viewer"