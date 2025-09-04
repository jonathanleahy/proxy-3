# 🎓 Complete Tutorial: API Recording & Replay System

> **Learn by doing:** This tutorial will walk you through setting up, recording, and replaying API calls step-by-step.

## 📚 Table of Contents
1. [Understanding the System](#understanding-the-system)
2. [Quick Start Tutorial](#quick-start-tutorial)
3. [Full Orchestration Tutorial](#full-orchestration-tutorial)
4. [Building a Sample Go REST App](#building-a-sample-go-rest-app)
5. [End-to-End Workflow](#end-to-end-workflow)
6. [Advanced Scenarios](#advanced-scenarios)

---

## 🎯 Understanding the System

### What We're Building
A complete system that can:
1. **Record** - Capture real API responses when your app makes external calls
2. **Replay** - Use those captured responses as mocks for testing

### The Components
```
Your App → Proxy → Real API     (RECORD mode)
Your App → Mock Server           (REPLAY mode)
```

### Why This Matters
- **No Internet needed** for testing after recording
- **Consistent test data** - same response every time
- **Fast tests** - no network delays
- **Cost savings** - no API call charges

---

## 🚀 Quick Start Tutorial

### Step 1: First Time Setup

```bash
# Clone or navigate to the project
cd proxy-3

# Make scripts executable
chmod +x orchestrate.sh quick-test.sh

# Verify Go is installed
go version
```

### Step 2: Try the Quick Test

```bash
# Record some API calls
./quick-test.sh record
```

You'll see:
```
🔴 RECORD MODE - Starting capture proxy...
📸 Making test API calls...
"Leanne Graham"
"sunt aut facere repellat provident occaecati excepturi optio reprehenderit"
{...todo data...}
💾 Saving captures...
✅ Captured 2 files
```

### Step 3: Replay the Captured Data

```bash
# Use captured data as mocks
./quick-test.sh replay
```

You'll see:
```
🎭 REPLAY MODE - Starting mock server...
📡 Testing mock endpoints...
Users endpoint:
"Leanne Graham"
Posts endpoint:
"sunt aut facere..."
✅ Mock server ready at http://localhost:8090
```

### Step 4: Test What's Running

```bash
# In a new terminal
./quick-test.sh test
```

**Congratulations!** You've just recorded and replayed API calls! 🎉

---

## 🎮 Full Orchestration Tutorial

### Starting the Orchestrator

```bash
./orchestrate.sh
```

You'll see this menu:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🎯 API Recording & Replay Orchestrator
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1) 📸 RECORD MODE - Capture real API responses
2) 🎭 REPLAY MODE - Use captured mocks
3) 🧪 TEST MODE   - Quick curl tests
4) 💾 SAVE        - Save current captures
5) 📊 STATUS      - Check system status
6) ❌ EXIT

Choose mode: 
```

### Tutorial: Recording Real APIs

#### Choose Option 1 (RECORD MODE)
```
Choose mode: 1
```

#### Enter API URLs (or use defaults)
```
Enter real API URLs (or press Enter for defaults):
ACCOUNTS_API_URL [https://jsonplaceholder.typicode.com]: [PRESS ENTER]
```

#### Start Your App (Optional)
```
Do you have a Go REST app to start? (y/n): n
```

#### The System is Now Recording!
```
✅ RECORD MODE ACTIVE
All HTTP calls will be captured through proxy at localhost:8091

You can now:
  • Make curl requests to your app
  • Use your app normally
  • All external API calls will be recorded
```

#### In Another Terminal, Make Some API Calls:
```bash
# These calls go through the proxy and get recorded
curl -x http://localhost:8091 https://jsonplaceholder.typicode.com/users
curl -x http://localhost:8091 https://jsonplaceholder.typicode.com/posts/1
curl -x http://localhost:8091 https://jsonplaceholder.typicode.com/comments?postId=1
```

#### Return to Orchestrator and Save (Option 4)
```
Choose mode: 4

💾 Saving captures...
✅ Captures saved successfully

Captured files:
-rw-r--r-- 1 user user 15234 Nov 10 10:00 captured/all-captured.json
-rw-r--r-- 1 user user 15234 Nov 10 10:00 captured/misc-captured.json
```

### Tutorial: Replaying as Mocks

#### Choose Option 2 (REPLAY MODE)
```
Choose mode: 2

🎭 Starting REPLAY MODE...
Found captured responses, copying to configs...
✅ Captured responses loaded
Starting mock server on port 8090...

✅ REPLAY MODE ACTIVE
Mock server running at http://localhost:8090

Available endpoints:
  • all-captured.json
    - /users
    - /posts/{id}
    - /comments
```

#### Test the Mocks (Option 3)
```
Choose mode: 3

Select test type:
1) Test through RECORD mode (captures traffic)
2) Test REPLAY mode (uses mocks)
3) Custom curl command
Choice: 2

