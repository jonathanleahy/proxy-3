#!/bin/sh
# Wrapper script that enforces running as appuser

# Check if running as root
if [ "$(id -u)" = "0" ]; then
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

# If not root, execute the command
exec "$@"