#!/bin/bash
# GO-WARMUP-COMMON.sh - Pre-download common Go libraries for any project

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔥 Go Common Libraries Pre-loader${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
echo "Pre-downloading commonly used Go libraries..."
echo ""

# Create volumes
docker volume create go-dev-cache 2>/dev/null
docker volume create go-dev-modules 2>/dev/null

# Ensure base image exists
if ! docker images | grep -q go-dev-alpine; then
    echo "Creating base image..."
    cat > Dockerfile.go-temp << 'EOF'
FROM golang:alpine
RUN apk add --no-cache ca-certificates git
WORKDIR /tmp/warmup
EOF
    docker build -t go-dev-alpine -f Dockerfile.go-temp .
    rm Dockerfile.go-temp
fi

# Create a temporary go.mod with common dependencies
cat > go.mod.common << 'EOF'
module warmup

go 1.21

require (
    // Web frameworks
    github.com/gin-gonic/gin v1.9.1
    github.com/labstack/echo/v4 v4.11.4
    github.com/gorilla/mux v1.8.1
    github.com/gofiber/fiber/v2 v2.52.0
    
    // Database
    gorm.io/gorm v1.25.5
    gorm.io/driver/postgres v1.5.4
    gorm.io/driver/mysql v1.5.2
    gorm.io/driver/sqlite v1.5.4
    github.com/jmoiron/sqlx v1.3.5
    
    // Redis
    github.com/redis/go-redis/v9 v9.4.0
    
    // MongoDB
    go.mongodb.org/mongo-driver v1.13.1
    
    // Testing
    github.com/stretchr/testify v1.8.4
    github.com/golang/mock v1.6.0
    
    // Utilities
    github.com/spf13/viper v1.18.2
    github.com/spf13/cobra v1.8.0
    github.com/joho/godotenv v1.5.1
    
    // Validation
    github.com/go-playground/validator/v10 v10.16.0
    
    // JWT
    github.com/golang-jwt/jwt/v5 v5.2.0
    
    // HTTP Client
    github.com/go-resty/resty/v2 v2.11.0
    
    // Logging
    go.uber.org/zap v1.26.0
    github.com/sirupsen/logrus v1.9.3
    
    // AWS SDK
    github.com/aws/aws-sdk-go-v2 v1.24.1
    github.com/aws/aws-sdk-go-v2/config v1.26.6
    github.com/aws/aws-sdk-go-v2/service/s3 v1.47.8
    
    // gRPC
    google.golang.org/grpc v1.60.1
    google.golang.org/protobuf v1.32.0
    
    // GraphQL
    github.com/99designs/gqlgen v0.17.43
    
    // WebSocket
    github.com/gorilla/websocket v1.5.1
    
    // UUID
    github.com/google/uuid v1.5.0
    
    // Time
    github.com/jinzhu/now v1.1.5
)
EOF

echo -e "${YELLOW}Downloading common Go libraries...${NC}"
echo "This may take a few minutes on first run..."
echo ""

# Run container to download all common dependencies
docker run --rm \
    -v "$(pwd)/go.mod.common:/tmp/warmup/go.mod" \
    -v go-dev-cache:/go/.cache \
    -v go-dev-modules:/go/pkg/mod \
    go-dev-alpine \
    sh -c "
        cd /tmp/warmup
        echo 'Creating go.sum...'
        go mod tidy 2>/dev/null || true
        echo ''
        echo 'Downloading all dependencies...'
        go mod download -x 2>&1 | grep -E 'go: downloading|get' | head -20
        echo '...'
        go mod download
        echo ''
        echo '✅ Common libraries downloaded!'
        echo ''
        echo 'Cached packages:'
        ls /go/pkg/mod/github.com/ 2>/dev/null | head -10
        echo ''
        echo 'Cache size:'
        du -sh /go/pkg/mod/ 2>/dev/null
    "

# Clean up
rm -f go.mod.common

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🔥 Common Libraries Pre-loaded!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Pre-loaded libraries include:"
echo "  • Web frameworks (Gin, Echo, Fiber, Gorilla)"
echo "  • Databases (GORM, PostgreSQL, MySQL, MongoDB)"
echo "  • Testing (Testify, Mock)"
echo "  • AWS SDK, gRPC, GraphQL"
echo "  • Common utilities (Viper, Cobra, JWT, UUID)"
echo ""
echo "These libraries are now cached in Docker volumes and will"
echo "load instantly when needed by your projects!"
echo ""
echo "Cache volumes:"
echo "  • go-dev-cache"
echo "  • go-dev-modules"
echo ""
echo "Next: Run your project and dependencies will load from cache!"