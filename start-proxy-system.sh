#!/bin/bash
# Complete startup script for transparent HTTPS proxy system

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default command if none provided
DEFAULT_CMD="cd /proxy/example-app && go run main.go"

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Start the transparent HTTPS proxy system and run a command in the app container."
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -m, --monitor  Start the monitor after setup"
    echo "  -t, --test     Run tests after setup"
    echo "  -s, --skip     Skip the startup tests"
    echo ""
    echo "COMMAND:"
    echo "  Command to run in the app container (default: example app)"
    echo "  Must be quoted if it contains spaces"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                    # Run default example app"
    echo "  $0 'go run myapp.go'                 # Run custom Go app"
    echo "  $0 'python3 /app/server.py'          # Run Python app"
    echo "  $0 --monitor 'node /app/server.js'   # Run Node.js app and monitor"
    echo ""
    echo "DEFAULT COMMAND:"
    echo "  $DEFAULT_CMD"
    exit 0
}

# Parse arguments
MONITOR_AFTER=false
TEST_AFTER=false
SKIP_TESTS=false
APP_COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -m|--monitor)
            MONITOR_AFTER=true
            shift
            ;;
        -t|--test)
            TEST_AFTER=true
            shift
            ;;
        -s|--skip)
            SKIP_TESTS=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Assume remaining args are the command
            APP_COMMAND="$*"
            break
            ;;
    esac
done

# Use default if no command provided
if [ -z "$APP_COMMAND" ]; then
    APP_COMMAND="$DEFAULT_CMD"
    echo -e "${YELLOW}ℹ️  No command specified, using default: $APP_COMMAND${NC}"
fi

echo -e "${BLUE}🚀 Starting Transparent HTTPS Proxy System${NC}"
echo "========================================="
echo -e "${YELLOW}Command to run: $APP_COMMAND${NC}"
echo ""

# Function to check if containers are running
check_containers() {
    if docker ps | grep -q transparent-proxy && docker ps | grep -q app; then
        return 0
    else
        return 1
    fi
}

# Function to wait for mitmproxy certificate
wait_for_cert() {
    echo -e "${YELLOW}⏳ Waiting for mitmproxy certificate...${NC}"
    local count=0
    
    # Check if certificate exists in container
    while ! docker exec transparent-proxy test -f /certs/mitmproxy-ca-cert.pem 2>/dev/null && [ $count -lt 30 ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if docker exec transparent-proxy test -f /certs/mitmproxy-ca-cert.pem 2>/dev/null; then
        echo -e "${GREEN}✅ Certificate found in container${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Certificate not found, but continuing...${NC}"
        return 0  # Continue anyway as certificate might be generated later
    fi
}

# Function to start the app as appuser
start_app() {
    echo -e "${YELLOW}🔧 Starting app as appuser (UID 1000)...${NC}"
    echo -e "${BLUE}Command: $APP_COMMAND${NC}"
    
    # Kill any existing processes first
    docker exec app sh -c "pkill -f 'go run' 2>/dev/null || true; pkill -f 'python' 2>/dev/null || true; pkill -f 'node' 2>/dev/null || true"
    sleep 1
    
    # Start the app as appuser (UID 1000) so traffic gets intercepted
    docker exec -d app su-exec appuser sh -c "$APP_COMMAND"
    
    # Wait for app to start
    sleep 3
    
    # Verify it's running
    if docker exec app sh -c "ps aux | grep -v grep" | grep -q appuser; then
        echo -e "${GREEN}✅ App running as appuser${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to start app as appuser${NC}"
        return 1
    fi
}

# Function to test the system
test_system() {
    echo -e "${YELLOW}🧪 Testing system...${NC}"
    
    # Test health endpoint
    if curl -s http://localhost:8080/health | grep -q "healthy"; then
        echo -e "${GREEN}✅ Health endpoint working${NC}"
    else
        echo -e "${RED}❌ Health endpoint not responding${NC}"
    fi
    
    # Test users endpoint (triggers HTTPS)
    if curl -s http://localhost:8080/users | grep -q "success"; then
        echo -e "${GREEN}✅ Users endpoint working (HTTPS interception)${NC}"
    else
        echo -e "${YELLOW}⚠️  Users endpoint returned error${NC}"
    fi
    
    # Check for recent captures
    local recent_captures=$(find captured -name "*.json" -mmin -5 2>/dev/null | wc -l)
    if [ $recent_captures -gt 0 ]; then
        echo -e "${GREEN}✅ Recent captures found: $recent_captures files${NC}"
    else
        echo -e "${YELLOW}⚠️  No recent captures in last 5 minutes${NC}"
    fi
}

# Function to cleanup existing processes
cleanup_existing() {
    echo -e "${YELLOW}🧹 Cleaning up existing processes...${NC}"
    
    # Kill any processes running as root (wrong!)
    docker exec app sh -c "ps aux | grep 'go run' | grep root | awk '{print \$1}' | xargs -r kill -9" 2>/dev/null || true
    docker exec app sh -c "pkill -f 'python' 2>/dev/null || true; pkill -f 'node' 2>/dev/null || true" 2>/dev/null || true
    
    # Kill local zombie processes
    pkill -f "transparent-capture.sh" 2>/dev/null || true
    pkill -f "go run cmd/main.go" 2>/dev/null || true
    
    sleep 2
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}

# Main execution
echo -e "${BLUE}Step 1: Checking Docker containers${NC}"
if check_containers; then
    echo -e "${GREEN}✅ Containers are running${NC}"
    # Clean up any incorrectly running processes
    cleanup_existing
else
    echo -e "${YELLOW}⚠️  Containers not running, starting them...${NC}"
    docker compose -f docker-compose-transparent.yml up -d
    sleep 5
fi

echo -e "\n${BLUE}Step 2: Waiting for certificate${NC}"
wait_for_cert

echo -e "\n${BLUE}Step 3: Starting application${NC}"
if start_app; then
    echo -e "${GREEN}✅ Application started successfully${NC}"
else
    echo -e "${RED}❌ Failed to start application${NC}"
    exit 1
fi

if [ "$SKIP_TESTS" = false ]; then
    echo -e "\n${BLUE}Step 4: Testing system${NC}"
    test_system
else
    echo -e "\n${BLUE}Step 4: Skipping tests (--skip flag used)${NC}"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 System is ready!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Show appropriate endpoints based on command
if [[ "$APP_COMMAND" == *"example-app"* ]]; then
    echo "Available endpoints (Example App):"
    echo "  - Health: http://localhost:8080/health"
    echo "  - Users: http://localhost:8080/users (fetches from HTTPS API)"
    echo "  - Posts: http://localhost:8080/posts (fetches from HTTPS API)"
    echo "  - Aggregate: http://localhost:8080/aggregate (multiple HTTPS calls)"
else
    echo "Your app is running with command:"
    echo "  $APP_COMMAND"
    echo ""
    echo "Check your app's documentation for available endpoints."
fi

echo ""
echo "Monitor captures:"
echo "  - Watch logs: docker logs -f transparent-proxy"
echo "  - View captures: ls -la captured/*.json"
echo ""
echo -e "${YELLOW}To stop the system:${NC} docker compose -f docker-compose-transparent.yml down"

# Launch monitor or test if requested
if [ "$MONITOR_AFTER" = true ]; then
    echo -e "\n${YELLOW}Launching monitor...${NC}"
    sleep 2
    ./monitor-proxy.sh
elif [ "$TEST_AFTER" = true ]; then
    echo -e "\n${YELLOW}Running tests...${NC}"
    sleep 2
    ./test-proxy-capture.sh
fi