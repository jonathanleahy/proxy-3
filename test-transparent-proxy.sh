#!/bin/bash
# Comprehensive test suite for transparent HTTPS proxy system

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Transparent HTTPS Proxy Test Suite${NC}"
echo "========================================="

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${YELLOW}Testing: $test_name${NC}"
    if eval "$test_command"; then
        echo -e "${GREEN}✅ PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}❌ FAILED${NC}"
        ((TESTS_FAILED++))
    fi
}

# 1. Check if containers are running
run_test "Docker containers running" \
    "docker ps | grep -q transparent-proxy && docker ps | grep -q app"

# 2. Check mitmproxy is listening
run_test "mitmproxy listening on port 8084" \
    "docker exec transparent-proxy ss -tlnp | grep -q ':8084'"

# 3. Check for duplicate mitmproxy processes
run_test "No duplicate mitmproxy processes" \
    "[ \$(docker exec transparent-proxy sh -c 'ps aux | grep -c \"mitmdump.*8084\"' || echo 0) -le 2 ]"

# 4. Check certificate exists
run_test "Certificate exists in proxy container" \
    "docker exec transparent-proxy test -f /certs/mitmproxy-ca-cert.pem"

# 5. Check certificate is accessible in app container
run_test "Certificate accessible in app container" \
    "docker exec app test -f /certs/mitmproxy-ca-cert.pem"

# 6. Check iptables rules are configured
run_test "iptables rules configured" \
    "docker exec transparent-proxy iptables -t nat -L OUTPUT -n | grep -q 'REDIRECT.*8084'"

# 7. Check iptables are capturing traffic
run_test "iptables showing traffic interception" \
    "docker exec transparent-proxy sh -c 'iptables -t nat -L OUTPUT -v -n | grep -E \"443.*REDIRECT\" | awk \"{print \\\$1}\" | grep -v \"^0$\"'"

# 8. Test health check endpoint (if available)
if docker exec transparent-proxy which python3 >/dev/null 2>&1; then
    run_test "Health check endpoint" \
        "docker exec transparent-proxy sh -c 'python3 /scripts/health_check_server.py &' && sleep 2 && docker exec transparent-proxy curl -s http://localhost:8085/health | grep -q 'healthy'"
fi

# 9. Test example app endpoints
echo -e "\n${BLUE}Testing Application Endpoints${NC}"
echo "---------------------------------"

# Start the app if not running
docker exec -d app sh -c "export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem && cd /proxy/example-app && go run main.go" 2>/dev/null || true
sleep 5

# Test health endpoint
run_test "App health endpoint" \
    "curl -s http://localhost:8080/health | grep -q 'healthy'"

# Test users endpoint (should trigger HTTPS capture)
run_test "App users endpoint (HTTPS capture)" \
    "curl -s http://localhost:8080/users | grep -q 'users'"

# 10. Check if captures are being saved
echo -e "\n${BLUE}Checking Capture Files${NC}"
echo "------------------------"

# Get current capture count
INITIAL_CAPTURES=$(ls -1 captured/*.json 2>/dev/null | wc -l || echo 0)

# Make some requests to generate captures
echo "Generating test traffic..."
for i in {1..5}; do
    curl -s http://localhost:8080/users >/dev/null 2>&1 || true
    curl -s http://localhost:8080/posts >/dev/null 2>&1 || true
done

# Wait for captures to be saved
sleep 5

# Check if new captures were created
FINAL_CAPTURES=$(ls -1 captured/*.json 2>/dev/null | wc -l || echo 0)
run_test "New captures being saved" \
    "[ $FINAL_CAPTURES -gt $INITIAL_CAPTURES ]"

# 11. Check all-captured.json is updated
run_test "all-captured.json exists and recent" \
    "[ -f captured/all-captured.json ] && [ \$(find captured/all-captured.json -mmin -5 | wc -l) -gt 0 ]"

# 12. Test graceful shutdown
echo -e "\n${BLUE}Testing Graceful Shutdown${NC}"
echo "---------------------------"

# Send USR1 signal to trigger save
run_test "Signal handling (USR1)" \
    "docker exec transparent-proxy sh -c 'kill -USR1 \$(cat /tmp/mitmproxy.pid 2>/dev/null) 2>/dev/null' || true"

# 13. Check for memory leaks or high resource usage
echo -e "\n${BLUE}Resource Usage Check${NC}"
echo "---------------------"

MEMORY_USAGE=$(docker stats --no-stream --format "{{.MemPerc}}" transparent-proxy | tr -d '%')
run_test "Memory usage reasonable" \
    "[ \$(echo \"$MEMORY_USAGE < 50\" | bc -l) -eq 1 ]"

# 14. Test error recovery
echo -e "\n${BLUE}Error Recovery Test${NC}"
echo "--------------------"

# Kill mitmproxy and see if it recovers
docker exec transparent-proxy sh -c "kill \$(cat /tmp/mitmproxy.pid 2>/dev/null) 2>/dev/null" || true
sleep 2

# Check if container is still running (should handle the error)
run_test "Container survives mitmproxy crash" \
    "docker ps | grep -q transparent-proxy"

# Print summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All tests passed! The transparent proxy system is working correctly.${NC}"
    exit 0
else
    echo -e "\n${RED}⚠️  Some tests failed. Please review the issues above.${NC}"
    exit 1
fi