#!/bin/bash

# Test script for example REST API
# Run this after starting the example server

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Server URL
SERVER_URL="${SERVER_URL:-http://localhost:8080}"

echo -e "${GREEN}🧪 Testing Example REST API${NC}"
echo -e "${GREEN}Server: $SERVER_URL${NC}"
echo "========================================="

# Function to test endpoint
test_endpoint() {
    local endpoint=$1
    local description=$2
    
    echo -e "\n${YELLOW}Testing: $endpoint${NC}"
    echo -e "${BLUE}$description${NC}"
    echo "---"
    
    # Make the request and show first few lines
    response=$(curl -s "$SERVER_URL$endpoint" 2>/dev/null || echo '{"error": "Connection failed"}')
    
    # Pretty print if jq is available, otherwise just echo
    if command -v jq &> /dev/null; then
        echo "$response" | jq . | head -20
    else
        echo "$response" | head -10
    fi
    
    echo "..."
}

# Test all endpoints
test_endpoint "/health" "Health check - internal endpoint"
test_endpoint "/users" "Fetch users from external API (JSONPlaceholder)"
test_endpoint "/posts" "Fetch posts from external API (JSONPlaceholder)"
test_endpoint "/aggregate" "Aggregate data from multiple external sources"

echo -e "\n${GREEN}✅ All endpoints tested!${NC}"
echo ""
echo "📊 Check captured traffic at: http://localhost:8090/viewer"
echo "📁 Captured files saved to: ../captured/"

# Quick test with curl one-liner
echo -e "\n${YELLOW}Quick test commands:${NC}"
echo "  curl $SERVER_URL/health"
echo "  curl $SERVER_URL/users | jq ."
echo "  curl $SERVER_URL/posts | jq ."
echo "  curl $SERVER_URL/aggregate | jq ."