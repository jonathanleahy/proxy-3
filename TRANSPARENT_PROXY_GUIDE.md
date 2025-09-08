# Transparent HTTPS Proxy Guide

## Status: ✅ Working

The transparent HTTPS proxy is now successfully intercepting and decrypting HTTPS traffic without requiring `InsecureSkipVerify` in your applications.

## Quick Start

### 1. Start the Proxy System

```bash
# Build and start all containers
docker compose -f docker-compose-transparent.yml up -d

# Verify mitmproxy is listening
docker exec transparent-proxy ss -tlnp | grep 8084
```

### 2. Manually Copy Certificate (if needed)

The certificate should auto-copy, but if the app can't find it:

```bash
docker exec transparent-proxy cp /home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem /certs/
```

### 3. Run Your Application

```bash
# Start the example app in the container
docker exec -d app sh -c "export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem && cd /proxy/example-app && go run main.go"

# Or run from host with test script
cd example-app
./test.sh
```

### 4. Verify Traffic Interception

```bash
# Check iptables counters (should show packets being redirected)
docker exec transparent-proxy iptables -t nat -L OUTPUT -v -n | grep -E "80|443"

# Example output showing successful interception:
# 0     0 REDIRECT   tcp dpt:80 owner UID match 1000 redir ports 8084
# 1    60 REDIRECT   tcp dpt:443 owner UID match 1000 redir ports 8084
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Host                           │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │          Shared Network Namespace                 │  │
│  │                                                   │  │
│  │  ┌─────────────────┐    ┌──────────────────┐    │  │
│  │  │   App Container  │    │ Proxy Container  │    │  │
│  │  │  (UID 1000)      │    │  (mitmproxy)     │    │  │
│  │  │                  │    │                  │    │  │
│  │  │  Go App ────┐    │    │  Port 8084       │    │  │
│  │  │             ↓    │    │       ↑          │    │  │
│  │  │  HTTPS Request   │    │       │          │    │  │
│  │  │  to :443         │    │   iptables      │    │  │
│  │  └──────────────────┘    │   redirect      │    │  │
│  │                          │       │          │    │  │
│  │                          │       ↓          │    │  │
│  │                          │   Decrypted      │    │  │
│  │                          │   & Logged      │    │  │
│  │                          │       │          │    │  │
│  │                          │       ↓          │    │  │
│  │                          │   Internet       │    │  │
│  │                          └──────────────────┘    │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Key Components

1. **Non-Root User (UID 1000)**
   - App runs as `appuser` with UID 1000
   - This ensures traffic can be distinguished from mitmproxy's own traffic

2. **iptables Rules**
   - Redirects port 80/443 traffic from UID 1000 to port 8084
   - Avoids redirect loops by only targeting specific UID
   ```bash
   iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner 1000 -j REDIRECT --to-port 8084
   ```

3. **Certificate Trust**
   - mitmproxy generates CA certificate
   - Certificate is shared via Docker volume
   - App uses `SSL_CERT_FILE` environment variable (no system installation needed)

4. **Shared Network Namespace**
   - App container uses `network_mode: "service:transparent-proxy"`
   - Both containers share the same network stack
   - Allows iptables rules to affect app traffic

## Troubleshooting

### Check if mitmproxy is running
```bash
docker exec transparent-proxy ss -tlnp | grep 8084
```

### View mitmproxy logs
```bash
docker logs transparent-proxy --tail 50
```

### Check iptables rules
```bash
docker exec transparent-proxy iptables -t nat -L OUTPUT -v -n
```

### Verify certificate exists
```bash
docker exec transparent-proxy ls -la /certs/
docker exec app ls -la /certs/
```

### Test without Docker
If you want to test the proxy manually:
```bash
# Set proxy environment variables
export HTTP_PROXY=http://localhost:8084
export HTTPS_PROXY=http://localhost:8084
export SSL_CERT_FILE=$(pwd)/captured/mitmproxy-ca-cert.pem

# Run your application
go run example-app/main.go
```

## Known Issues

1. **Output Buffering**: mitmproxy output may be buffered and not immediately visible in logs
2. **Certificate Timing**: Certificate generation takes a few seconds on first start
3. **Capture Saving**: The capture script may need adjustment for automatic saving

## Files Modified

- `docker/Dockerfile.app` - Added non-root user (UID 1000)
- `docker/transparent-entry.sh` - Fixed iptables rules and added debugging
- `docker/app-entry.sh` - Uses environment variables for certificate trust
- `example-app/main.go` - Removed InsecureSkipVerify

## Next Steps

To improve capture saving:
1. Check the mitmproxy script buffering
2. Add periodic save functionality
3. Implement proper logging for the capture script