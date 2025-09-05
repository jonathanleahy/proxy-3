#!/bin/bash

# Transparent HTTPS Capture - No Certificates Needed!
# This uses Docker network namespace sharing for true transparent proxy

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🔐 Transparent HTTPS Capture System${NC}"
echo -e "${GREEN}No certificates or proxy settings needed!${NC}"
echo "========================================="

# Parse arguments
ACTION=${1:-start}
APP_CMD=${2:-}

case "$ACTION" in
  start)
    echo -e "\n${YELLOW}Starting transparent capture system...${NC}"
    
    # Clean up any existing containers
    echo "Cleaning up old containers..."
    docker-compose -f docker-compose-transparent.yml down 2>/dev/null || true
    
    # Build images
    echo -e "\n${BLUE}Building Docker images...${NC}"
    docker-compose -f docker-compose-transparent.yml build
    
    # Start the system
    echo -e "\n${BLUE}Starting containers...${NC}"
    docker-compose -f docker-compose-transparent.yml up -d
    
    echo -e "\n${GREEN}✅ Transparent capture system is running!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "📊 View captures at: http://localhost:8090/viewer"
    echo "📁 Captures saved to: ./captured/"
    echo ""
    echo "To run your app in the transparent proxy environment:"
    echo -e "${YELLOW}./transparent-capture.sh run 'your-app-command'${NC}"
    echo ""
    echo "Example:"
    echo -e "${YELLOW}./transparent-capture.sh run 'curl https://api.github.com'${NC}"
    echo ""
    echo "To see logs: docker-compose -f docker-compose-transparent.yml logs -f"
    echo "To stop: ./transparent-capture.sh stop"
    ;;
    
  run)
    if [ -z "$APP_CMD" ]; then
      echo "Usage: $0 run 'your-app-command'"
      exit 1
    fi
    
    echo -e "\n${YELLOW}Running app with transparent HTTPS capture...${NC}"
    echo -e "${BLUE}Command: $APP_CMD${NC}"
    echo ""
    
    # Run the command inside the app container
    docker-compose -f docker-compose-transparent.yml exec app sh -c "$APP_CMD"
    ;;
    
  exec)
    # Interactive shell in app container
    echo -e "\n${YELLOW}Opening shell in app container...${NC}"
    echo "All HTTPS traffic will be transparently captured!"
    echo ""
    docker-compose -f docker-compose-transparent.yml exec app sh
    ;;
    
  logs)
    docker-compose -f docker-compose-transparent.yml logs -f
    ;;
    
  stop)
    echo -e "\n${YELLOW}Stopping transparent capture system...${NC}"
    docker-compose -f docker-compose-transparent.yml down
    echo -e "${GREEN}✅ Stopped${NC}"
    ;;
    
  test)
    echo -e "\n${YELLOW}Testing transparent capture...${NC}"
    
    # Run some test requests
    echo "Making test HTTPS requests (will be captured transparently)..."
    
    docker-compose -f docker-compose-transparent.yml exec app sh -c "
      echo '1. GitHub API test:'
      curl -s https://api.github.com/users/github | head -3
      echo ''
      echo '2. HTTPBin test:'
      curl -s https://httpbin.org/json | head -3
      echo ''
      echo '3. Google test:'
      curl -s -I https://www.google.com | head -3
    "
    
    echo -e "\n${GREEN}✅ Test complete! Check ./captured/ for captured requests${NC}"
    ;;
    
  *)
    echo "Usage: $0 {start|run|exec|logs|stop|test}"
    echo ""
    echo "  start         - Start the transparent capture system"
    echo "  run 'cmd'     - Run a command with transparent capture"
    echo "  exec          - Open shell in app container"
    echo "  logs          - Show container logs"
    echo "  stop          - Stop the system"
    echo "  test          - Run test HTTPS requests"
    exit 1
    ;;
esac