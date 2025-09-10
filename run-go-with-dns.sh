#!/bin/sh
# Run Go app with fixed DNS resolution

# Set Go to use pure Go DNS resolver with custom servers
export GODEBUG=netdns=go
export GOPROXY=direct

# Create custom resolv.conf
cat > /tmp/resolv.conf << 'RESOLV'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
RESOLV

# Use the custom resolv.conf
export LOCALDOMAIN=
export RES_OPTIONS=
export HOSTALIASES=/dev/null
export RESOLV_HOST_CONF=/tmp/resolv.conf

# Run the Go app with custom DNS
exec "$@"
