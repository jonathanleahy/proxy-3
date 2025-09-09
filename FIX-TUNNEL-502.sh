#!/bin/bash
# FIX-TUNNEL-502.sh - Fix CONNECT tunnel failed 502 errors

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FIXING CONNECT TUNNEL FAILED (502)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "502 tunnel failed = mitmproxy can't reach the target server"
echo "Usually a Docker networking issue"
echo ""

# Stop old containers
echo -e "${YELLOW}Cleaning up old containers...${NC}"
docker stop mitmproxy proxy 2>/dev/null || true
docker rm mitmproxy proxy 2>/dev/null || true

# Method 1: Use host network (best for connectivity)
echo -e "${YELLOW}Method 1: Trying host network mode...${NC}"
docker run -d \
    --name mitmproxy-host \
    --network host \
    mitmproxy/mitmproxy \
    mitmdump \
        --listen-port 8080 \
        --ssl-insecure \
        --set confdir=/home/mitmproxy/.mitmproxy 2>/dev/null

if [ $? -eq 0 ]; then
    sleep 3
    if docker ps | grep -q mitmproxy-host; then
        echo -e "${GREEN}✅ Started with host network${NC}"
        
        # Test it
        echo "Testing..."
        if curl -x http://localhost:8080 --insecure -s --max-time 5 https://www.google.com -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
            echo -e "${GREEN}✅ Host network mode WORKS!${NC}"
            WORKING=true
        else
            echo -e "${RED}Host network didn't help${NC}"
            docker stop mitmproxy-host && docker rm mitmproxy-host
            WORKING=false
        fi
    else
        docker rm mitmproxy-host 2>/dev/null
        WORKING=false
    fi
else
    echo "Host network not allowed (Sysbox)"
    WORKING=false
fi

# Method 2: Bridge network with explicit DNS
if [ "$WORKING" != "true" ]; then
    echo ""
    echo -e "${YELLOW}Method 2: Bridge network with Google DNS...${NC}"
    
    docker run -d \
        --name mitmproxy-dns \
        -p 8080:8080 \
        --dns 8.8.8.8 \
        --dns 8.8.4.4 \
        mitmproxy/mitmproxy \
        mitmdump \
            --listen-port 8080 \
            --ssl-insecure \
            --set upstream_cert=false \
            --set confdir=/home/mitmproxy/.mitmproxy
    
    sleep 3
    
    # Test from inside container first
    echo "Testing DNS from inside container..."
    docker exec mitmproxy-dns nslookup google.com 2>&1 | grep -q "Address" && echo "✅ DNS works" || echo "❌ DNS failed"
    
    # Test proxy
    if curl -x http://localhost:8080 --insecure -s --max-time 5 https://www.google.com -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ DNS fix WORKS!${NC}"
        WORKING=true
        docker stop mitmproxy-host 2>/dev/null && docker rm mitmproxy-host 2>/dev/null
    else
        echo -e "${RED}DNS fix didn't help${NC}"
        docker stop mitmproxy-dns && docker rm mitmproxy-dns
        WORKING=false
    fi
fi

# Method 3: Run proxy directly on host (not in Docker)
if [ "$WORKING" != "true" ]; then
    echo ""
    echo -e "${YELLOW}Method 3: Running mitmproxy directly (no Docker)...${NC}"
    
    # Check if mitmproxy is installed
    if command -v mitmdump &> /dev/null; then
        echo "Found local mitmproxy"
    else
        echo "Installing mitmproxy locally..."
        if command -v pip3 &> /dev/null; then
            pip3 install mitmproxy
        elif command -v brew &> /dev/null; then
            brew install mitmproxy
        else
            echo -e "${RED}Can't install mitmproxy automatically${NC}"
            echo "Install with: pip3 install mitmproxy"
        fi
    fi
    
    if command -v mitmdump &> /dev/null; then
        echo "Starting local mitmproxy on port 8081..."
        mitmdump --listen-port 8081 --ssl-insecure > /tmp/mitmproxy.log 2>&1 &
        LOCAL_PID=$!
        sleep 3
        
        if curl -x http://localhost:8081 --insecure -s --max-time 5 https://www.google.com -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
            echo -e "${GREEN}✅ Local mitmproxy WORKS on port 8081!${NC}"
            echo "PID: $LOCAL_PID"
            echo "Logs: tail -f /tmp/mitmproxy.log"
            WORKING=true
            PROXY_PORT=8081
        else
            kill $LOCAL_PID 2>/dev/null
            echo -e "${RED}Local mitmproxy also failed${NC}"
        fi
    fi
fi

# Method 4: Use a different proxy
if [ "$WORKING" != "true" ]; then
    echo ""
    echo -e "${YELLOW}Method 4: Using squid proxy instead...${NC}"
    
    docker run -d \
        --name squid \
        -p 3128:3128 \
        --dns 8.8.8.8 \
        ubuntu/squid
    
    sleep 5
    
    if curl -x http://localhost:3128 -s --max-time 5 https://www.google.com -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ Squid proxy works on port 3128${NC}"
        echo "Note: Squid doesn't decrypt HTTPS, just proxies it"
        WORKING=true
        PROXY_PORT=3128
    else
        docker stop squid && docker rm squid
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RESULTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

if [ "$WORKING" = "true" ]; then
    echo -e "${GREEN}✅ Found a working solution!${NC}"
    echo ""
    echo "Working proxy details:"
    if docker ps | grep -q mitmproxy; then
        echo "  Type: mitmproxy (can decrypt HTTPS)"
        echo "  Port: 8080"
        echo "  Container: $(docker ps --filter name=mitmproxy --format '{{.Names}}')"
    elif [ -n "$LOCAL_PID" ]; then
        echo "  Type: local mitmproxy (can decrypt HTTPS)"
        echo "  Port: 8081"
        echo "  PID: $LOCAL_PID"
    elif docker ps | grep -q squid; then
        echo "  Type: squid (tunnels HTTPS, doesn't decrypt)"
        echo "  Port: 3128"
    fi
    echo ""
    echo "Test with:"
    echo "  ${GREEN}curl -x http://localhost:${PROXY_PORT:-8080} --insecure https://api.github.com${NC}"
else
    echo -e "${RED}Network issues preventing proxy from working${NC}"
    echo ""
    echo "This is likely due to:"
    echo "1. Docker network restrictions"
    echo "2. Corporate firewall"
    echo "3. DNS resolution issues"
    echo ""
    echo "Try running mitmproxy directly on your host:"
    echo "  ${YELLOW}pip3 install mitmproxy${NC}"
    echo "  ${YELLOW}mitmdump --listen-port 8080 --ssl-insecure${NC}"
fi