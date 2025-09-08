#!/bin/sh
# Entry point for app container to install mitmproxy certificate

# Check if certificate is available
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    echo "📜 Installing mitmproxy CA certificate..."
    cp /certs/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt
    update-ca-certificates
    echo "✅ CA certificate installed and trusted"
else
    echo "⚠️  No mitmproxy certificate found at /certs/mitmproxy-ca-cert.pem"
fi

# Execute the command passed to the container
exec "$@"