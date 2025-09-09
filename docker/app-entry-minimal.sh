#!/bin/sh
# Minimal entry point that works without su-exec or special packages

# Wait for certificate if it exists
if [ -d /certs ]; then
    count=0
    while [ ! -f /certs/mitmproxy-ca-cert.pem ] && [ $count -lt 30 ]; do
        [ $count -eq 0 ] && echo "⏳ Waiting for certificate..."
        sleep 1
        count=$((count + 1))
    done
    
    if [ -f /certs/mitmproxy-ca-cert.pem ]; then
        echo "📜 Found certificate"
        export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
        export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
        export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    fi
fi

# Check if running as root and warn
if [ "$(id -u)" = "0" ] && echo "$1" | grep -qE "^(go|python|node|./|/app/|/proxy/)"; then
    echo "⚠️  WARNING: Running as root - traffic won't be intercepted!"
    echo "Use: docker exec -u appuser app sh -c \"$*\""
fi

# Execute the command
exec "$@"