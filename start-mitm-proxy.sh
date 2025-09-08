#!/bin/bash

# Start mitmproxy in regular proxy mode (not transparent) for HTTPS decryption
# This is more reliable than transparent mode

echo "🔐 Starting MITM Proxy with HTTPS Decryption"
echo "============================================"
echo ""

# Kill any existing mitmproxy
pkill -f mitmdump 2>/dev/null || true

# Create captured directory if it doesn't exist
mkdir -p captured

echo "Starting mitmproxy on port 8082..."
echo ""

# Run mitmproxy with the capture script
OUTPUT_DIR=./captured mitmdump \
    --listen-port 8082 \
    --set confdir=~/.mitmproxy \
    -s scripts/mitm_capture.py \
    --ssl-insecure &

sleep 2

echo ""
echo "✅ MITM Proxy is running on port 8082"
echo ""
echo "To use it:"
echo "  1. Set proxy: export HTTP_PROXY=http://localhost:8082 HTTPS_PROXY=http://localhost:8082"
echo "  2. Run your app with these environment variables"
echo "  3. HTTPS content will be decrypted and captured"
echo ""
echo "View captures at: http://localhost:8090/viewer"
echo ""
echo "To stop: pkill -f mitmdump"