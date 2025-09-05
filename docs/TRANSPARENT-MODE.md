# 🔐 Transparent HTTPS Capture (No Certificates!)

## How It Works

This mode uses Docker's network namespace sharing and iptables to transparently intercept ALL HTTPS traffic without requiring any certificates or proxy configuration in your application.

```
┌─────────────┐       ┌──────────────────────┐
│   Your App  │──────►│  Transparent Proxy   │
│  Container  │       │     (iptables)       │
│             │       │                      │
│ network_mode│       │  - Intercepts 443    │
│  = service: │       │  - Decrypts HTTPS    │
│   proxy     │       │  - Logs everything   │
└─────────────┘       └──────────────────────┘
                               │
                               ▼
                        ┌──────────────┐
                        │ Real Server  │
                        │(github.com)  │
                        └──────────────┘
```

## Quick Start

```bash
# Make script executable
chmod +x transparent-capture.sh

# Start the system
./transparent-capture.sh start

# Run your app with transparent capture
./transparent-capture.sh run 'curl https://api.github.com'

# Or get a shell
./transparent-capture.sh exec
# Then run any commands - all HTTPS will be captured!
```

## Key Benefits

### ✅ No Certificate Installation
- No need to install CA certificates
- No SSL_CERT_FILE environment variable
- No certificate trust issues

### ✅ No Proxy Configuration
- No HTTP_PROXY/HTTPS_PROXY variables needed
- App doesn't know it's being proxied
- Works with any application

### ✅ Complete Transparency
- Traffic is intercepted at network level
- App thinks it's talking directly to servers
- All HTTPS is automatically decrypted

## How Transparent Mode Works

1. **Shared Network Namespace**: The app container uses `network_mode: "service:transparent-proxy"`, meaning it shares the exact same network stack as the proxy container.

2. **iptables Rules**: The proxy container sets up iptables rules that redirect all traffic on ports 80/443 to mitmproxy:
   ```bash
   iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8080
   ```

3. **Transparent Interception**: Mitmproxy runs in transparent mode (`--mode transparent`), which means it:
   - Accepts redirected connections
   - Determines the original destination
   - Establishes SSL with the real server
   - Decrypts and logs everything

4. **No Certificate Validation**: Since the app never sees the proxy (traffic is redirected at kernel level), it never needs to validate proxy certificates.

## Commands

### Start System
```bash
./transparent-capture.sh start
```

### Run Your Application
```bash
# Run any command - HTTPS will be captured
./transparent-capture.sh run 'your-app --flags'

# Examples:
./transparent-capture.sh run 'curl https://api.github.com/users/github'
./transparent-capture.sh run 'go run main.go'
./transparent-capture.sh run 'npm start'
```

### Interactive Shell
```bash
# Get a shell in the app container
./transparent-capture.sh exec

# Then run any commands
curl https://any-site.com  # Will be captured!
```

### View Logs
```bash
./transparent-capture.sh logs
```

### Stop System
```bash
./transparent-capture.sh stop
```

## Captured Data

All captured requests are saved to `./captured/` in JSON format compatible with the mock server.

View captures at: http://localhost:8090/viewer

## Requirements

- Docker
- Docker Compose
- Linux/Mac (Windows may need WSL2)
- NET_ADMIN capability (handled by Docker)

## Limitations

- Only captures HTTP/HTTPS traffic (ports 80/443)
- Requires Docker containers (can't capture host traffic)
- May not work with certificate pinning

## Comparison with Certificate Mode

| Feature | Transparent Mode | Certificate Mode |
|---------|-----------------|------------------|
| Certificates needed | ❌ No | ✅ Yes |
| Proxy settings | ❌ No | ✅ Yes |
| Setup complexity | Low | Medium |
| Works with any app | ✅ Yes | ⚠️ If app respects proxy |
| Container required | ✅ Yes | ❌ No |

## Troubleshooting

### "Cannot start service: driver failed"
Make sure Docker is running and you have permissions.

### "Address already in use"
Stop any services using port 8090:
```bash
lsof -ti:8090 | xargs kill -9
```

### "No captures appearing"
Check that your app is running inside the container:
```bash
./transparent-capture.sh run 'your-command'
# NOT: your-command (on host)
```

## Advanced Usage

### Custom Application Container

Edit `docker-compose-transparent.yml` to change the app container's command:

```yaml
app:
  command: |
    sh -c "
    # Your custom app command here
    node server.js
    "
```

### Different Ports

To capture other ports, edit `docker/transparent-entry.sh`:

```bash
# Add more ports
iptables -t nat -A PREROUTING -p tcp --dport 8443 -j REDIRECT --to-port 8080
```

## Security Note

This transparent mode is designed for development and testing. It intercepts ALL HTTPS traffic from the app container, which is exactly what you want for API capture but should not be used in production.