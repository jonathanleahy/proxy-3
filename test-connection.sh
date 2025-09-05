#!/bin/bash

echo "Testing connection to app..."

# Check if container is running
echo "1. Checking containers:"
docker ps | grep -E "(transparent-proxy|app)"

echo ""
echo "2. Testing from host:"
curl -v http://localhost:8080 2>&1 | head -20

echo ""
echo "3. Testing from inside network:"
docker exec app curl -v http://localhost:8080 2>&1 | head -20

echo ""
echo "4. Checking what's listening:"
docker exec app netstat -tlnp 2>/dev/null || docker exec app ss -tlnp 2>/dev/null || echo "No netstat/ss available"

echo ""
echo "5. App container logs:"
docker logs app --tail=20