#!/bin/bash

# Quick HTTPS Capture - Simplified version that works

echo "🔐 Quick HTTPS Capture Setup"
echo "============================"

# Clean up
docker stop mitm-proxy 2>/dev/null && docker rm mitm-proxy 2>/dev/null

# Start mitmproxy
echo "Starting MITM proxy..."
docker run -d \
  --name mitm-proxy \
  -p 8080:8080 \
  -v $(pwd)/captured:/captured \
  -v $(pwd)/scripts:/scripts \
  mitmproxy/mitmproxy \
  mitmdump -s /scripts/mitm_capture.py --set confdir=/home/mitmproxy/.mitmproxy

echo "Waiting for proxy to start..."
sleep 10

# Get certificate - try until it works
echo "Extracting certificate..."
mkdir -p certs

# Keep trying until we get the cert
for i in {1..5}; do
    echo "Attempt $i..."
    
    # Try docker cp first
    docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem 2>/dev/null
    
    # Check if it worked
    if [ -f "certs/mitmproxy-ca.pem" ] && [ -s "certs/mitmproxy-ca.pem" ]; then
        echo "✅ Certificate extracted successfully!"
        break
    fi
    
    # If not, try docker exec
    docker exec mitm-proxy cat /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem > certs/mitmproxy-ca.pem 2>/dev/null
    
    # Check again
    if [ -f "certs/mitmproxy-ca.pem" ] && [ -s "certs/mitmproxy-ca.pem" ]; then
        echo "✅ Certificate extracted successfully!"
        break
    fi
    
    sleep 3
done

# Final check
if [ ! -f "certs/mitmproxy-ca.pem" ] || [ ! -s "certs/mitmproxy-ca.pem" ]; then
    echo "❌ Failed to extract certificate after multiple attempts"
    echo "Try running: docker logs mitm-proxy"
    exit 1
fi

# Show what to do
echo ""
echo "✅ Ready! Now run these commands in your app's terminal:"
echo ""
echo "export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem"
echo "export HTTP_PROXY=http://localhost:8080"
echo "export HTTPS_PROXY=http://localhost:8080"
echo "./your-app"
echo ""
echo "View logs: docker logs -f mitm-proxy"
echo "Stop: docker stop mitm-proxy && docker rm mitm-proxy"