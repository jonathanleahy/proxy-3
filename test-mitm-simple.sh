#!/bin/bash
# test-mitm-simple.sh - Test mitmproxy without needing Python

PROXY_PORT=8080

echo "Testing mitmproxy HTTPS interception..."
echo ""

# Test 1: HTTP (should always work)
echo "1. HTTP request (no SSL):"
curl -x http://localhost:$PROXY_PORT \
     -s --max-time 10 \
     http://httpbin.org/get | head -20

echo ""
echo "---"
echo ""

# Test 2: HTTPS with cert ignore (shows content)
echo "2. HTTPS request (YOU CAN SEE THE DECRYPTED CONTENT):"
response=$(curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://httpbin.org/json)

if [ -n "$response" ]; then
    echo "✅ HTTPS CONTENT VISIBLE:"
    echo "$response"
else
    echo "❌ No response"
fi

echo ""
echo "---"
echo ""

# Test 3: GitHub API
echo "3. GitHub API HTTPS request:"
curl -x http://localhost:$PROXY_PORT \
     --insecure \
     -s --max-time 10 \
     https://api.github.com/users/github \
     | grep -E '"login"|"name"|"company"' || echo "GitHub request failed"

echo ""
echo "---"
echo ""

echo "4. Check what mitmproxy captured:"
docker logs --tail 15 mitmproxy 2>&1 | grep -E "GET|POST|200|304|https" || echo "No recent captures in logs"

echo ""
echo "---"
echo ""

# Test without proxy to compare
echo "5. Direct request (no proxy) for comparison:"
curl -s --max-time 5 https://httpbin.org/json | head -5

echo ""
echo "═══════════════════════════════════════════════"
echo "If you see JSON content above, mitmproxy is"
echo "successfully decrypting HTTPS traffic!"
echo "═══════════════════════════════════════════════"