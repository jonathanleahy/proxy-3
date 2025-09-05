# Transparent Proxy - Example Usage

## Quick Start

### 1. Start the system and server together:
```bash
./transparent-capture.sh start --with-server
```

### 2. Test the connection:
```bash
curl http://localhost:8080/api/health
```

## Step-by-Step Usage

### Option A: Start Everything at Once
```bash
# Start containers AND auto-start the server
./transparent-capture.sh start --with-server

# Test it's working
curl http://localhost:8080/api/health
```

### Option B: Manual Server Start
```bash
# Start the containers
./transparent-capture.sh start

# Start the server
./transparent-capture.sh server

# Test it's working
curl http://localhost:8080/api/health
```

## Testing with the Test Server

If the main server isn't working, use the test server:

```bash
# Run the connection test (automatically starts test server)
./test-connection.sh

# Or manually:
./transparent-capture.sh exec
# Inside container:
./test-server
```

## Common Commands

```bash
# View server logs
./transparent-capture.sh app-logs

# Follow logs live
./transparent-capture.sh app-logs -f

# Stop just the server
./transparent-capture.sh stop-server

# Stop everything
./transparent-capture.sh stop

# Run a command with transparent capture
./transparent-capture.sh run 'curl https://api.github.com'
```

## Troubleshooting

### "Connection reset by peer" error
The server isn't running. Start it with:
```bash
./transparent-capture.sh server
```

### After machine restart
The containers don't auto-start the server. Either:
1. Use `./transparent-capture.sh start --with-server`
2. Or manually start with `./transparent-capture.sh server`

### Testing if it's working
```bash
# Quick test
curl http://localhost:8080/api/health

# Full diagnostic test
./test-connection.sh
```

## What's Actually Happening

1. **transparent-proxy container**: Runs mitmproxy, handles the network routing
2. **app container**: Your application environment (shares network with transparent-proxy)
3. **Port 8080**: Your REST API server
4. **Port 8084**: mitmproxy (internal, for transparent capture)
5. **Port 8090**: Web viewer for captured requests

The app container uses the transparent-proxy's network namespace, so all HTTPS traffic from your app is automatically captured without needing certificates or proxy settings.