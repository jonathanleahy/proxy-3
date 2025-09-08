#!/bin/bash
# Entry point for transparent mitmproxy container

echo "🔐 Starting mitmproxy in transparent mode (no certificates needed!)"

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# Get mitmproxy user UID (typically 1000 in mitmproxy image)
MITMPROXY_UID=$(id -u mitmproxy 2>/dev/null || echo "1000")

# Setup iptables rules for transparent proxy
# IMPORTANT: Exclude mitmproxy's own traffic to prevent redirect loops

# For PREROUTING (external traffic coming in)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8084
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8084

# For OUTPUT (local traffic) - EXCLUDE mitmproxy's own traffic
# Skip redirection for root user (who runs mitmproxy)
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner ! --uid-owner 0 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner ! --uid-owner 0 -j REDIRECT --to-port 8084

# Alternative: Mark mitmproxy's packets to bypass interception
iptables -t mangle -A OUTPUT -p tcp -m owner --uid-owner 0 -j MARK --set-mark 1
iptables -t nat -A OUTPUT -p tcp --dport 443 -m mark ! --mark 1 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 80 -m mark ! --mark 1 -j REDIRECT --to-port 8084

echo "✅ iptables rules configured for transparent interception"
echo "📊 HTTP (80) and HTTPS (443) traffic will be intercepted"
echo "🔄 Mitmproxy's own traffic is excluded from interception"

# Copy CA certificate to shared location for app container
mkdir -p /certs
cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/ 2>/dev/null || true

# Start mitmproxy in transparent mode with our capture script on port 8084
exec mitmdump \
    --mode transparent \
    --listen-port 8084 \
    --showhost \
    --set confdir=/home/mitmproxy/.mitmproxy \
    -s /scripts/mitm_capture.py \
    --set block_global=false