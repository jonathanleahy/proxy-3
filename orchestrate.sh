#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROXY_PORT=8091
MOCK_PORT=8090
APP_PORT=8080  # Your Go REST app port
CAPTURED_DIR="./captured"
CONFIGS_DIR="./configs"

# Function to print colored messages
print_msg() {
    echo -e "${2}${1}${NC}"
}

# Function to cleanup on exit
cleanup() {
    print_msg "\n🧹 Cleaning up..." "$YELLOW"
    pkill -f "cmd/capture/main.go" 2>/dev/null
    pkill -f "cmd/main.go" 2>/dev/null
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset http_proxy
    unset https_proxy
    print_msg "✅ Cleanup complete" "$GREEN"
}

# Set trap for cleanup
trap cleanup EXIT

# Main menu
show_menu() {
    echo ""
    print_msg "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$BLUE"
    print_msg "   🎯 API Recording & Replay Orchestrator" "$BLUE"
    print_msg "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$BLUE"
    echo ""
    echo "1) 📸 RECORD MODE - Capture real API responses"
    echo "2) 🎭 REPLAY MODE - Use captured mocks"
    echo "3) 🧪 TEST MODE   - Quick curl tests"
    echo "4) 💾 SAVE        - Save current captures"
    echo "5) 📊 STATUS      - Check system status"
    echo "6) ❌ EXIT"
    echo ""
    echo -n "Choose mode: "
}

# Start recording mode
start_record_mode() {
    print_msg "\n📸 Starting RECORD MODE..." "$YELLOW"
    
    # Kill any existing processes
    pkill -f "cmd/capture/main.go" 2>/dev/null
    pkill -f "cmd/main.go" 2>/dev/null
    sleep 1
    
    # Start capture proxy in transparent mode
    print_msg "Starting TRANSPARENT capture proxy on port $PROXY_PORT..." "$BLUE"
    print_msg "The proxy will automatically detect and record ALL API destinations" "$BLUE"
    
    # Start capture proxy in transparent mode - it will auto-detect destinations
    CAPTURE_PORT=$PROXY_PORT \
    OUTPUT_DIR=$CAPTURED_DIR \
    TRANSPARENT_MODE=true \
    go run cmd/capture/main.go &
    
    sleep 2
    
    # Set proxy environment variables for ALL HTTP traffic
    export HTTP_PROXY="http://localhost:$PROXY_PORT"
    export HTTPS_PROXY="http://localhost:$PROXY_PORT"
    export http_proxy="http://localhost:$PROXY_PORT"
    export https_proxy="http://localhost:$PROXY_PORT"
    export ALL_PROXY="http://localhost:$PROXY_PORT"
    
    print_msg "✅ TRANSPARENT Proxy Active" "$GREEN"
    print_msg "   ALL HTTP/HTTPS traffic will be intercepted" "$GREEN"
    print_msg "   Destinations will be auto-detected and recorded" "$GREEN"
    
    # Check if user has a custom Go app to run
    echo ""
    read -p "Do you have an app to start that makes API calls? (y/n): " has_app
    if [[ $has_app == "y" ]]; then
        read -p "Enter the command to start your app [go run main.go]: " app_cmd
        app_cmd=${app_cmd:-go run main.go}
        print_msg "Starting your app with proxy: $app_cmd" "$BLUE"
        
        # Run app with proxy environment
        HTTP_PROXY="http://localhost:$PROXY_PORT" \
        HTTPS_PROXY="http://localhost:$PROXY_PORT" \
        eval "$app_cmd" &
        
        sleep 2
    fi
    
    print_msg "\n✅ TRANSPARENT RECORD MODE ACTIVE" "$GREEN"
    print_msg "The proxy will:" "$GREEN"
    echo "  • Automatically detect API destinations"
    echo "  • Record responses from ALL external APIs"
    echo "  • Group captures by detected service"
    echo "  • No configuration needed!"
    print_msg "\nYou can now:" "$YELLOW"
    echo "  • Make requests to ANY external API"
    echo "  • Use your app normally"
    echo "  • Everything will be captured automatically"
    echo ""
    echo "Example test:"
    echo "  curl -x http://localhost:$PROXY_PORT https://api.github.com/users/github"
    echo "  curl -x http://localhost:$PROXY_PORT https://jsonplaceholder.typicode.com/users"
    echo ""
    echo "Press Enter to return to menu..."
    read
}

