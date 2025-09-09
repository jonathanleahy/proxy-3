#!/bin/bash
# Universal iptables setup that works on all systems

echo "🔐 Starting mitmproxy with universal iptables rules"

# Enable IP forwarding
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
    chmod 644 /certs/mitmproxy-ca-cert.pem
    echo "✅ Certificate ready"
fi

# Clear existing rules
iptables -t nat -F OUTPUT 2>/dev/null || true

echo "🔧 Testing iptables owner matching..."

# Test if owner matching works
TEST_RULE_WORKS=false
if iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084 2>/dev/null; then
    echo "✅ Owner matching supported - using precise rules"
    TEST_RULE_WORKS=true
    
    # Remove test rule
    iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084 2>/dev/null
    
    # Add proper rules with owner matching
    # Skip localhost traffic for everyone
    iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN  # Skip Docker networks
    
    # Redirect traffic from UID 1000
    iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
    iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
    
    echo "✅ Rules installed for UID 1000 only"
else
    echo "⚠️  Owner matching not supported - using universal rules"
    
    # Use simpler rules that work everywhere
    # Skip localhost and Docker networks
    iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN
    
    # Redirect ALL other HTTP/HTTPS traffic (from any user)
    iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8084
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8084
    
    echo "⚠️  WARNING: ALL HTTP/HTTPS traffic will be intercepted (not just UID 1000)"
    echo "  This is necessary because owner matching doesn't work on this system"
fi

# Show current rules
echo ""
echo "📋 Current iptables rules:"
iptables -t nat -L OUTPUT -n | grep -E "REDIRECT|RETURN" || echo "No rules found"

# Start health check
python3 /scripts/health_check_server.py >/dev/null 2>&1 &

# Start mitmproxy
echo ""
echo "🚀 Starting mitmproxy on port 8084..."
exec mitmdump --mode transparent --listen-port 8084 \
    -s /scripts/mitm_capture_improved.py \
    --set confdir=~/.mitmproxy \
    --set connection_strategy=eager \
    --set upstream_cert=false