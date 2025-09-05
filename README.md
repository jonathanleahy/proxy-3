# Mock API Server

A dynamic REST API simulator that captures and replays HTTP traffic - perfect for testing without external dependencies.

## Features

- 🔍 **Transparent Proxy Mode**: Automatically detect and record ALL API calls
- 🔄 **Dynamic Route Loading**: Define routes and responses in JSON files
- 🔥 **Hot Reload**: Automatically reloads when JSON files change
- 📸 **Smart Capture**: Record real API responses for use as mocks
- 🎯 **Path Parameters**: Support for dynamic path segments like `/accounts/{id}`
- 🎭 **Record & Replay**: Capture once, replay forever
- ⏱️ **Response Delays**: Simulate network latency
- 🚀 **Zero Configuration**: Works out of the box with sensible defaults

## Quick Start

### 🚀 NEW: Transparent Proxy Mode (Easiest!)

```bash
# 1. Start the transparent recording proxy
./orchestrate.sh  # Choose option 1

# 2. Run your app with proxy settings
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
./your-app

# 3. Your app's API calls are automatically captured!
# No configuration needed - it detects and records everything

# 4. Replay captured traffic later
./orchestrate.sh  # Choose option 2
```

### Traditional Quick Start

```bash
# Quick demo
make quick-demo

# Or use interactive menu
./orchestrate.sh

# Or run components individually
go run cmd/main.go          # Mock server
go run cmd/capture/main.go  # Capture proxy
```

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