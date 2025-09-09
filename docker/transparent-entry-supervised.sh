#!/bin/bash
# Supervised entry point for transparent mitmproxy container
# Ensures container doesn't exit when processes die

echo "🔐 Starting supervised mitmproxy in transparent mode"

# Configuration
MAX_RESTARTS=10
RESTART_COUNT=0
PID_FILE="/tmp/mitmproxy.pid"
HEALTH_PID_FILE="/tmp/health.pid"

# Enable IP forwarding (handle read-only filesystem gracefully)
# Try multiple methods to enable IP forwarding
IP_FORWARD_ENABLED=false

# Method 1: Direct write (works with privileged mode)
if echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null; then
    IP_FORWARD_ENABLED=true
    echo "✅ IP forwarding enabled via direct write"
# Method 2: Using sysctl (works in some restricted environments)
elif sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
    IP_FORWARD_ENABLED=true
    echo "✅ IP forwarding enabled via sysctl"
# Method 3: Check if already enabled
elif [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
    IP_FORWARD_ENABLED=true
    echo "✅ IP forwarding already enabled"
else
    echo "⚠️  Cannot enable IP forwarding - continuing anyway"
    echo "   Note: This may be fine if Docker's network is handling it"
fi

# Setup iptables rules for transparent proxy
setup_iptables() {
    echo "🔧 Setting up iptables rules..."
    
    # For PREROUTING (external traffic coming in)
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8084
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8084
    
    # For OUTPUT (local traffic) - Capture traffic from appuser (UID 1000)
    iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
    iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
    
    echo "✅ iptables rules configured for transparent interception"
}

# Function to start mitmproxy and generate certificate
start_mitmproxy_for_cert() {
    echo "🔑 Starting mitmproxy to generate certificate..."
    
    # Start mitmproxy briefly to generate certificates
    timeout 5 mitmdump --mode transparent --listen-port 8086 >/dev/null 2>&1 &
    local cert_pid=$!
    
    # Wait for certificate generation (check both possible locations)
    local max_wait=10
    local waited=0
    while [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.pem ] && [ ! -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ] && [ $waited -lt $max_wait ]; do
        sleep 1
        waited=$((waited + 1))
    done
    
    # Kill the temporary mitmproxy
    kill $cert_pid 2>/dev/null || true
    wait $cert_pid 2>/dev/null || true
    
    if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ] || [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        echo "✅ Certificate generated successfully"
        return 0
    else
        echo "❌ Certificate generation failed"
        return 1
    fi
}

# Function to copy certificate with proper permissions
copy_certificate() {
    mkdir -p /certs
    
    # Check both possible certificate locations
    local cert_source=""
    if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        cert_source=~/.mitmproxy/mitmproxy-ca-cert.pem
    elif [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        cert_source=/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem
    fi
    
    if [ -n "$cert_source" ]; then
        cp "$cert_source" /certs/
        chmod 644 /certs/mitmproxy-ca-cert.pem
        chown root:root /certs/mitmproxy-ca-cert.pem
        echo "✅ Certificate copied to shared volume from $cert_source"
        return 0
    else
        echo "❌ Certificate not found in any location"
        return 1
    fi
}

# Function to start health check server
start_health_server() {
    if [ -f /scripts/health_check_server.py ]; then
        echo "🏥 Starting health check server..."
        python3 /scripts/health_check_server.py >/dev/null 2>&1 &
        echo $! > "$HEALTH_PID_FILE"
        echo "✅ Health check server started (PID: $(cat $HEALTH_PID_FILE))"
    else
        echo "⚠️  Health check server script not found"
    fi
}

# Function to start mitmproxy with monitoring
start_mitmproxy() {
    # Determine which capture script to use
    CAPTURE_SCRIPT="/scripts/mitm_capture_improved.py"
    if [ ! -f "$CAPTURE_SCRIPT" ]; then
        CAPTURE_SCRIPT="/scripts/mitm_capture.py"
    fi
    
    echo "📜 Using capture script: $CAPTURE_SCRIPT"
    echo "🚀 Starting mitmproxy (attempt $((RESTART_COUNT + 1))/$MAX_RESTARTS)..."
    
    # Start mitmproxy
    mitmdump \
        --mode transparent \
        --listen-port 8084 \
        --showhost \
        --set confdir=~/.mitmproxy \
        -s "$CAPTURE_SCRIPT" \
        --set block_global=false \
        --verbose 2>&1 &
    
    local mitm_pid=$!
    echo "$mitm_pid" > "$PID_FILE"
    echo "✅ mitmproxy started with PID $mitm_pid"
    
    # Wait for mitmproxy to exit
    wait "$mitm_pid"
    local exit_code=$?
    
    echo "⚠️  mitmproxy exited with code $exit_code"
    rm -f "$PID_FILE"
    
    return $exit_code
}

# Function to monitor and restart processes
monitor_processes() {
    while [ $RESTART_COUNT -lt $MAX_RESTARTS ]; do
        # Check health server
        if [ -f "$HEALTH_PID_FILE" ]; then
            if ! kill -0 $(cat "$HEALTH_PID_FILE") 2>/dev/null; then
                echo "🔄 Restarting health check server..."
                start_health_server
            fi
        fi
        
        # Start mitmproxy
        start_mitmproxy
        
        # Increment restart counter
        RESTART_COUNT=$((RESTART_COUNT + 1))
        
        if [ $RESTART_COUNT -lt $MAX_RESTARTS ]; then
            echo "🔄 Restarting mitmproxy in 5 seconds..."
            sleep 5
        fi
    done
    
    echo "❌ Maximum restart attempts ($MAX_RESTARTS) reached. Keeping container alive for debugging..."
}

# Signal handlers for graceful shutdown
cleanup() {
    echo "🛑 Received shutdown signal, cleaning up..."
    
    # Kill mitmproxy
    if [ -f "$PID_FILE" ]; then
        kill -TERM $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    
    # Kill health server
    if [ -f "$HEALTH_PID_FILE" ]; then
        kill -TERM $(cat "$HEALTH_PID_FILE") 2>/dev/null || true
        rm -f "$HEALTH_PID_FILE"
    fi
    
    echo "👋 Cleanup complete, exiting..."
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
echo "🚀 Starting transparent proxy supervisor..."

# Setup iptables
setup_iptables

# Generate certificate first
start_mitmproxy_for_cert

# Copy certificate
copy_certificate

# Start health check server
start_health_server

# Start monitoring loop
monitor_processes &
MONITOR_PID=$!

# Keep container running
echo "✅ Supervisor initialized. Container will stay alive even if processes crash."
echo "📊 Monitoring PID: $MONITOR_PID"

# Wait for monitor process or signals
wait $MONITOR_PID

# If we get here, keep container alive for debugging
echo "🔍 Entering debug mode - container staying alive..."
tail -f /dev/null