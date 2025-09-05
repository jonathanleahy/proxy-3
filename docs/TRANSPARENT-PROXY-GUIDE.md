# 🔍 Transparent Proxy Recording Guide

> **The Magic:** Set HTTP_PROXY and capture EVERYTHING automatically!

## What is Transparent Mode?

In transparent mode, the capture proxy automatically:
- **Detects** where your app is trying to connect
- **Forwards** requests to the actual destination
- **Records** all responses
- **No configuration needed** - it just works!

## Quick Start

### 1. Start Transparent Recording

```bash
# Using orchestrate script (EASIEST)
./orchestrate.sh
# Choose option 1 (RECORD MODE)
# It automatically starts in transparent mode!

# Or manually:
TRANSPARENT_MODE=true \
CAPTURE_PORT=8091 \
OUTPUT_DIR=./captured \
go run cmd/capture/main.go
```

### 2. Set Your App to Use the Proxy

```bash
# Set these environment variables for your app:
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
export http_proxy=http://localhost:8091
export https_proxy=http://localhost:8091

# Then run your web server normally
go run your-server.go
# or
npm start
# or
python app.py
```

### 3. Use Your App

Just use your application normally! Every external API call will be:
- Automatically routed through the proxy
- Forwarded to the real destination
- Response captured and saved

### 4. Save Captures

```bash
curl http://localhost:8091/capture/save
```

## 🎯 Real-World Example

Let's say you have a web server that calls multiple APIs:

```go
// your-server.go
func handleRequest(w http.ResponseWriter, r *http.Request) {
    // Calls GitHub API
    resp1, _ := http.Get("https://api.github.com/users/octocat")
    
    // Calls Weather API
    resp2, _ := http.Get("https://api.openweathermap.org/data/2.5/weather?q=London")
    
    // Calls your internal API
    resp3, _ := http.Get("https://api.mycompany.com/v1/accounts")
    
    // Process and return data...
}
```

### Step-by-Step Recording:

```bash
# Terminal 1: Start transparent proxy
./orchestrate.sh
# Choose 1 for RECORD MODE

# Terminal 2: Run your server with proxy
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
go run your-server.go

# Terminal 3: Make requests to your server
curl http://localhost:8080/your-endpoint

# Back to Terminal 1: Save captures (option 4)
```

**Result:** The proxy captured responses from:
- `api.github.com`
- `api.openweathermap.org` 
- `api.mycompany.com`

All without any configuration!

## 📊 What Gets Captured?

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/users/octocat",
      "status": 200,
      "response": {
        "login": "octocat",
        "id": 583231,
        "name": "The Octocat"
      },
      "description": "Captured from api.github.com",
      "captured_at": "2025-01-15T10:00:00Z"
    },
    {
      "method": "GET",
      "path": "/data/2.5/weather",
      "status": 200,
      "response": {
        "weather": [{"main": "Clouds"}],
        "main": {"temp": 283.15}
      },
      "description": "Captured from api.openweathermap.org"
    }
  ]
}
```

## 🔄 Replay Mode

After recording, use the captured data as mocks:

```bash
# 1. Copy captures to config
cp captured/*.json configs/

# 2. Start mock server
./orchestrate.sh
# Choose 2 for REPLAY MODE

# 3. Point your app to mock server (instead of proxy)
export GITHUB_API_URL=http://localhost:8090
export WEATHER_API_URL=http://localhost:8090
# Remove proxy settings!
unset HTTP_PROXY
unset HTTPS_PROXY

# 4. Run your app - it now uses mocks!
go run your-server.go
```

## 🚀 Advanced Usage

### Docker Applications

```bash
# Record Docker container traffic
docker run -e HTTP_PROXY=http://host.docker.internal:8091 \
           -e HTTPS_PROXY=http://host.docker.internal:8091 \
           your-app:latest
```

### Node.js Applications

```javascript
// Proxy will be used automatically if HTTP_PROXY is set
process.env.HTTP_PROXY = 'http://localhost:8091';
process.env.HTTPS_PROXY = 'http://localhost:8091';

// Or use in package.json scripts
"scripts": {
  "dev:record": "HTTP_PROXY=http://localhost:8091 node server.js"
}
```

### Python Applications

```python
import os
os.environ['HTTP_PROXY'] = 'http://localhost:8091'
os.environ['HTTPS_PROXY'] = 'http://localhost:8091'

# Requests library respects these automatically
import requests
response = requests.get('https://api.example.com/data')
```

### Java Applications

```bash
java -Dhttp.proxyHost=localhost \
     -Dhttp.proxyPort=8091 \
     -Dhttps.proxyHost=localhost \
     -Dhttps.proxyPort=8091 \
     -jar your-app.jar
```

## 🎭 Complete Workflow

### Record Once
```bash
# 1. Start transparent proxy
TRANSPARENT_MODE=true go run cmd/capture/main.go &

# 2. Run your app with proxy
HTTP_PROXY=http://localhost:8091 ./your-app

# 3. Exercise all features of your app
# (make API calls, run tests, etc.)

# 4. Save captures
curl http://localhost:8091/capture/save
```

### Replay Forever
```bash
# 1. Start mock server
go run cmd/main.go &

# 2. Run your app pointing to mocks
API_URL=http://localhost:8090 ./your-app

# No internet needed!
# Same responses every time!
# Super fast!
```

## 🔧 Troubleshooting

### "Connection refused"
- Check proxy is running: `lsof -i :8091`
- Check HTTP_PROXY is set: `echo $HTTP_PROXY`

### "Not capturing anything"
- Ensure your app respects HTTP_PROXY
- Try with curl first: `curl -x http://localhost:8091 https://api.github.com`
- Check logs: proxy prints all forwarded requests

### "HTTPS not working"
- Set both HTTP_PROXY and HTTPS_PROXY
- Some apps use lowercase: `https_proxy`
- Some apps need: `ALL_PROXY`

### Application-specific proxy settings

**Go:**
```go
os.Setenv("HTTP_PROXY", "http://localhost:8091")
```

**Node.js:**
```javascript
process.env.HTTP_PROXY = 'http://localhost:8091';
```

**Python:**
```python
os.environ['HTTP_PROXY'] = 'http://localhost:8091'
```

**curl:**
```bash
curl -x http://localhost:8091 https://api.example.com
```

## 🎯 Benefits of Transparent Mode

1. **Zero Configuration** - No need to specify API endpoints
2. **Catches Everything** - Won't miss any API calls
3. **Service Discovery** - Automatically finds all dependencies
4. **Easy Migration** - Just set HTTP_PROXY, done!
5. **Language Agnostic** - Works with any language/framework

## 📝 Summary

**Traditional Mode:**
- Configure each API endpoint
- Might miss some APIs
- Need to know all endpoints upfront

**Transparent Mode:**
- Just set HTTP_PROXY
- Captures everything automatically
- Discovers APIs as they're called
- Perfect for complex applications

```bash
# One command to rule them all:
HTTP_PROXY=http://localhost:8091 ./your-app

# That's it! Everything gets recorded!
```