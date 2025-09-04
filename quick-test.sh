#!/bin/bash

# Quick test script for record and replay modes
# Usage: ./quick-test.sh [record|replay|test]

MODE=${1:-menu}
PROXY_PORT=8091
MOCK_PORT=8090

case "$MODE" in
    record)
        echo "🔴 RECORD MODE - Starting capture proxy..."
        # Kill existing
        pkill -f "cmd/capture/main.go" 2>/dev/null
        
        # Start capture proxy with test API
        CAPTURE_PORT=$PROXY_PORT \
        OUTPUT_DIR=./captured \
        DEFAULT_TARGET=https://jsonplaceholder.typicode.com \
        go run cmd/capture/main.go &
        
        sleep 2
        
        # Make some test calls through proxy
        echo "📸 Making test API calls..."
        curl -s -x http://localhost:$PROXY_PORT https://jsonplaceholder.typicode.com/users/1 | jq '.name'
        curl -s -x http://localhost:$PROXY_PORT https://jsonplaceholder.typicode.com/posts/1 | jq '.title'
        curl -s -x http://localhost:$PROXY_PORT https://jsonplaceholder.typicode.com/todos/1 | jq '.'
        
        # Save captures
        echo "💾 Saving captures..."
        curl -s http://localhost:$PROXY_PORT/capture/save
        
        echo "✅ Captured $(ls -1 captured/*.json 2>/dev/null | wc -l) files"
        
        # Kill proxy
        pkill -f "cmd/capture/main.go"
        ;;
        
    replay)
        echo "🎭 REPLAY MODE - Starting mock server..."
        # Kill existing
        pkill -f "cmd/main.go" 2>/dev/null
        
        # Copy captured to configs
        cp captured/*.json configs/ 2>/dev/null
        
        # Start mock server
        PORT=$MOCK_PORT CONFIG_PATH=./configs go run cmd/main.go &
        
        sleep 2
        
        echo "📡 Testing mock endpoints..."
        echo "Users endpoint:"
        curl -s http://localhost:$MOCK_PORT/users/1 | jq '.name' 2>/dev/null || echo "Not available"
        
        echo "Posts endpoint:"  
        curl -s http://localhost:$MOCK_PORT/posts/1 | jq '.title' 2>/dev/null || echo "Not available"
        
        echo "✅ Mock server ready at http://localhost:$MOCK_PORT"
        echo "Press Ctrl+C to stop"
        
        # Wait for interrupt
        wait
        ;;
        
    test)
        echo "🧪 TEST MODE - Quick endpoint test..."
        
        # Try mock server first
        if curl -s http://localhost:$MOCK_PORT >/dev/null 2>&1; then
            echo "✅ Mock server is running"
            echo "Testing endpoint: /users/1"
            curl -s http://localhost:$MOCK_PORT/users/1 | jq '.'
        elif curl -s http://localhost:$PROXY_PORT/capture/status >/dev/null 2>&1; then
            echo "✅ Capture proxy is running"
            echo "Testing through proxy: /users/1"
            curl -s -x http://localhost:$PROXY_PORT https://jsonplaceholder.typicode.com/users/1 | jq '.'
        else
            echo "❌ No servers running. Start with:"
            echo "   ./quick-test.sh record   # To capture"
            echo "   ./quick-test.sh replay   # To mock"
        fi
        ;;
        
    menu|*)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   🎯 Quick Test Script"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Usage: ./quick-test.sh [command]"
        echo ""
        echo "Commands:"
        echo "  record  - Start proxy and capture API calls"
        echo "  replay  - Start mock server with captured data"
        echo "  test    - Test current setup"
        echo ""
        echo "Example workflow:"
        echo "  1. ./quick-test.sh record  # Capture real APIs"
        echo "  2. ./quick-test.sh replay  # Use as mocks"
        echo "  3. ./quick-test.sh test    # Test endpoints"
        ;;
esac