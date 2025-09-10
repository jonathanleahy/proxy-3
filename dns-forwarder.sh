#!/bin/sh
# Simple DNS forwarding using socat or iptables

# Install dnsmasq if available
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache dnsmasq 2>/dev/null || true
fi

# Configure dnsmasq as a forwarding DNS server
if command -v dnsmasq >/dev/null 2>&1; then
    echo "Starting dnsmasq DNS forwarder..."
    cat > /tmp/dnsmasq.conf << 'DNSCONF'
# Forward all DNS queries to Google DNS
server=8.8.8.8
server=8.8.4.4
# Also try Cloudflare
server=1.1.1.1
# Listen on Docker's DNS port
listen-address=127.0.0.11
port=53
# Don't read /etc/resolv.conf
no-resolv
# Log queries for debugging
log-queries
log-facility=/var/log/dnsmasq.log
DNSCONF
    
    # Start dnsmasq
    dnsmasq -C /tmp/dnsmasq.conf -k &
    echo "DNS forwarder started on 127.0.0.11:53"
else
    echo "Using iptables for DNS forwarding..."
    # Forward DNS traffic to external DNS
    iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 8.8.8.8:53
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination 8.8.8.8:53
fi
