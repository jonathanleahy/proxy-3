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
    # Set environment variable for SSL certificate
    export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem
    export REQUESTS_CA_BUNDLE=/certs/mitmproxy-ca-cert.pem
    export NODE_EXTRA_CA_CERTS=/certs/mitmproxy-ca-cert.pem
    echo "✅ Certificate configured via environment variables"
else
    echo "⚠️  No mitmproxy certificate found at /certs/mitmproxy-ca-cert.pem after waiting"
fi

# Execute the command passed to the container
exec "$@"