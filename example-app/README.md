# Example REST API App

This is a simple Go REST API that makes external API calls - perfect for demonstrating the proxy recording and replay system.

## Quick Start

### Build and Test

```bash
# Build for Docker container (Linux/AMD64)
./build.sh

# Test the API endpoints
./test.sh
```

### 1. Run with Recording (Capture Mode)
```bash
# Terminal 1: Start the capture proxy
cd ..
./orchestrate.sh  # Choose option 1 (RECORD MODE)

# Terminal 2: Run this app with proxy
cd example-app
export HTTP_PROXY=http://localhost:8091
go run main.go

# Terminal 3: Make API calls
curl http://localhost:8080/users
curl http://localhost:8080/posts
curl http://localhost:8080/aggregate

# Back in Terminal 1: Save captures (option 4)
```

### 2. Run with Mocks (Replay Mode)
```bash
# Terminal 1: Start the mock server
cd ..
./orchestrate.sh  # Choose option 2 (REPLAY MODE)

# Terminal 2: Run this app pointing to mocks
cd example-app
unset HTTP_PROXY  # Important!
export USERS_API_URL=http://localhost:8090
export POSTS_API_URL=http://localhost:8090
export API_BASE_URL=http://localhost:8090
go run main.go

# Terminal 3: Make API calls (now using mocks!)
curl http://localhost:8080/users
curl http://localhost:8080/posts
curl http://localhost:8080/aggregate
```

## Available Endpoints

- `GET /health` - Health check (no external calls)
- `GET /users` - Fetches user list from external API
- `GET /posts` - Fetches posts from external API  
- `GET /aggregate` - Combines data from multiple API calls

## Environment Variables

- `APP_PORT` - Server port (default: 8080)
- `HTTP_PROXY` - Proxy for recording (e.g., http://localhost:8091)
- `USERS_API_URL` - Override users API endpoint
- `POSTS_API_URL` - Override posts API endpoint
- `API_BASE_URL` - Override base API for aggregate endpoint

## How It Works

1. **In Record Mode**: The app's HTTP calls go through the proxy, which forwards them to real APIs and records responses
2. **In Replay Mode**: The app's HTTP calls go directly to the mock server, which returns the previously recorded responses

This demonstrates how you can test your app without internet access or real API dependencies!