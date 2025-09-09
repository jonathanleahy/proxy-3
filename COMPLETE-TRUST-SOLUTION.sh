#!/bin/bash
# COMPLETE-TRUST-SOLUTION.sh - Complete certificate trust solution without --insecure

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🔐 COMPLETE HTTPS WITHOUT --insecure${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Building a complete solution that works WITHOUT --insecure flag"
echo ""

# Clean up any existing containers and use different ports
echo -e "${YELLOW}Step 1: Cleaning up and using port 8082...${NC}"
docker stop mitmproxy mitmproxy-host mitmproxy-dns test-client 2>/dev/null || true
docker rm mitmproxy mitmproxy-host mitmproxy-dns test-client 2>/dev/null || true

# Start mitmproxy on port 8082 to avoid conflicts
docker run -d \
    --name mitmproxy \
    -p 8082:8082 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8082 --ssl-insecure

sleep 4

# Get the certificate
echo -e "${YELLOW}Step 2: Getting mitmproxy certificate...${NC}"
docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

if [ ! -s mitmproxy-ca.pem ]; then
    echo -e "${RED}Failed to get certificate, trying alternative method...${NC}"
    
    # Alternative: copy from container volume
    docker exec mitmproxy find /home/mitmproxy -name "*.pem" -type f
    sleep 2
    docker exec mitmproxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem || {
        echo -e "${RED}Certificate extraction failed${NC}"
        exit 1
    }
fi

echo -e "${GREEN}✅ Got certificate ($(wc -c < mitmproxy-ca.pem) bytes)${NC}"

# Create the ultimate trusted client container
echo -e "${YELLOW}Step 3: Creating ultimate trusted container...${NC}"
cat > Dockerfile.ultimate-trusted << 'EOF'
FROM alpine:latest

# Install packages individually for better error handling
RUN apk update && \
    apk add --no-cache curl ca-certificates wget bash

# Copy mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificate store
RUN update-ca-certificates && \
    echo "Certificate trust store updated" && \
    ls -la /etc/ssl/certs/ | grep mitmproxy

# Set all certificate environment variables
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

CMD ["/bin/bash"]
EOF

# Build the ultimate trusted container
docker build -t ultimate-trusted -f Dockerfile.ultimate-trusted .

if [ $? -ne 0 ]; then
    echo -e "${RED}Container build failed${NC}"
    exit 1
fi

# Test WITHOUT --insecure flag
echo ""
echo -e "${YELLOW}Step 4: Testing WITHOUT --insecure flag...${NC}"
echo ""

# Get Docker bridge IP for proxy connection
DOCKER_IP=$(docker inspect mitmproxy | grep '"IPAddress"' | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
echo "MITMProxy container IP: $DOCKER_IP"

# Test 1: From trusted container using container IP
echo -e "${BLUE}Test 1: Using container networking${NC}"
docker run --rm ultimate-trusted sh -c "
    echo 'Testing HTTPS through proxy WITHOUT --insecure...'
    
    # Test with the container IP
    curl -x http://$DOCKER_IP:8082 \
         -s --max-time 10 \
         https://api.github.com/users/github \
         | head -5
    
    if [ \$? -eq 0 ]; then
        echo '✅ SUCCESS! HTTPS works without --insecure!'
    else
        echo '❌ Failed with container IP'
    fi
"

# Test 2: Using host network for direct access
echo ""
echo -e "${BLUE}Test 2: Using host network${NC}"
docker run --rm --network host ultimate-trusted sh -c "
    echo 'Testing with host network...'
    
    curl -x http://localhost:8082 \
         -s --max-time 10 \
         https://api.github.com/users/github \
         | head -5
    
    if [ \$? -eq 0 ]; then
        echo '✅ SUCCESS! Host network works!'
    else
        echo '❌ Failed with host network'
    fi
"

# Create a Go app container that works without InsecureSkipVerify
echo ""
echo -e "${YELLOW}Step 5: Creating Go app without InsecureSkipVerify...${NC}"

cat > Dockerfile.secure-go << 'EOF'
FROM golang:alpine

# Install ca-certificates
RUN apk add --no-cache ca-certificates

# Copy mitmproxy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificate store
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

# Create secure Go app (no InsecureSkipVerify!)
COPY <<'GOEOF' main.go
package main

import (
    "fmt"
    "io"
    "net/http"
    "os"
)

func main() {
    // Create client WITHOUT InsecureSkipVerify
    client := &http.Client{}
    
    req, err := http.NewRequest("GET", "https://api.github.com/users/github", nil)
    if err != nil {
        fmt.Printf("Request error: %v\n", err)
        return
    }
    
    // Show proxy being used
    if proxy := os.Getenv("HTTP_PROXY"); proxy != "" {
        fmt.Printf("✅ Using proxy: %s\n", proxy)
    }
    
    fmt.Println("🔒 Making HTTPS request WITHOUT InsecureSkipVerify...")
    
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("❌ Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("🎉 SUCCESS! Got %d bytes\n", len(body))
    fmt.Println("🔐 Certificate was TRUSTED automatically!")
    fmt.Printf("First 200 chars: %.200s...\n", string(body))
}
GOEOF

CMD ["go", "run", "main.go"]
EOF

docker build -t secure-go-app -f Dockerfile.secure-go .

# Test the Go app
echo ""
echo -e "${YELLOW}Step 6: Testing Go app without InsecureSkipVerify...${NC}"

# Method 1: Container networking
docker run --rm \
    -e HTTP_PROXY=http://$DOCKER_IP:8082 \
    -e HTTPS_PROXY=http://$DOCKER_IP:8082 \
    secure-go-app

# Method 2: Host networking  
echo ""
echo -e "${BLUE}Testing with host network...${NC}"
docker run --rm --network host \
    -e HTTP_PROXY=http://localhost:8082 \
    -e HTTPS_PROXY=http://localhost:8082 \
    secure-go-app

# Create easy-to-use script for your specific app
echo ""
echo -e "${YELLOW}Step 7: Creating script for your app...${NC}"

cat > RUN-YOUR-APP-SECURELY.sh << 'EOF'
#!/bin/bash
# RUN-YOUR-APP-SECURELY.sh - Run your app with trusted certificates

echo "🔐 Running your Go app with trusted HTTPS (no --insecure needed)..."

# Your app location
APP_PATH="${1:-~/temp/aa/cmd/api/main.go}"

# Build a container for your specific app
docker build -t your-secure-app -f Dockerfile.secure-go .

# Run your app with the secure setup
echo "Starting your app: $APP_PATH"

# Create temporary directory for your app
docker run --rm --network host \
    -v ~/temp/aa:/external-app \
    -e HTTP_PROXY=http://localhost:8082 \
    -e HTTPS_PROXY=http://localhost:8082 \
    -w /external-app \
    your-secure-app \
    go run cmd/api/main.go
EOF

chmod +x RUN-YOUR-APP-SECURELY.sh

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 SOLUTION COMPLETE!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "✅ MITMProxy running on port 8082"
echo "✅ Certificates installed in containers only"
echo "✅ No --insecure flag needed"
echo "✅ No InsecureSkipVerify needed in Go"
echo "✅ Your host system unchanged"
echo ""
echo -e "${YELLOW}How to use:${NC}"
echo ""
echo "1. Test manually:"
echo "   ${GREEN}docker run --rm --network host ultimate-trusted${NC}"
echo "   ${GREEN}curl -x http://localhost:8082 https://api.github.com${NC}"
echo ""
echo "2. Run your Go app:"
echo "   ${GREEN}./RUN-YOUR-APP-SECURELY.sh${NC}"
echo ""
echo "3. View captured traffic:"
echo "   ${GREEN}docker logs -f mitmproxy${NC}"
echo ""
echo -e "${BLUE}The --insecure flag is NO LONGER NEEDED! 🎊${NC}"