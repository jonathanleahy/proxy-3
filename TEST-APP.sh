#!/bin/bash
# TEST-APP.sh - Test if the app is actually working

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TESTING APP STATUS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check what containers are running
echo -e "${YELLOW}Running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Check if app container is running
if docker ps | grep -q " app "; then
    echo -e "${GREEN}✅ App container is running${NC}"
    
    # The log shows "Starting minimal server on :8080" which is CORRECT
    # The app runs on 8080 INSIDE the container
    # Docker maps it to 9080 on the HOST
    
    echo ""
    echo -e "${YELLOW}Testing port 9080 (host port)...${NC}"
    if curl -s http://localhost:9080 2>/dev/null | grep -q "working"; then
        echo -e "${GREEN}✅ SUCCESS! App is responding on port 9080${NC}"
        echo "Response:"
        curl -s http://localhost:9080
    else
        echo -e "${YELLOW}Trying port 8080...${NC}"
        if curl -s http://localhost:8080 2>/dev/null | grep -q "working"; then
            echo -e "${GREEN}✅ App is on port 8080${NC}"
            curl -s http://localhost:8080
        else
            echo -e "${YELLOW}App might still be starting, waiting...${NC}"
            sleep 5
            
            # Try again
            echo "Trying port 9080 again..."
            response=$(curl -s http://localhost:9080 2>&1)
            if [ -n "$response" ]; then
                echo -e "${GREEN}✅ Got response:${NC}"
                echo "$response"
            else
                echo -e "${RED}No response${NC}"
                
                # Check from inside the container
                echo ""
                echo -e "${YELLOW}Testing from inside the container...${NC}"
                docker exec app curl -s http://localhost:8080 2>&1 || docker exec app wget -O- http://localhost:8080 2>&1
            fi
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}App logs (last 10 lines):${NC}"
    docker logs --tail 10 app
else
    echo -e "${RED}❌ App container is not running${NC}"
    
    # Check if it exited
    if docker ps -a | grep -q " app "; then
        echo "Container exited. Logs:"
        docker logs app 2>&1 | tail -20
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PORT MAPPING EXPLANATION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "The app runs on port 8080 INSIDE the container"
echo "Docker maps it to port 9080 on your HOST"
echo ""
echo "So when you see 'Starting server on :8080' in logs, that's correct!"
echo "You access it via http://localhost:9080 from your machine"
echo ""
echo -e "${GREEN}The mapping: localhost:9080 -> container:8080${NC}"