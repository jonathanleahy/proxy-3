# Transparent HTTPS Proxy System

A Docker-based transparent HTTPS proxy that captures all HTTP/HTTPS traffic without requiring certificates or proxy configuration. Perfect for API development, testing, and debugging.

## Features

- 🔐 **No certificates needed** - Transparent interception using iptables
- 🚀 **Zero configuration** - Works out of the box
- 📊 **Web viewer** - View captured requests at http://localhost:8090/viewer
- 🔄 **Hot reload** - Mock server auto-reloads when config changes
- 🏗️ **Multi-architecture** - Supports x86_64, ARM64, and more
- 🐳 **Docker-based** - Consistent environment across all platforms

## Quick Start

### 1. Clone and Setup (First Time Only)

```bash
git clone https://github.com/jonathanleahy/proxy-3.git
cd proxy-3
./setup.sh  # Builds binaries and Docker images
```

### 2. Start Everything

```bash
# Option A: Start system and server together
./transparent-capture.sh start --with-server

# Option B: Start separately
./transparent-capture.sh start   # Start containers
./transparent-capture.sh server  # Start REST server
```

### 3. Test It Works

```bash
curl http://localhost:8080/api/health
# Returns: {"status":"healthy"}
```

## How It Works

The system uses three Docker containers:

1. **transparent-proxy** - Runs mitmproxy with iptables rules to intercept traffic
2. **app** - Your application container (shares network with proxy)
3. **viewer** - Web interface to view captured requests

The app container shares the network namespace with the proxy container, so all outbound HTTPS traffic is automatically captured without any proxy settings or certificates.

## Common Commands

### Starting and Stopping

```bash
./transparent-capture.sh start           # Start containers
./transparent-capture.sh start --with-server  # Start with server
./transparent-capture.sh server          # Start REST server
./transparent-capture.sh stop-server     # Stop server only
./transparent-capture.sh stop            # Stop everything
```

### Running Applications

```bash
# Run the main server
./transparent-capture.sh run './main'

# Run any command with transparent capture
./transparent-capture.sh run 'curl https://api.github.com'

# Open shell in container
./transparent-capture.sh exec
```

### Monitoring

```bash
./transparent-capture.sh app-logs        # View server logs
./transparent-capture.sh app-logs -f     # Follow logs live
./transparent-capture.sh logs            # View all container logs
```

### Testing

```bash
./test-connection.sh                     # Run diagnostic test
curl http://localhost:8080/api/health    # Quick health check
```

## Ports

- **8080** - Your REST API server
- **8084** - mitmproxy (internal)
- **8090** - Web viewer for captured requests

## Building for Different Architectures

The `build.sh` script automatically detects your architecture:

```bash
./build.sh  # Builds for your current architecture
```

Supported architectures:
- x86_64 (amd64)
- ARM64 (Apple Silicon, AWS Graviton)
- ARMv7

## Troubleshooting

### "Connection reset by peer" error

The server isn't running. Start it with:
```bash
./transparent-capture.sh server
```

### After machine restart

The server doesn't auto-start. Use:
```bash
./transparent-capture.sh start --with-server
```

### Port 8080 already in use

```bash
lsof -ti:8080 | xargs kill -9  # Kill process using port
./transparent-capture.sh stop   # Stop containers
./transparent-capture.sh start  # Restart
```

### Permission denied errors

```bash
chmod +x *.sh  # Make scripts executable
sudo chown -R $USER:$USER .  # Fix ownership
```

## Project Structure

```
proxy-3/
├── main                    # REST server binary (built by build.sh)
├── test-server            # Test server binary
├── rest-server.go         # REST server source
├── test-server.go         # Test server source
├── transparent-capture.sh # Main control script
├── test-connection.sh     # Connection test script
├── build.sh              # Build binaries script
├── setup.sh              # Initial setup script
├── docker-compose-transparent.yml
├── docker/
│   ├── Dockerfile.app
│   ├── Dockerfile.mitmproxy
│   └── transparent-entry.sh
├── scripts/
│   └── mitm_capture.py   # mitmproxy capture script
├── captured/             # Captured requests (created automatically)
└── configs/              # Mock server configs
```

## Requirements

- Docker & Docker Compose
- Go 1.19+ (for building binaries)
- Linux/macOS (Windows via WSL2)

## How to Use on Another Machine

1. Copy the entire project directory
2. Run `./setup.sh` to build for local architecture
3. Start with `./transparent-capture.sh start --with-server`

No need to worry about paths or user-specific configurations!

## API Endpoints

The included REST server provides:

- `GET /` - Returns server info
- `GET /api/health` - Health check endpoint
- `GET /api/test` - Test endpoint

Each request triggers an outbound HTTPS call to GitHub API that gets transparently captured.

## Advanced Usage

### Custom Applications

Place your application in the project directory and run:

```bash
./transparent-capture.sh run './your-app'
```

### Building Inside Container

```bash
./transparent-capture.sh exec
# Inside container:
go build -o my-app my-app.go
./my-app
```

### Viewing Captures

1. Visit http://localhost:8090/viewer
2. Or check `./captured/` directory for JSON files

## License

MIT

## Support

For issues, visit: https://github.com/jonathanleahy/proxy-3/issues