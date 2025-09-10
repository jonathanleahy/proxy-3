#!/bin/bash
# run-app.sh - Run your Go application with HTTPS capture and DNS fix

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}❌ Error: No command provided${NC}"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Examples:"
    echo "  $0 'go run main.go'"
    echo "  $0 'go run cmd/server/main.go'"
    echo "  $0 './my-compiled-app'"
    echo "  $0 'go test ./...'"
    echo ""
    exit 1
fi

APP_CMD="$*"

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  🚀 Running App with HTTPS Capture${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if capture system is running
if ! docker ps | grep -q transparent-proxy; then
    echo -e "${RED}❌ Error: Capture system is not running${NC}"
    echo ""
    echo "Please start it first with:"
    echo -e "${YELLOW}  ./start-capture.sh${NC}"
    echo ""
    exit 1
fi

# Check if app container is running
if ! docker ps | grep -q "app"; then
    echo -e "${RED}❌ Error: App container is not running${NC}"
    echo ""
    echo "Please restart the system with:"
    echo -e "${YELLOW}  docker compose -f docker-compose-transparent.yml down${NC}"
    echo -e "${YELLOW}  ./start-capture.sh${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Capture system is running${NC}"
echo -e "${YELLOW}Command: ${NC}$APP_CMD"
echo ""

# Create DNS resolver wrapper for Go apps
echo -e "${YELLOW}Setting up DNS resolver...${NC}"
docker exec app sh -c "cat > /tmp/dns-resolver.go << 'EOF'
package dnsfix

import (
    \"context\"
    \"net\"
    \"net/http\"
    \"time\"
)

// GetHTTPClient returns an HTTP client with custom DNS resolver
func GetHTTPClient() *http.Client {
    return &http.Client{
        Transport: &http.Transport{
            DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                dialer := &net.Dialer{
                    Timeout: 30 * time.Second,
                    Resolver: &net.Resolver{
                        PreferGo: true,
                        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                            d := net.Dialer{Timeout: 5 * time.Second}
                            return d.DialContext(ctx, network, \"8.8.8.8:53\")
                        },
                    },
                }
                return dialer.DialContext(ctx, network, addr)
            },
        },
        Timeout: 30 * time.Second,
    }
}
EOF
"

# Create run wrapper script inside container
docker exec app sh -c "cat > /tmp/run-with-capture.sh << 'EOF'
#!/bin/sh
# Wrapper script to run apps with proper environment

# Set certificate trust
export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem

# Go-specific settings for DNS
export GODEBUG=netdns=go
export GOPROXY=direct

# Info for the user
echo '📦 Environment configured:'
echo '  • Certificate: /certs/mitmproxy-ca-cert.pem'
echo '  • DNS: Using Google DNS (8.8.8.8)'
echo '  • User: appuser (UID 1000)'
echo ''

# Change to appropriate directory
if [ -d /app ] && [ \"\$(ls -A /app 2>/dev/null)\" ]; then
    echo '  • App directory: /app (mounted from host)'
    cd /app
else
    echo '  • App directory: /proxy (default)'
    cd /proxy
fi

# Run the command
exec \$@
EOF
chmod +x /tmp/run-with-capture.sh
"

echo -e "${GREEN}✅ Environment prepared${NC}"
echo ""

# Run the app as appuser
echo -e "${BLUE}Starting application...${NC}"
echo "────────────────────────────────────────────────"
echo ""

# Execute the command in the container as appuser
docker exec -it -u appuser app /tmp/run-with-capture.sh $APP_CMD

EXIT_CODE=$?

echo ""
echo "────────────────────────────────────────────────"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Application completed successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Application exited with code: $EXIT_CODE${NC}"
fi

echo ""
echo -e "${BLUE}📊 Capture Statistics:${NC}"

# Show capture stats
CAPTURE_COUNT=$(ls -1 captured/*.json 2>/dev/null | wc -l)
if [ $CAPTURE_COUNT -gt 0 ]; then
    LATEST_CAPTURE=$(ls -t captured/*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_CAPTURE" ]; then
        echo -e "  • Total capture files: ${GREEN}$CAPTURE_COUNT${NC}"
        echo -e "  • Latest capture: ${GREEN}$(basename $LATEST_CAPTURE)${NC}"
        
        # Check if any captures from this session
        RECENT_CAPTURES=$(find captured -name "*.json" -mmin -5 2>/dev/null | wc -l)
        if [ $RECENT_CAPTURES -gt 0 ]; then
            echo -e "  • Recent captures (last 5 min): ${GREEN}$RECENT_CAPTURES${NC}"
        fi
    fi
else
    echo -e "  • No captures found yet"
fi

echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "  • Monitor live captures: ./monitor-proxy.sh"
echo "  • View proxy logs: docker logs -f transparent-proxy"
echo "  • Force save captures: docker exec transparent-proxy pkill -USR1 mitmdump"
echo ""

exit $EXIT_CODE