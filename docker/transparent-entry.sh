#!/bin/bash
# Entry point for transparent mitmproxy container

echo "🔐 Starting mitmproxy in transparent mode (no certificates needed!)"

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Setup iptables rules for transparent proxy
# Redirect all HTTP traffic to mitmproxy port 8080
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
# Redirect all HTTPS traffic to mitmproxy port 8080
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8080

# Also handle traffic from local processes (in case app is in same container)
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080

echo "✅ iptables rules configured for transparent interception"
echo "📊 HTTP (80) and HTTPS (443) traffic will be intercepted"

# Start mitmproxy in transparent mode with our capture script
exec mitmdump \
    --mode transparent \
    --showhost \
    --set confdir=/home/mitmproxy/.mitmproxy \
    -s /scripts/mitm_capture.py \
    --set block_global=false