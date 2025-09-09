# Why Go Apps Don't Use Proxy Settings Automatically

## The Problem
Go's `http.Client{}` creates a client that **completely ignores** proxy environment variables. This is by design in Go.

## What Works vs What Doesn't

### ❌ DOESN'T WORK (most Go apps):
```go
client := &http.Client{}
resp, err := client.Get("https://api.example.com")
// This IGNORES HTTP_PROXY/HTTPS_PROXY environment variables!
```

### ✅ WORKS (but most apps don't do this):
```go
// Option 1: Use default transport
resp, err := http.Get("https://api.example.com")
// This uses http.DefaultTransport which DOES respect proxy env vars

// Option 2: Explicitly enable proxy
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment,
    },
}
```

## The Reality

**If you can't modify the Go app's source code, you CANNOT force it to use a proxy via environment variables.**

This is different from:
- Python (requests library auto-uses proxy env vars)
- Node.js (many libraries auto-use proxy env vars)  
- curl (auto-uses proxy env vars)
- wget (auto-uses proxy env vars)

## Your Options

1. **Modify the Go app** - Add proxy support to the HTTP client
2. **Use transparent proxy with iptables** - But this requires root and is complex
3. **Use a different monitoring tool** - Like tcpdump or Wireshark
4. **Ask the app developer** - To add proxy support

## Why This Is So Frustrating

The Docker proxy solution works perfectly for:
- Python apps
- Node.js apps  
- Java apps
- Ruby apps
- Shell scripts using curl/wget

But NOT for Go apps that use `&http.Client{}` without proxy configuration.

## The Simplest Fix (if you can modify code)

Add these 3 lines to the Go app:
```go
import "net/http"
import "net/url"

proxyURL, _ := url.Parse("http://localhost:8084")
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyURL(proxyURL),
    },
}
```

That's it. Without code changes, standard Go apps won't use the proxy.