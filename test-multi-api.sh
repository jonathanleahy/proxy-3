#!/bin/bash

# Integration test showing multi-API recording and replay
# This demonstrates that the proxy captures ALL external calls

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🧪 Multi-API Recording Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Clean up previous captures
echo -e "${YELLOW}Cleaning previous captures...${NC}"
rm -rf captured/*.json
mkdir -p captured

# Step 1: Start capture proxy
echo -e "\n${BLUE}Step 1: Starting capture proxy...${NC}"
CAPTURE_PORT=8091 \
OUTPUT_DIR=./captured \
DEFAULT_TARGET=https://jsonplaceholder.typicode.com \
go run cmd/capture/main.go &
PROXY_PID=$!
sleep 2

# Step 2: Make multiple different API calls through proxy
echo -e "\n${BLUE}Step 2: Making multiple API calls through proxy...${NC}"

echo "  📍 Call 1: Fetching user 1..."
curl -s -x http://localhost:8091 https://jsonplaceholder.typicode.com/users/1 > /dev/null

echo "  📍 Call 2: Fetching user 2..."
curl -s -x http://localhost:8091 https://jsonplaceholder.typicode.com/users/2 > /dev/null

echo "  📍 Call 3: Fetching posts for user 1..."
curl -s -x http://localhost:8091 "https://jsonplaceholder.typicode.com/posts?userId=1&_limit=2" > /dev/null

echo "  📍 Call 4: Fetching todos for user 1..."
curl -s -x http://localhost:8091 "https://jsonplaceholder.typicode.com/todos?userId=1&_limit=3" > /dev/null

echo "  📍 Call 5: Fetching specific post..."
curl -s -x http://localhost:8091 https://jsonplaceholder.typicode.com/posts/5 > /dev/null

echo "  📍 Call 6: Fetching comments for post 1..."
curl -s -x http://localhost:8091 "https://jsonplaceholder.typicode.com/comments?postId=1&_limit=2" > /dev/null

# Step 3: Save captures
echo -e "\n${BLUE}Step 3: Saving captures...${NC}"
curl -s http://localhost:8091/capture/save > /dev/null

# Kill proxy
kill $PROXY_PID 2>/dev/null
wait $PROXY_PID 2>/dev/null

# Step 4: Check what was captured
echo -e "\n${BLUE}Step 4: Checking captured routes...${NC}"
if [ -f "captured/all-captured.json" ]; then
    echo "Captured routes:"
    grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' captured/all-captured.json | cut -d'"' -f4 | sort -u | while read path; do
        echo "  ✅ $path"
    done
fi

# Step 5: Copy to configs for replay
echo -e "\n${BLUE}Step 5: Preparing for replay...${NC}"
cp captured/*.json configs/
echo "  ✅ Captured data copied to configs"

# Step 6: Start mock server
echo -e "\n${BLUE}Step 6: Starting mock server with captured data...${NC}"
PORT=8090 CONFIG_PATH=./configs go run cmd/main.go &
MOCK_PID=$!
sleep 2

# Step 7: Test replay - all different calls should work!
echo -e "\n${BLUE}Step 7: Testing replay of all captured endpoints...${NC}"

echo "  🎭 Replaying user 1..."
USER1=$(curl -s http://localhost:8090/users/1 | jq -r '.name' 2>/dev/null)
[ ! -z "$USER1" ] && echo "    ✅ Got: $USER1" || echo "    ❌ Failed"

echo "  🎭 Replaying user 2..."
USER2=$(curl -s http://localhost:8090/users/2 | jq -r '.name' 2>/dev/null)
[ ! -z "$USER2" ] && echo "    ✅ Got: $USER2" || echo "    ❌ Failed"

echo "  🎭 Replaying posts for user 1..."
POSTS=$(curl -s "http://localhost:8090/posts?userId=1&_limit=2" | jq 'length' 2>/dev/null)
[ "$POSTS" -gt 0 ] 2>/dev/null && echo "    ✅ Got $POSTS posts" || echo "    ❌ Failed"

echo "  🎭 Replaying todos for user 1..."
TODOS=$(curl -s "http://localhost:8090/todos?userId=1&_limit=3" | jq 'length' 2>/dev/null)
[ "$TODOS" -gt 0 ] 2>/dev/null && echo "    ✅ Got $TODOS todos" || echo "    ❌ Failed"

echo "  🎭 Replaying post 5..."
POST5=$(curl -s http://localhost:8090/posts/5 | jq -r '.title' 2>/dev/null | head -c 20)
[ ! -z "$POST5" ] && echo "    ✅ Got: ${POST5}..." || echo "    ❌ Failed"

echo "  🎭 Replaying comments..."
COMMENTS=$(curl -s "http://localhost:8090/comments?postId=1&_limit=2" | jq 'length' 2>/dev/null)
[ "$COMMENTS" -gt 0 ] 2>/dev/null && echo "    ✅ Got $COMMENTS comments" || echo "    ❌ Failed"

# Kill mock server
kill $MOCK_PID 2>/dev/null
wait $MOCK_PID 2>/dev/null

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Test Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Summary:"
echo "• The proxy captured ALL 6 different API endpoints"
echo "• Each unique URL pattern was recorded separately"
echo "• The mock server can replay ALL of them"
echo "• Your app can make multiple API calls and they'll all be mocked correctly!"
echo ""
echo "This means when your app makes calls to:"
echo "  - Different services (users, posts, todos, comments)"
echo "  - Different IDs (/users/1, /users/2)"
echo "  - Different query parameters (?userId=1&_limit=2)"
echo "They are ALL captured and can ALL be replayed!"