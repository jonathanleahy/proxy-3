# Mock API Server

A dynamic REST API simulator that allows you to run the Firecracker API without external dependencies.

## Features

- 🔄 **Dynamic Route Loading**: Define routes and responses in JSON files
- 🔥 **Hot Reload**: Automatically reloads when JSON files change
- 📸 **Capture Mode**: Record real API responses for use as mocks
- 🎯 **Path Parameters**: Support for dynamic path segments like `/accounts/{id}`
- ⏱️ **Response Delays**: Simulate network latency
- 📝 **Custom Headers**: Set response headers per route
- 🚀 **Zero Configuration**: Works out of the box with sensible defaults

## Quick Start

### 1. Run Everything with Mocks

```bash
# Start all services including mock server
./run-with-mocks.sh start

# The API will be available at http://localhost:8080
# Mock server runs at http://localhost:8090
```

### 2. Run Mock Server Standalone

```bash
cd mock-api-server
go run cmd/main.go

# Or with Docker
docker-compose -f docker-compose.mock.yml up
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

### Method 1: Intercept Mode (Recommended)

Run on a machine with access to real APIs:

```bash
# 1. Start the capture proxy
./mock-api-server/capture-real-apis.sh intercept

# 2. Run the generated script
./run-capture-proxy.sh

# 3. Update your .env to point to the proxy
ACCOUNTS_API_URL=http://localhost:8091/accounts
# ... other APIs

# 4. Use the application normally

# 5. Save captured responses
curl http://localhost:8091/capture/save

# 6. Find JSON files in ./mock-api-server/captured/
```

### Method 2: Direct Capture

```bash
cd mock-api-server

# Set real API URLs as environment variables
export ACCOUNTS_API_URL=https://real-api.example.com
export WALLET_API_URL=https://real-wallet-api.example.com

# Run capture proxy
go run cmd/capture/main.go

# Make requests through the proxy
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

## Project Structure

```
mock-api-server/
├── cmd/
│   ├── main.go           # Mock server
│   └── capture/
│       └── main.go       # Capture proxy
├── configs/              # Route definition JSON files
│   └── accounts-api.json # Sample routes
├── captured/             # Captured real responses
├── Dockerfile           
└── README.md
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