# Start replay mode
start_replay_mode() {
    print_msg "\n🎭 Starting REPLAY MODE..." "$YELLOW"
    
    # Kill any existing processes
    pkill -f "cmd/capture/main.go" 2>/dev/null
    pkill -f "cmd/main.go" 2>/dev/null
    sleep 1
    
    # Copy captured files to configs if they exist
    if [ -d "$CAPTURED_DIR" ] && [ "$(ls -A $CAPTURED_DIR)" ]; then
        print_msg "Found captured responses, copying to configs..." "$BLUE"
        cp $CAPTURED_DIR/*.json $CONFIGS_DIR/ 2>/dev/null
        print_msg "✅ Captured responses loaded" "$GREEN"
    fi
    
    # Start mock server
    print_msg "Starting mock server on port $MOCK_PORT..." "$BLUE"
    PORT=$MOCK_PORT CONFIG_PATH=$CONFIGS_DIR go run cmd/main.go &
    sleep 2
    
    # Clear proxy settings (we want direct calls to mock)
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset http_proxy
    unset https_proxy
    
    print_msg "\n✅ REPLAY MODE ACTIVE" "$GREEN"
    print_msg "Mock server running at http://localhost:$MOCK_PORT" "$GREEN"
    print_msg "\nAvailable endpoints:" "$YELLOW"
    
    # Show available routes
    for file in $CONFIGS_DIR/*.json; do
        if [ -f "$file" ]; then
            echo "  • $(basename $file)"
            grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | cut -d'"' -f4 | head -5 | while read path; do
                echo "    - $path"
            done
        fi
    done
    
    echo ""
    echo "Press Enter to return to menu..."
    read
}

# Test mode with curl examples
test_mode() {
    print_msg "\n🧪 TEST MODE" "$YELLOW"
    echo ""
    echo "Select test type:"
    echo "1) Test through RECORD mode (captures traffic)"
    echo "2) Test REPLAY mode (uses mocks)"
    echo "3) Custom curl command"
    echo -n "Choice: "
    read test_choice
    
    case $test_choice in
        1)
            if [ ! -z "$HTTP_PROXY" ]; then
                print_msg "\n📸 Testing in RECORD mode..." "$BLUE"
                echo "Example: Fetching users through proxy"
                curl -x http://localhost:$PROXY_PORT http://jsonplaceholder.typicode.com/users/1 | jq '.' 2>/dev/null || curl -x http://localhost:$PROXY_PORT http://jsonplaceholder.typicode.com/users/1
            else
                print_msg "❌ Record mode not active. Start it first!" "$RED"
            fi
            ;;
        2)
            print_msg "\n🎭 Testing REPLAY mode..." "$BLUE"
            echo "Example: Fetching from mock server"
            curl http://localhost:$MOCK_PORT/users/1 | jq '.' 2>/dev/null || curl http://localhost:$MOCK_PORT/users/1
            ;;
        3)
            echo "Enter your curl command:"
            read curl_cmd
            print_msg "\nExecuting: $curl_cmd" "$BLUE"
            eval "$curl_cmd"
            ;;
    esac
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Save captured data
save_captures() {
    print_msg "\n💾 Saving captures..." "$YELLOW"
    
    response=$(curl -s http://localhost:$PROXY_PORT/capture/save 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        print_msg "✅ $response" "$GREEN"
        
        if [ -d "$CAPTURED_DIR" ] && [ "$(ls -A $CAPTURED_DIR)" ]; then
            print_msg "\nCaptured files:" "$BLUE"
            ls -la $CAPTURED_DIR/*.json 2>/dev/null
        fi
    else
        print_msg "❌ No capture proxy running or no captures to save" "$RED"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Check status
check_status() {
    print_msg "\n📊 System Status" "$YELLOW"
    echo ""
    
    # Check capture proxy
    if curl -s http://localhost:$PROXY_PORT/capture/status >/dev/null 2>&1; then
        print_msg "✅ Capture Proxy: RUNNING on port $PROXY_PORT" "$GREEN"
        status=$(curl -s http://localhost:$PROXY_PORT/capture/status)
        echo "   $status"
    else
        print_msg "❌ Capture Proxy: NOT RUNNING" "$RED"
    fi
    
    # Check mock server
    if curl -s http://localhost:$MOCK_PORT >/dev/null 2>&1; then
        print_msg "✅ Mock Server: RUNNING on port $MOCK_PORT" "$GREEN"
    else
        print_msg "❌ Mock Server: NOT RUNNING" "$RED"
    fi
    
    # Check proxy settings
    if [ ! -z "$HTTP_PROXY" ]; then
        print_msg "✅ Proxy Variables: SET" "$GREEN"
        echo "   HTTP_PROXY=$HTTP_PROXY"
    else
        print_msg "⚠️  Proxy Variables: NOT SET" "$YELLOW"
    fi
    
    # Check for captured files
    if [ -d "$CAPTURED_DIR" ] && [ "$(ls -A $CAPTURED_DIR 2>/dev/null)" ]; then
        count=$(ls -1 $CAPTURED_DIR/*.json 2>/dev/null | wc -l)
        print_msg "📁 Captured Files: $count files" "$BLUE"
    else
        print_msg "📁 Captured Files: None" "$YELLOW"
    fi
    
    echo ""
    echo "Press Enter to continue..."
    read
}

# Main loop
main() {
    clear
    print_msg "🚀 API Recording & Replay Orchestrator" "$GREEN"
    print_msg "========================================" "$GREEN"
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) start_record_mode ;;
            2) start_replay_mode ;;
            3) test_mode ;;
            4) save_captures ;;
            5) check_status ;;
            6) 
                print_msg "\n👋 Goodbye!" "$GREEN"
                exit 0
                ;;
            *)
                print_msg "Invalid option!" "$RED"
                sleep 1
                ;;
        esac
    done
}

# Run main function
main