🎭 Testing REPLAY mode...
Example: Fetching from mock server
{
  "userId": 1,
  "id": 1,
  "title": "...",
  "body": "..."
}
```

---

## 🛠️ Building a Sample Go REST App

Let's create a simple Go app that makes external API calls:

### Create `example-app/main.go`:

```go
package main

import (
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "os"
)

// WeatherService calls external weather API
type WeatherService struct {
    BaseURL string
}

type WeatherResponse struct {
    Location string  `json:"location"`
    Temp     float64 `json:"temp"`
    Summary  string  `json:"summary"`
}

func (w *WeatherService) GetWeather(city string) (*WeatherResponse, error) {
    // This will use HTTP_PROXY if set
    resp, err := http.Get(fmt.Sprintf("%s/weather?city=%s", w.BaseURL, city))
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    body, _ := io.ReadAll(resp.Body)
    
    var weather WeatherResponse
    json.Unmarshal(body, &weather)
    return &weather, nil
}

func main() {
    // Use external API or mock based on environment
    baseURL := os.Getenv("WEATHER_API_URL")
    if baseURL == "" {
        baseURL = "https://api.openweathermap.org/data/2.5"
    }

    service := &WeatherService{BaseURL: baseURL}

    http.HandleFunc("/weather", func(w http.ResponseWriter, r *http.Request) {
        city := r.URL.Query().Get("city")
        if city == "" {
            city = "London"
        }

        weather, err := service.GetWeather(city)
        if err != nil {
            http.Error(w, err.Error(), http.StatusInternalServerError)
            return
        }

        json.NewEncoder(w).Encode(weather)
    })

    fmt.Println("Server starting on :8080")
    http.ListenAndServe(":8080", nil)
}
```

### Using the App with Recording:

```bash
# Terminal 1: Start orchestrator in record mode
./orchestrate.sh
# Choose option 1, set up proxy

# Terminal 2: Start your Go app with proxy
export HTTP_PROXY=http://localhost:8091
export WEATHER_API_URL=https://api.openweathermap.org/data/2.5
go run example-app/main.go

# Terminal 3: Make requests to your app
curl http://localhost:8080/weather?city=London
curl http://localhost:8080/weather?city=Paris

# Back in Terminal 1: Save captures (option 4)
```

### Using the App with Replay:

```bash
# Terminal 1: Start orchestrator in replay mode
./orchestrate.sh
# Choose option 2

# Terminal 2: Start your app pointing to mock
export WEATHER_API_URL=http://localhost:8090
unset HTTP_PROXY  # Important: remove proxy
go run example-app/main.go

