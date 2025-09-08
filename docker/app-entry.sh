#!/bin/sh
# Entry point for app container to use mitmproxy certificate

# Wait for certificate to be available (max 30 seconds)
count=0
while [ ! -f /certs/mitmproxy-ca-cert.pem ] && [ $count -lt 30 ]; do
    echo "⏳ Waiting for mitmproxy certificate..."
    sleep 1
    count=$((count + 1))
done

# Check if certificate is available
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    echo "📜 Found mitmproxy CA certificate"
    
    # Copy certificate to system trust store (requires root)
    if [ -w /usr/local/share/ca-certificates ]; then
        cp /certs/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates 2>/dev/null && echo "✅ Certificate installed in system trust store"
    else
        # Running as non-root, try to update Go's certificate bundle
        if [ -w /etc/ssl/certs ]; then
            cp /certs/mitmproxy-ca-cert.pem /etc/ssl/certs/mitmproxy.pem
            echo "✅ Certificate copied to /etc/ssl/certs"
        fi
    fi
    
    # Set environment variables as fallback
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
    export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    
    # For Go applications, set the system cert pool
    export GODEBUG=x509sha1=1
    export SSL_CERT_DIR=/etc/ssl/certs
    
    echo "✅ Certificate configured via environment variables"
else
    echo "⚠️  No mitmproxy certificate found at /certs/mitmproxy-ca-cert.pem after waiting"
fi

# Check if we're about to run an application command
# (not system commands like sh, bash, cat, ls, etc.)
IS_APP_COMMAND=false
if echo "$1" | grep -qE "^(go|python|node|npm|yarn|java|ruby|php|./|/app/|/proxy/)" || [ "$#" -eq 0 ]; then
    IS_APP_COMMAND=true
fi

# If running as root and it's an app command, show error and exit
if [ "$(id -u)" = "0" ] && [ "$IS_APP_COMMAND" = "true" ]; then
    echo "==========================================="
    echo "❌ ERROR: Cannot run application as root!"
    echo "==========================================="
    echo ""
    echo "The transparent proxy ONLY intercepts traffic from UID 1000 (appuser)."
    echo "Running as root will bypass the proxy completely!"
    echo ""
    echo "📖 Please read README.md for instructions on how to run the system correctly."
    echo ""
    echo "Quick fix - use the management script:"
    echo "  ./start-proxy-system.sh '$*'"
    echo ""
    echo "Or manually run as appuser:"
    echo "  docker exec -d app su-exec appuser sh -c \"$*\""
    echo ""
    echo "See README.md section: '🚀 Quick Start - Use Management Scripts'"
    echo "==========================================="
    exit 1
fi

# Switch to appuser for running the application (if we're root and it's allowed)
if [ "$(id -u)" = "0" ]; then
    # Execute the command as appuser
    exec su-exec appuser "$@"
else
    # Already non-root, execute directly
    exec "$@"
fi