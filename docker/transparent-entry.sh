#!/bin/bash
# Entry point for transparent mitmproxy container

echo "🔐 Starting mitmproxy in transparent mode (no certificates needed!)"

# Check if mitmproxy is already running
PID_FILE="/tmp/mitmproxy.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  mitmproxy already running with PID $OLD_PID"
        exit 0
    else
        echo "🔄 Removing stale PID file"
        rm -f "$PID_FILE"
    fi
fi

# Enable IP forwarding (handle read-only filesystem gracefully)
if [ -w /proc/sys/net/ipv4/ip_forward ]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "✅ IP forwarding enabled"
else
    echo "⚠️  Cannot enable IP forwarding (read-only filesystem) - continuing anyway"
fi

# Get mitmproxy user UID (typically 1000 in mitmproxy image)
MITMPROXY_UID=$(id -u mitmproxy 2>/dev/null || echo "1000")

# Setup iptables rules for transparent proxy
# IMPORTANT: Exclude mitmproxy's own traffic to prevent redirect loops

# For PREROUTING (external traffic coming in)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8084
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8084

# For OUTPUT (local traffic) - Capture traffic from appuser (UID 1000)
# This will capture the app's traffic but not mitmproxy's (runs as root)
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084

echo "✅ iptables rules configured for transparent interception"
echo "📊 HTTP (80) and HTTPS (443) traffic will be intercepted"
echo "🔄 Mitmproxy's own traffic is excluded from interception"

# Ensure certificate directory exists
mkdir -p /certs

# Function to copy certificate with retries
copy_certificate() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
            cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/ && \
            chmod 644 /certs/mitmproxy-ca-cert.pem && \
            echo "✅ Certificate copied to shared volume (attempt $attempt)" && \
            return 0
        else
            echo "⏳ Waiting for certificate generation (attempt $attempt/$max_attempts)..."
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    echo "❌ ERROR: Failed to copy certificate after $max_attempts attempts"
    return 1
}

# Try to copy certificate
copy_certificate || echo "⚠️  WARNING: Continuing without certificate"

echo "🚀 Starting mitmproxy in transparent mode..."

# Use improved capture script if available, otherwise fallback to original
CAPTURE_SCRIPT="/scripts/mitm_capture_improved.py"
if [ ! -f "$CAPTURE_SCRIPT" ]; then
    CAPTURE_SCRIPT="/scripts/mitm_capture.py"
    if [ ! -f "$CAPTURE_SCRIPT" ]; then
        echo "❌ ERROR: No capture script found!"
        exit 1
    fi
fi
echo "📜 Using capture script: $CAPTURE_SCRIPT"

echo "📝 Starting mitmdump with PID tracking..."

# Function to handle signals and cleanup
cleanup() {
    echo "🛑 Received shutdown signal, cleaning up..."
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        kill -TERM "$PID" 2>/dev/null || true
        sleep 2
        kill -KILL "$PID" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start mitmproxy in background and save PID
mitmdump \
    --mode transparent \
    --listen-port 8084 \
    --showhost \
    --set confdir=/home/mitmproxy/.mitmproxy \
    -s "$CAPTURE_SCRIPT" \
    --set block_global=false \
    --verbose 2>&1 &

MITM_PID=$!
echo "$MITM_PID" > "$PID_FILE"
echo "✅ mitmproxy started with PID $MITM_PID"

# Wait for mitmproxy process
wait "$MITM_PID"
EXIT_CODE=$?

# Cleanup PID file
rm -f "$PID_FILE"

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: mitmdump exited with code $EXIT_CODE"
    exit $EXIT_CODE
fi