# Terminal 3: Make requests (now using mocks!)
curl http://localhost:8080/weather?city=London
# Returns the exact same data that was captured!
```

---

## 📋 End-to-End Workflow

### Complete Workflow Example

#### 1. Initial Setup
```bash
# Start fresh
rm -rf captured/*.json
rm -rf configs/*.json
```

#### 2. Record Phase
```bash
# Start orchestrator
./orchestrate.sh

# Choose 1 (RECORD)
# Enter your real API URLs
# Start your app if needed

# In another terminal, exercise your app
curl http://localhost:8080/endpoint1
curl -X POST http://localhost:8080/endpoint2 -d '{"data":"test"}'
curl http://localhost:8080/endpoint3

# Back in orchestrator, choose 4 (SAVE)
# Then choose 6 (EXIT)
```

#### 3. Replay Phase
```bash
# Start orchestrator
./orchestrate.sh

# Choose 2 (REPLAY)
# Mocks are automatically loaded

# Your app now uses mocks instead of real APIs
# No internet needed!
# Same responses every time!
```

#### 4. Check What's Happening
```bash
# In orchestrator, choose 5 (STATUS)

📊 System Status

✅ Capture Proxy: RUNNING on port 8091
   {"captured_routes":5,"output_dir":"./captured"}
✅ Mock Server: RUNNING on port 8090
✅ Proxy Variables: SET
   HTTP_PROXY=http://localhost:8091
📁 Captured Files: 2 files
```

---

## 🚀 Advanced Scenarios

### Scenario 1: Multiple External APIs

```bash
# Edit run-capture-proxy.sh with multiple APIs
export ACCOUNTS_API_URL="https://api.mycompany.com/accounts"
export ORDERS_API_URL="https://api.mycompany.com/orders"
export INVENTORY_API_URL="https://api.partner.com/inventory"

# The proxy will route based on the path:
# /accounts/* → ACCOUNTS_API_URL
# /orders/*   → ORDERS_API_URL
# /inventory/* → INVENTORY_API_URL
```

### Scenario 2: Docker Environment

```bash
# Record from Docker containers
docker run --network host \
  -e HTTP_PROXY=http://localhost:8091 \
  -e HTTPS_PROXY=http://localhost:8091 \
  your-app:latest

# Captures work the same way!
```

### Scenario 3: CI/CD Pipeline

```bash
# In your CI pipeline
./quick-test.sh replay &  # Start mock server
sleep 5

# Run your tests against mocks
npm test
go test ./...
pytest

# Cleanup
pkill -f "cmd/main.go"
```

### Scenario 4: Team Collaboration

```bash
# After recording, commit the captures
git add captured/*.json
git commit -m "Updated API mocks"
git push

# Team members can pull and use immediately
git pull
./quick-test.sh replay
```

---

## 🎯 Quick Command Reference

### Recording Commands
```bash
# Quick record
./quick-test.sh record

# Interactive record
./orchestrate.sh  # Choose option 1

# Manual record
HTTP_PROXY=http://localhost:8091 curl https://api.example.com
```

### Replay Commands
```bash
# Quick replay
./quick-test.sh replay

# Interactive replay
./orchestrate.sh  # Choose option 2

# Manual replay
curl http://localhost:8090/your-endpoint
```

### Testing Commands
```bash
# Quick test
./quick-test.sh test

# Check status
./orchestrate.sh  # Choose option 5

# Save captures
curl http://localhost:8091/capture/save
```

---

## 🔧 Troubleshooting

### "Connection refused"
- Check the proxy is running: `./orchestrate.sh` → option 5
- Check ports 8090 and 8091 are free: `lsof -i :8090`

### "No captures saved"
- Make sure you made API calls while in record mode
- Check HTTP_PROXY is set: `echo $HTTP_PROXY`
- Try manual save: `curl http://localhost:8091/capture/save`

### "Mock not returning data"
- Check captured files exist: `ls captured/`
- Verify files copied to configs: `ls configs/`
- Check the path matches exactly

### "Proxy not intercepting"
- Ensure HTTP_PROXY is exported: `export HTTP_PROXY=http://localhost:8091`
- Some apps need: `export https_proxy` (lowercase)
- Docker needs: `--network host`

---

## 📚 Next Steps

1. **Customize captures** - Edit the JSON files in `captured/`
2. **Add delays** - Simulate slow networks in your mocks
3. **Error scenarios** - Add 404, 500 responses to test error handling
4. **Share with team** - Commit your `captured/` folder
5. **Automate tests** - Use in CI/CD pipelines

---

## 🎉 Congratulations!

You now know how to:
- ✅ Record real API responses
- ✅ Replay them as mocks
- ✅ Switch between modes easily
- ✅ Test without internet or real APIs
- ✅ Share test data with your team

Happy testing! 🚀