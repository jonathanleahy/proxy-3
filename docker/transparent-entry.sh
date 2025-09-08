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

# For OUTPUT (local traffic) - Capture traffic from appuser (UID 1000)
# This will capture the app's traffic but not mitmproxy's (runs as root)
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084

echo "✅ iptables rules configured for transparent interception"
echo "📊 HTTP (80) and HTTPS (443) traffic will be intercepted"
echo "🔄 Mitmproxy's own traffic is excluded from interception"

# Copy CA certificate to shared location for app container
mkdir -p /certs
cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/ 2>/dev/null || true

# Wait a moment for certificate generation
sleep 2

# Copy certificate again in case it was just generated
if [ -f /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/ 2>/dev/null || true
    echo "📋 Certificate copied to shared volume"
fi

echo "🚀 Starting mitmproxy in transparent mode..."

# Check if script exists
if [ ! -f /scripts/mitm_capture.py ]; then
    echo "❌ ERROR: /scripts/mitm_capture.py not found!"
    exit 1
fi

echo "📝 Running command: mitmdump --mode transparent --listen-port 8084 --showhost --set confdir=/home/mitmproxy/.mitmproxy -s /scripts/mitm_capture.py --set block_global=false --verbose"

# Start mitmproxy in transparent mode with our capture script on port 8084
# Run without exec to see errors
mitmdump \
    --mode transparent \
    --listen-port 8084 \
    --showhost \
    --set confdir=/home/mitmproxy/.mitmproxy \
    -s /scripts/mitm_capture.py \
    --set block_global=false \
    --verbose 2>&1 || echo "❌ ERROR: mitmdump exited with code $?"