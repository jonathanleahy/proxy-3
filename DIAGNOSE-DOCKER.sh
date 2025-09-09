#!/bin/bash
# DIAGNOSE-DOCKER.sh - Find out why containers won't start

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DOCKER DIAGNOSTICS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# 1. Check Docker daemon
echo -e "${YELLOW}1. Docker daemon status:${NC}"
if docker version > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker is running${NC}"
    docker version --format 'Server version: {{.Server.Version}}'
else
    echo -e "${RED}❌ Docker is not running or not accessible${NC}"
    exit 1
fi
echo ""

# 2. Check if we can run basic containers
echo -e "${YELLOW}2. Testing basic container run:${NC}"
if docker run --rm alpine:latest echo "Hello from Alpine" 2>/dev/null; then
    echo -e "${GREEN}✅ Can run Alpine containers${NC}"
else
    echo -e "${RED}❌ Cannot run Alpine containers${NC}"
    echo "Error details:"
    docker run --rm alpine:latest echo "test" 2>&1
fi
echo ""

# 3. Check if we can pull images
echo -e "${YELLOW}3. Testing image availability:${NC}"
echo -n "  busybox: "
if docker run --rm busybox echo "ok" > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

echo -n "  alpine: "
if docker run --rm alpine echo "ok" > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

echo -n "  ubuntu: "
if docker run --rm ubuntu echo "ok" > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi
echo ""

# 4. Check network connectivity
echo -e "${YELLOW}4. Container network test:${NC}"
if docker run --rm alpine ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Containers can reach internet${NC}"
else
    echo -e "${RED}❌ Containers cannot reach internet${NC}"
    echo "This might be why package installation fails"
fi
echo ""

# 5. Check port availability
echo -e "${YELLOW}5. Port availability:${NC}"
for port in 8080 8084; do
    echo -n "  Port $port: "
    if lsof -i :$port > /dev/null 2>&1; then
        echo -e "${RED}IN USE${NC}"
        lsof -i :$port | grep LISTEN | head -1
    else
        echo -e "${GREEN}FREE${NC}"
    fi
done
echo ""

# 6. Test mitmproxy specifically
echo -e "${YELLOW}6. Testing mitmproxy image:${NC}"
if docker run --rm -d --name test-mitm mitmproxy/mitmproxy mitmdump > /dev/null 2>&1; then
    sleep 2
    if docker ps | grep -q test-mitm; then
        echo -e "${GREEN}✅ mitmproxy can start${NC}"
        docker stop test-mitm > /dev/null 2>&1
        docker rm test-mitm > /dev/null 2>&1
    else
        echo -e "${RED}❌ mitmproxy exits immediately${NC}"
        echo "Last logs:"
        docker logs test-mitm 2>&1 | tail -5
        docker rm test-mitm > /dev/null 2>&1
    fi
else
    echo -e "${RED}❌ Cannot run mitmproxy image${NC}"
    echo "Try: docker pull mitmproxy/mitmproxy"
fi
echo ""

# 7. Test with minimal setup
echo -e "${YELLOW}7. Testing minimal proxy setup:${NC}"
docker stop minimal-proxy minimal-app 2>/dev/null || true
docker rm minimal-proxy minimal-app 2>/dev/null || true

# Try the simplest possible proxy
docker run -d --name minimal-proxy -p 9999:8080 mitmproxy/mitmproxy mitmdump 2>&1
sleep 3

if docker ps | grep -q minimal-proxy; then
    echo -e "${GREEN}✅ Minimal proxy works on port 9999${NC}"
    
    # Test if we can connect
    if curl -s http://localhost:9999 2>&1 | grep -q "Proxy"; then
        echo -e "${GREEN}✅ Can connect to proxy${NC}"
    else
        echo -e "${YELLOW}⚠️  Proxy running but not responding as expected${NC}"
    fi
else
    echo -e "${RED}❌ Even minimal proxy won't start${NC}"
    echo "Error logs:"
    docker logs minimal-proxy 2>&1 | tail -10
fi

# Clean up
docker stop minimal-proxy 2>/dev/null || true
docker rm minimal-proxy 2>/dev/null || true
echo ""

# 8. System information
echo -e "${YELLOW}8. System information:${NC}"
echo "OS: $(uname -s)"
echo "Architecture: $(uname -m)"
echo "Docker info:"
docker info --format 'Storage Driver: {{.Driver}}'
docker info --format 'Cgroup Version: {{.CgroupVersion}}'
echo ""

# 9. Suggest solutions
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SUGGESTED SOLUTIONS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if ! docker run --rm alpine ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${YELLOW}Network Issue Detected:${NC}"
    echo "1. Check if you're behind a corporate firewall"
    echo "2. Try with DNS: --dns 8.8.8.8"
    echo "3. Check Docker's network settings"
    echo ""
fi

echo -e "${YELLOW}Try this minimal working example:${NC}"
echo ""
cat << 'EOF'
# Simple HTTP server (no proxy needed)
docker run -d --name simple-http -p 8080:8080 busybox \
    sh -c "while true; do echo -e 'HTTP/1.1 200 OK\r\n\r\nHello World' | nc -l -p 8080; done"

# Test it
curl http://localhost:8080
EOF