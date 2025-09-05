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

## Configuration

### Route Definition Format

Routes are defined in JSON files in the `configs/` directory:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/v2/accounts/{id}",
      "status": 200,
      "description": "Get account by ID",
      "headers": {
        "Content-Type": "application/json"
      },
      "delay": 100,
      "response": {
        "id": "{{id}}",
        "status": "ACTIVE",
        "balance": 1000.00
      }
    }
  ]
}
```

### Features

- **Path Parameters**: Use `{param}` in paths, access with `{{param}}` in responses
- **Multiple Files**: Split routes across multiple JSON files for organization
- **Hot Reload**: Changes to JSON files are applied immediately
- **404 by Default**: Returns 404 for undefined routes

## Capture Real API Responses

### Method 1: Transparent Proxy Mode (NEW - Recommended!)

No configuration needed - automatically detects and records ALL API calls:

```bash
# 1. Start transparent recording
./orchestrate.sh  # Choose option 1 (RECORD MODE)

# 2. Run your application with proxy
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
./your-web-server

# 3. Use your application normally
# ALL external API calls are automatically captured!

# 4. Save captured responses
# In orchestrator menu, choose option 4 (SAVE)
# Or: curl http://localhost:8091/capture/save

# 5. Replay captured traffic
./orchestrate.sh  # Choose option 2 (REPLAY MODE)
```

### Method 2: Traditional Configuration Mode

Configure specific API endpoints to proxy:

```bash
# Set real API URLs as environment variables
export ACCOUNTS_API_URL=https://real-api.example.com
export WALLET_API_URL=https://real-wallet-api.example.com

# Run capture proxy
go run cmd/capture/main.go

# Point your app to proxy URLs
# Save captures when done
curl http://localhost:8091/capture/save
```

## Using Captured Data

1. Captured responses are saved to `./captured/` directory
2. Copy them to `./configs/` to use as mock data
3. The format is already compatible - no conversion needed!

```bash
# Use captured data as mocks
cp ./captured/accounts-captured.json ./configs/
```

## Management Commands

```bash
# Start services
./run-with-mocks.sh start

# Stop services
./run-with-mocks.sh stop

# View logs
./run-with-mocks.sh logs mock-api-server

# Check status
./run-with-mocks.sh status

# Reload routes (happens automatically)
./run-with-mocks.sh reload

# Start capture mode
./run-with-mocks.sh capture
```

## 🔍 Transparent Proxy Mode (New Feature!)

The transparent proxy mode automatically detects and records ALL external API calls without any configuration:

### How It Works
1. **Set HTTP_PROXY** - Your app sends all HTTP traffic through the proxy
2. **Auto-Detection** - Proxy automatically detects the destination
3. **Forward & Record** - Forwards to real API and records response
4. **Zero Config** - No need to specify API endpoints upfront!

### Example: Recording a Complex App
```bash
# Your app makes calls to multiple APIs:
# - api.github.com
# - api.stripe.com
# - maps.googleapis.com
# - internal-api.company.com

# Just set the proxy and run:
export HTTP_PROXY=http://localhost:8091
./your-app

# ALL these APIs are automatically captured!
```

### Supported Languages
Works with any language that respects HTTP_PROXY:
- **Go**: Automatic with `http.Get()`
- **Node.js**: Automatic with `axios`, `fetch`
- **Python**: Automatic with `requests`
- **Java**: Use `-Dhttp.proxyHost`
- **Docker**: Use `-e HTTP_PROXY`

## 🔐 MITM Proxy Mode - Full HTTPS Content Capture

NEW! Capture and inspect **encrypted HTTPS content** using mitmproxy in Docker - perfect for restricted environments without admin access!

### Quick Start (No Admin Required!)

```bash
# 1. Start MITM proxy with Docker
docker-compose --profile mitm up

# 2. Extract the CA certificate (one-time setup)
./scripts/get-mitm-cert.sh

# 3. Run your app with the CA certificate (no admin needed!)
export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
./your-app

# Your HTTPS traffic is now fully captured and decrypted!
```

### What You Get with MITM
- ✅ **Full HTTPS content** - Request/response bodies, even encrypted
- ✅ **All headers** - Including cookies, auth tokens
- ✅ **No admin required** - Uses environment variables
- ✅ **Docker-based** - No system changes needed
- ✅ **Same format** - Compatible with existing viewer and replay

### Two Proxy Options
| Feature | Port 8091 (CONNECT) | Port 8080 (MITM) |
|---------|-------------------|------------------|
| HTTPS Support | ✅ Yes | ✅ Yes |
| See HTTPS Content | ❌ No | ✅ Yes (decrypted) |
| Certificates | ❌ Not needed | ✅ Auto-generated |
| Setup Complexity | Simple | Docker + CA cert |

See [docs/MITM-SETUP.md](docs/MITM-SETUP.md) for detailed instructions.

## Project Structure

```
.
├── cmd/
│   ├── main.go           # Mock server
│   └── capture/
│       └── main.go       # Capture proxy with transparent mode
├── configs/              # Route definition JSON files
│   └── *.json           # Mock configurations
├── captured/             # Captured real responses
│   └── *.json           # Auto-captured from proxy
├── example-app/          # Demo application
├── docs/                 # Documentation
│   ├── DUMMYS-GUIDE.md
│   ├── ORCHESTRATION-TUTORIAL.md
│   ├── TRANSPARENT-PROXY-GUIDE.md
│   └── ARCHITECTURE.md
├── orchestrate.sh        # Interactive menu system
├── quick-test.sh         # Quick testing script
├── Makefile             # Common commands
└── docker-compose.yml   # Container orchestration
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8090` | Mock server port |
| `CONFIG_PATH` | `./configs` | Directory for route JSON files |
| `CAPTURE_PORT` | `8091` | Capture proxy port |
| `OUTPUT_DIR` | `./captured` | Directory for captured responses |

## Tips

1. **Organization**: Split routes by service (accounts.json, cards.json, etc.)
2. **Versioning**: Include API version in paths (`/v1/`, `/v2/`)
3. **Scenarios**: Create different JSON files for different test scenarios
4. **Errors**: Define error responses with appropriate status codes
5. **Delays**: Add realistic delays to simulate network latency

## Troubleshooting

### Routes Not Loading
- Check JSON syntax in config files
- Look at server logs for parsing errors
- Ensure files are in the `configs/` directory

### 404 Responses
- Verify the path matches exactly (including leading `/`)
- Check method (GET, POST, etc.) matches
- Look at server logs to see requested vs configured paths

### Capture Not Working
- Ensure real API URLs are accessible
- Check proxy is running on correct port
- Verify environment variables are set correctly

## Examples

### Adding a New Route

1. Create or edit a JSON file in `configs/`:

```json
{
  "routes": [
    {
      "method": "POST",
      "path": "/v1/payments",
      "status": 201,
      "response": {
        "payment_id": "PAY-123",
        "status": "PROCESSING"
      }
    }
  ]
}
```

2. The route is immediately available (hot reload)

### Simulating Errors

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/v1/accounts/999",
      "status": 404,
      "response": {
        "error": "Account not found",
        "code": "ACCOUNT_NOT_FOUND"
      }
    }
  ]
}
```

### Dynamic Responses

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/v1/users/{userId}/orders/{orderId}",
      "status": 200,
      "response": {
        "user_id": "{{userId}}",
        "order_id": "{{orderId}}",
        "total": 99.99
      }
    }
  ]
}
```

## Contributing

Feel free to add more mock data or enhance the capture functionality!