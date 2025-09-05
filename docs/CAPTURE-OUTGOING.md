# How to Capture OUTGOING API Calls from Your App

## The Problem
If you're seeing incoming calls to your app instead of outgoing calls FROM your app, it means your app's HTTP client isn't using the proxy.

## Solutions by Language

### Go Application

#### Method 1: Environment Variables (Easiest)
```go
// In your app's main() or init()
import (
    "net/http"
    "os"
)

func init() {
    // The default http.Client respects HTTP_PROXY
    // Just make sure you're using http.Get, http.Post, etc.
}

func makeAPICall() {
    // This WILL use the proxy if HTTP_PROXY is set
    resp, err := http.Get("https://external-api.com/data")
    
    // This also works
    resp, err := http.Post("https://api.example.com/users", "application/json", body)
}
```

Then run your app:
```bash
HTTP_PROXY=http://localhost:8091 HTTPS_PROXY=http://localhost:8091 go run your-app.go
```

#### Method 2: Explicit Proxy Configuration
```go
import (
    "net/http"
    "net/url"
)

func createProxyClient() *http.Client {
    proxyURL, _ := url.Parse("http://localhost:8091")
    return &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyURL(proxyURL),
        },
    }
}

func makeAPICall() {
    client := createProxyClient()
    resp, err := client.Get("https://external-api.com/data")
    // This request WILL go through the proxy
}
```

### Node.js Application

#### For axios:
```javascript
// Axios automatically respects HTTP_PROXY
const axios = require('axios');

// Just run with:
// HTTP_PROXY=http://localhost:8091 node your-app.js
```

#### For fetch:
```javascript
const { HttpsProxyAgent } = require('https-proxy-agent');

const proxyAgent = new HttpsProxyAgent('http://localhost:8091');

fetch('https://api.example.com/data', {
    agent: proxyAgent
})
.then(res => res.json())
.then(data => console.log(data));
```

### Python Application

```python
import os
import requests

# requests library respects HTTP_PROXY automatically
response = requests.get('https://api.example.com/data')

# Or explicitly:
proxies = {
    'http': 'http://localhost:8091',
    'https': 'http://localhost:8091'
}
response = requests.get('https://api.example.com/data', proxies=proxies)
```

### Java Application

```java
// Set system properties
System.setProperty("http.proxyHost", "localhost");
System.setProperty("http.proxyPort", "8091");
System.setProperty("https.proxyHost", "localhost");
System.setProperty("https.proxyPort", "8091");

// Or run with:
// java -Dhttp.proxyHost=localhost -Dhttp.proxyPort=8091 YourApp
```

## Testing Your Setup

### 1. Start the Capture System
```bash
./orchestrate.sh
# Choose 1 (RECORD MODE)
```

### 2. Test with curl first
```bash
# This should be captured:
curl -x http://localhost:8091 https://jsonplaceholder.typicode.com/users
```

### 3. Check the viewer
Open http://localhost:8090/viewer and select "Live Captures" - you should see the curl request.

### 4. Run your app with proxy
```bash
# For Go
HTTP_PROXY=http://localhost:8091 HTTPS_PROXY=http://localhost:8091 go run your-app.go

# For Node
HTTP_PROXY=http://localhost:8091 HTTPS_PROXY=http://localhost:8091 node your-app.js

# For Python  
HTTP_PROXY=http://localhost:8091 HTTPS_PROXY=http://localhost:8091 python your-app.py
```

### 5. Make your app call external APIs
Trigger whatever functionality in your app makes external API calls.

### 6. Check the viewer
You should now see the OUTGOING API calls from your app to external services.

## Common Issues

### "Still seeing incoming calls"
Your app's HTTP client isn't using the proxy. Check:
1. Is HTTP_PROXY set in the app's environment?
2. Does your HTTP client library respect proxy settings?
3. Are you using a custom HTTP client that bypasses proxy?

### "No calls captured"
1. Your app might be using HTTPS and not respecting HTTPS_PROXY
2. Try setting: `export ALL_PROXY=http://localhost:8091`
3. Your app might be caching responses

### "Connection refused"
The proxy isn't running. Check with:
```bash
curl http://localhost:8091/capture/status
```

## Debug Mode

Add logging to see if your app is using the proxy:

```go
// Go example
transport := &http.Transport{
    Proxy: http.ProxyFromEnvironment,
}
transport.OnProxyConnectResponse = func(ctx context.Context, proxyURL *url.URL, connectReq *http.Request, connectRes *http.Response) error {
    log.Printf("Connected through proxy: %s", proxyURL)
    return nil
}
client := &http.Client{Transport: transport}
```

## Alternative: Middleware Approach

If you can't get the proxy working, add middleware to your app:

```go
// Capture middleware for your HTTP client
func captureMiddleware(next http.RoundTripper) http.RoundTripper {
    return http.RoundTripperFunc(func(req *http.Request) (*http.Response, error) {
        // Log the outgoing request
        log.Printf("Outgoing API call: %s %s", req.Method, req.URL)
        
        // Make the actual request
        resp, err := next.RoundTrip(req)
        
        // Log the response
        if err == nil {
            log.Printf("Response: %d", resp.StatusCode)
        }
        
        return resp, err
    })
}
```