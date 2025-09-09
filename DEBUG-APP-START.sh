#!/bin/bash
# DEBUG-APP-START.sh - Debug why the app won't start

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DEBUGGING APP START FAILURE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if app container exists
echo -e "${YELLOW}1. Checking app container status:${NC}"
if docker ps -a | grep -q " app "; then
    echo "Container exists. Status:"
    docker ps -a --filter "name=app" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo -e "${YELLOW}2. Container logs:${NC}"
    docker logs app 2>&1
    
    echo ""
    echo -e "${YELLOW}3. Container details:${NC}"
    docker inspect app | grep -A5 "Error"
else
    echo "No app container found"
fi

echo ""
echo -e "${YELLOW}4. Checking if binary exists:${NC}"
if [ -f test-app/server ]; then
    echo -e "${GREEN}✅ Binary exists${NC}"
    ls -lh test-app/server
    
    echo ""
    echo -e "${YELLOW}5. Testing binary locally:${NC}"
    file test-app/server
    
    echo ""
    echo -e "${YELLOW}6. Trying to run binary in a test container:${NC}"
    docker run --rm -v $(pwd)/test-app:/app alpine /app/server 2>&1 | head -10 || {
        echo -e "${RED}Binary won't run in Alpine${NC}"
        
        echo ""
        echo -e "${YELLOW}7. Testing with Ubuntu:${NC}"
        docker run --rm -v $(pwd)/test-app:/app ubuntu:latest /app/server 2>&1 | head -10 || {
            echo -e "${RED}Binary won't run in Ubuntu either${NC}"
            
            echo ""
            echo -e "${YELLOW}8. Checking binary architecture:${NC}"
            docker run --rm -v $(pwd)/test-app:/app alpine sh -c "apk add --no-cache file && file /app/server"
        }
    }
else
    echo -e "${RED}❌ Binary doesn't exist${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ATTEMPTING FIX${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Clean up
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true

# Create a simpler test server that definitely works
echo -e "${YELLOW}Creating minimal test server...${NC}"
mkdir -p simple-test

# Create a shell script server (no compilation needed)
cat > simple-test/server.sh << 'EOF'
#!/bin/sh
echo "Starting simple server on port 8080..."

# Create a simple response handler
while true; do
    # Read the request
    read -r line
    while [ "$line" != "" ]; do
        read -r line
    done
    
    # Send response
    echo "HTTP/1.1 200 OK"
    echo "Content-Type: text/plain"
    echo ""
    echo "Simple server is working!"
    echo "Time: $(date)"
    echo ""
    echo "This is a shell script server - no Go needed"
done | nc -l -p 8080
EOF

chmod +x simple-test/server.sh

echo -e "${YELLOW}Starting simple shell server...${NC}"
docker run -d \
    --name app-simple \
    -p 8080:8080 \
    -v $(pwd)/simple-test:/app:ro \
    busybox \
    sh /app/server.sh

sleep 3

if docker ps | grep -q app-simple; then
    echo -e "${GREEN}✅ Simple server started!${NC}"
    
    if curl -s http://localhost:8080 | grep -q "working"; then
        echo -e "${GREEN}✅ Server is accessible on port 8080${NC}"
    else
        echo -e "${YELLOW}Server running but not responding as expected${NC}"
    fi
else
    echo -e "${RED}Even simple server failed${NC}"
    docker logs app-simple
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ALTERNATIVE: GO SERVER WITH BETTER COMPATIBILITY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Try building with CGO disabled for better compatibility
echo -e "${YELLOW}Building Go server with CGO_ENABLED=0 for better compatibility...${NC}"

docker run --rm \
    -v $(pwd)/test-app:/app \
    -w /app \
    -e CGO_ENABLED=0 \
    -e GOOS=linux \
    -e GOARCH=amd64 \
    golang:alpine \
    go build -a -installsuffix cgo -o server-static main.go

if [ -f test-app/server-static ]; then
    echo -e "${GREEN}✅ Static binary built${NC}"
    
    docker stop app-static 2>/dev/null || true
    docker rm app-static 2>/dev/null || true
    
    docker run -d \
        --name app-static \
        -p 8081:8080 \
        -v $(pwd)/test-app:/app:ro \
        -e PORT=8080 \
        scratch \
        /app/server-static 2>/dev/null || {
            echo "Scratch failed, trying Alpine..."
            docker rm app-static 2>/dev/null
            
            docker run -d \
                --name app-static \
                -p 8081:8080 \
                -v $(pwd)/test-app:/app:ro \
                -e PORT=8080 \
                alpine:latest \
                /app/server-static
        }
    
    sleep 3
    
    if docker ps | grep -q app-static; then
        echo -e "${GREEN}✅ Static Go server running on port 8081${NC}"
        curl -s http://localhost:8081 | head -3
    else
        echo -e "${RED}Static server failed too${NC}"
        docker logs app-static 2>&1 | tail -10
    fi
fi