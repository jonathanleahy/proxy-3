#!/bin/bash
# Fixed iptables approach - avoids Docker DNS conflicts

echo "🔐 Starting mitmproxy with fixed iptables rules"

# Enable IP forwarding (ignore failures)
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || \
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || \
echo "⚠️  Cannot enable IP forwarding - continuing"

# Generate certificate first
mkdir -p ~/.mitmproxy /certs
timeout 5 mitmdump --quiet >/dev/null 2>&1 &
sleep 3
kill $! 2>/dev/null || true

if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp ~/.mitmproxy/mitmproxy-ca-cert.pem /certs/
    echo "✅ Certificate ready"
fi

# Clear any existing rules
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true

# FIXED APPROACH: Use specific rules that don't conflict with Docker DNS
echo "🔧 Setting up iptables with Docker-safe rules..."

# Create custom chain to avoid Docker's chains
iptables -t nat -N PROXY_INTERCEPT 2>/dev/null || true

# Only redirect traffic from UID 1000 (appuser) to avoid loops
# Skip Docker's DNS (127.0.0.11) and local traffic
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner 1000 \
    -d 127.0.0.0/8 -j RETURN 2>/dev/null || true
    
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner 1000 \
    --dport 443 -j REDIRECT --to-port 8084 2>/dev/null || true
    
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner 1000 \
    --dport 80 -j REDIRECT --to-port 8084 2>/dev/null || true

# Alternative: If owner match fails, try without it
if [ $? -ne 0 ]; then
    echo "⚠️  Owner-based rules failed, trying simpler rules..."
    
    # Skip localhost completely
    iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN 2>/dev/null || true
    iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN 2>/dev/null || true
    
    # Redirect only external traffic
    iptables -t nat -A OUTPUT -p tcp --dport 443 \
        ! -d 127.0.0.0/8 -j REDIRECT --to-port 8084 2>/dev/null || true
    iptables -t nat -A OUTPUT -p tcp --dport 80 \
        ! -d 127.0.0.0/8 -j REDIRECT --to-port 8084 2>/dev/null || true
fi

echo "✅ iptables rules applied (or skipped if failed)"

# Start health check
python3 /scripts/health_check_server.py >/dev/null 2>&1 &

# Start mitmproxy
echo "🚀 Starting mitmproxy..."
exec mitmdump --mode transparent --listen-port 8084 \
    -s /scripts/mitm_capture_improved.py \
    --set confdir=~/.mitmproxy \
    --set connection_strategy=eager \
    --set upstream_cert=false