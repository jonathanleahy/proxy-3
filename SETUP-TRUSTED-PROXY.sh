#!/bin/bash
# SETUP-TRUSTED-PROXY.sh - Quick certificate trust setup for main branch

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔐 Setting up trusted HTTPS proxy (no --insecure needed)${NC}"

# Start mitmproxy
echo -e "${YELLOW}Starting mitmproxy...${NC}"
docker run -d \
    --name mitmproxy-trusted \
    -p 8083:8083 \
    mitmproxy/mitmproxy \
    mitmdump --listen-port 8083 --ssl-insecure

sleep 4

# Get certificate
echo -e "${YELLOW}Getting certificate...${NC}"
docker exec mitmproxy-trusted cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > mitmproxy-ca.pem

# Create Go container with certificate pre-installed
echo -e "${YELLOW}Creating Go container with trusted certificate...${NC}"
cat > Dockerfile.go-trusted-simple << 'EOF'
FROM golang:alpine

# Install ca-certificates
RUN apk add --no-cache ca-certificates

# Copy certificate
COPY mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy.crt

# Update certificates
RUN update-ca-certificates

# Set certificate environment
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /go/src/app
EOF

docker build -t go-trusted -f Dockerfile.go-trusted-simple .

echo -e "${GREEN}✅ Trusted Go container ready!${NC}"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "1. Run your app in the trusted container:"
echo "   ${GREEN}docker run --rm -it -v ~/temp/aa:/go/src/app -e HTTP_PROXY=http://host.docker.internal:8083 -e HTTPS_PROXY=http://host.docker.internal:8083 --add-host host.docker.internal:host-gateway go-trusted${NC}"
echo ""
echo "2. In the container, run your app:"
echo "   ${GREEN}go run cmd/api/main.go${NC}"
echo ""
echo "3. View captures:"
echo "   ${GREEN}docker logs -f mitmproxy-trusted${NC}"
echo ""
echo -e "${GREEN}No InsecureSkipVerify needed! 🎉${NC}"