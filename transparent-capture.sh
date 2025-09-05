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
    
    # Clean up any existing containers and networks
    echo "Cleaning up old containers and networks..."
    docker compose -f docker-compose-transparent.yml down 2>/dev/null || true
    # Also remove any orphaned networks
    docker network rm proxy-3_capture-net 2>/dev/null || true
    # Kill any process using port 8090
    echo "Freeing up port 8090..."
    lsof -ti:8090 | xargs kill -9 2>/dev/null || true
    sleep 1
    
    # Build images
    echo -e "\n${BLUE}Building Docker images...${NC}"
    docker compose -f docker-compose-transparent.yml build
    
    # Start the system
    echo -e "\n${BLUE}Starting containers...${NC}"
    docker compose -f docker-compose-transparent.yml up -d
    
    echo -e "\n${GREEN}✅ Transparent capture system is running!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "📊 View captures at: http://localhost:${VIEWER_PORT:-8090}/viewer"
    echo "📁 Captures saved to: ./captured/"
    echo ""
    echo "To run your app in the transparent proxy environment:"
    echo -e "${YELLOW}./transparent-capture.sh run 'your-app-command'${NC}"
    echo ""
    echo "Example:"
    echo -e "${YELLOW}./transparent-capture.sh run 'curl https://api.github.com'${NC}"
    echo ""
    echo "To see logs: docker compose -f docker-compose-transparent.yml logs -f"
    echo "To stop: ./transparent-capture.sh stop"
    ;;
    
  run)
    if [ -z "$APP_CMD" ]; then
      echo "Usage: $0 run 'your-app-command'"
      exit 1
    fi
    
    echo -e "\n${YELLOW}Running app with transparent HTTPS capture...${NC}"
    echo -e "${BLUE}Command: $APP_CMD${NC}"
    echo -e "${GREEN}Output will appear below (Ctrl+C to stop):${NC}"
    echo "========================================="
    echo ""
    
    # Run the command inside the app container - stays attached
    # This is perfect for servers where you want to see live output
    docker compose -f docker-compose-transparent.yml exec app sh -c "$APP_CMD"
    ;;
    
  server)
    if [ -z "$APP_CMD" ]; then
      # Default to running ./main if no command specified
      APP_CMD="cd /proxy && ./main"
    fi
    
    echo -e "\n${YELLOW}Starting server with transparent HTTPS capture...${NC}"
    echo -e "${BLUE}Command: $APP_CMD${NC}"
    echo ""
    
    # Kill any existing instance first
    docker compose -f docker-compose-transparent.yml exec app pkill main 2>/dev/null || true
    sleep 1
    
    # Run the server in detached mode with log capture
    LOG_FILE="/proxy/app.log"
    docker compose -f docker-compose-transparent.yml exec -d app sh -c "$APP_CMD > $LOG_FILE 2>&1"
    
    echo -e "${GREEN}✅ Server started in background${NC}"
    echo -e "${BLUE}📄 Logs are being written to: $LOG_FILE${NC}"
    echo ""
    echo "Testing server connection..."
    
    # Try up to 5 times with 2 second delays
    for i in {1..5}; do
      sleep 2
      if curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8080/api/health 2>/dev/null | grep -q "200"; then
        SERVER_UP=true
        break
      fi
      echo "  Waiting for server to start... ($i/5)"
    done
    
    # Test if server is responding
    if [ "$SERVER_UP" = "true" ]; then
      echo -e "${GREEN}✅ Server is responding on port 8080${NC}"
      echo ""
      echo "Endpoints available:"
      echo "  • http://localhost:8080/"
      echo "  • http://localhost:8080/api/health"
      echo "  • http://localhost:8080/api/test"
      echo ""
      echo "To view logs:"
      echo "  $0 app-logs          # Show recent logs"
      echo "  $0 app-logs -f       # Follow logs (live)"
    else
      echo -e "${YELLOW}⚠️  Server may still be starting up...${NC}"
      echo "To view logs: $0 app-logs"
    fi
    ;;
    
  exec)
    # Interactive shell in app container
    echo -e "\n${YELLOW}Opening shell in app container...${NC}"
    echo "All HTTPS traffic will be transparently captured!"
    echo ""
    docker compose -f docker-compose-transparent.yml exec app sh
    ;;
    
  logs)
    docker compose -f docker-compose-transparent.yml logs -f
    ;;
    
  app-logs)
    # View application logs
    LOG_FILE="/proxy/app.log"
    FOLLOW_FLAG=${2:-}
    
    if [ "$FOLLOW_FLAG" == "-f" ]; then
      echo -e "${YELLOW}Following application logs (Ctrl+C to stop)...${NC}"
      docker compose -f docker-compose-transparent.yml exec app tail -f $LOG_FILE
    else
      echo -e "${YELLOW}Recent application logs:${NC}"
      docker compose -f docker-compose-transparent.yml exec app sh -c "if [ -f $LOG_FILE ]; then tail -n 50 $LOG_FILE; else echo 'No logs found. Start the server with: $0 server'; fi"
    fi
    ;;
    
  stop)
    echo -e "\n${YELLOW}Stopping transparent capture system...${NC}"
    docker compose -f docker-compose-transparent.yml down
    echo -e "${GREEN}✅ Stopped${NC}"
    ;;
    
  test)
    echo -e "\n${YELLOW}Testing transparent capture...${NC}"
    
    # Run some test requests
    echo "Making test HTTPS requests (will be captured transparently)..."
    
    docker compose -f docker-compose-transparent.yml exec app sh -c "
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
    echo "Usage: $0 {start|server|run|exec|logs|app-logs|stop|test}"
    echo ""
    echo "  start         - Start the transparent capture system"
    echo "  server [cmd]  - Start server (default: ./main) in background"
    echo "  run 'cmd'     - Run a command with transparent capture"
    echo "  exec          - Open shell in app container"
    echo "  logs          - Show all container logs"
    echo "  app-logs [-f] - Show application logs (add -f to follow)"
    echo "  stop          - Stop the system"
    echo "  test          - Run test HTTPS requests"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start the system"
    echo "  $0 server                   # Start ./main server"
    echo "  $0 app-logs                 # View app logs"
    echo "  $0 app-logs -f              # Follow app logs (live)"
    echo "  $0 run 'curl https://api.github.com'  # Run one-off command"
    exit 1
    ;;
esac