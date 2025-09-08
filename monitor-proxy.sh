#!/bin/bash
# Monitor script for transparent proxy system

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${BLUE}📊 Transparent Proxy System Monitor${NC}"
echo "========================================="

while true; do
    echo -e "\n${YELLOW}[$(date '+%H:%M:%S')]${NC} System Status:"
    
    # Check containers
    echo -n "  Containers: "
    if docker ps | grep -q transparent-proxy && docker ps | grep -q app; then
        echo -e "${GREEN}✅ Running${NC}"
    else
        echo -e "${RED}❌ Not running${NC}"
    fi
    
    # Check mitmproxy
    echo -n "  Mitmproxy: "
    if docker exec transparent-proxy ss -tlnp 2>/dev/null | grep -q ':8084'; then
        echo -e "${GREEN}✅ Listening on 8084${NC}"
    else
        echo -e "${RED}❌ Not listening${NC}"
    fi
    
    # Check app process
    echo -n "  App Process: "
    APP_USER=$(docker exec app sh -c "ps aux | grep 'go run main.go' | grep -v grep | awk '{print \$1}'" 2>/dev/null | head -1)
    if [ "$APP_USER" = "appuser" ]; then
        echo -e "${GREEN}✅ Running as appuser (UID 1000)${NC}"
    elif [ "$APP_USER" = "root" ]; then
        echo -e "${RED}❌ Running as root (traffic NOT intercepted!)${NC}"
    else
        echo -e "${YELLOW}⚠️  Not running${NC}"
    fi
    
    # Check iptables counters
    echo -n "  Traffic Intercepted: "
    PACKETS=$(docker exec transparent-proxy iptables -t nat -L OUTPUT -v -n 2>/dev/null | grep "443.*REDIRECT" | awk '{print $1}')
    if [ -n "$PACKETS" ] && [ "$PACKETS" != "0" ]; then
        echo -e "${GREEN}✅ $PACKETS packets${NC}"
    else
        echo -e "${YELLOW}⚠️  No HTTPS traffic intercepted${NC}"
    fi
    
    # Check recent captures
    echo -n "  Recent Captures: "
    RECENT=$(find captured -name "*.json" -mmin -5 2>/dev/null | wc -l)
    if [ $RECENT -gt 0 ]; then
        echo -e "${GREEN}✅ $RECENT files in last 5 min${NC}"
    else
        echo -e "${YELLOW}⚠️  None in last 5 min${NC}"
    fi
    
    # Check last capture time
    LAST_CAPTURE=$(ls -t captured/*.json 2>/dev/null | head -1)
    if [ -n "$LAST_CAPTURE" ]; then
        LAST_TIME=$(stat -c %y "$LAST_CAPTURE" | cut -d' ' -f2 | cut -d'.' -f1)
        echo "  Last Capture: $LAST_TIME"
    fi
    
    echo -e "\n${BLUE}Quick Actions:${NC}"
    echo "  [1] Restart app as appuser"
    echo "  [2] Test health endpoint"
    echo "  [3] Test users endpoint (HTTPS)"
    echo "  [4] Show mitmproxy logs"
    echo "  [5] Force save captures"
    echo "  [q] Quit monitor"
    echo -n "  Select action (or wait 5s): "
    
    # Read with timeout
    if read -t 5 -n 1 action; then
        echo ""
        case $action in
            1)
                echo -e "${YELLOW}Restarting app as appuser...${NC}"
                docker exec app sh -c "pkill -f 'go run' 2>/dev/null || true"
                sleep 1
                docker exec -d app su-exec appuser sh -c "cd /proxy/example-app && go run main.go"
                sleep 2
                ;;
            2)
                echo -e "${YELLOW}Testing health endpoint...${NC}"
                curl -s http://localhost:8080/health | jq . 2>/dev/null || echo "Failed"
                sleep 2
                ;;
            3)
                echo -e "${YELLOW}Testing users endpoint...${NC}"
                curl -s http://localhost:8080/users | jq '.message' 2>/dev/null || echo "Failed"
                sleep 2
                ;;
            4)
                echo -e "${YELLOW}Mitmproxy logs (last 20 lines):${NC}"
                docker logs transparent-proxy --tail 20 2>&1
                sleep 3
                ;;
            5)
                echo -e "${YELLOW}Forcing capture save...${NC}"
                docker exec transparent-proxy sh -c "kill -USR1 \$(cat /tmp/mitmproxy.pid 2>/dev/null) 2>/dev/null" || echo "Failed"
                sleep 2
                ;;
            q)
                echo -e "${GREEN}Exiting monitor...${NC}"
                exit 0
                ;;
        esac
    fi
done