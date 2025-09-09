#!/bin/bash
# Minimal entry point without iptables configuration
# This version works even when iptables is restricted

echo "🔐 Starting mitmproxy (no iptables mode)"

# Create directories
mkdir -p ~/.mitmproxy /certs /captured

# Generate certificate first
echo "🔑 Generating certificate..."
timeout 5 mitmdump --quiet >/dev/null 2>&1 &
PID=$!
sleep 3
kill $PID 2>/dev/null || true

# Copy certificate if it exists
if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/
    chmod 644 /certs/mitmproxy-ca-cert.pem
    echo "✅ Certificate ready at /certs/"
elif [ -f /root/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp /root/.mitmproxy/mitmproxy-ca-cert.pem /certs/
    chmod 644 /certs/mitmproxy-ca-cert.pem
    echo "✅ Certificate ready at /certs/"
else
    echo "⚠️  Certificate generation failed - continuing anyway"
fi

# Start health check server if available
if [ -f /scripts/health_check_server.py ]; then
    python3 /scripts/health_check_server.py >/dev/null 2>&1 &
    echo "✅ Health check server started"
fi

# Start mitmproxy in regular proxy mode (not transparent)
echo "🚀 Starting mitmproxy in regular proxy mode..."
echo "Configure your app to use proxy: http://localhost:8084"

# Use regular proxy mode instead of transparent mode
exec mitmdump \
    --listen-port 8084 \
    --set confdir=~/.mitmproxy \
    -s /scripts/mitm_capture_improved.py \
    --set block_global=false \
    --set connection_strategy=eager