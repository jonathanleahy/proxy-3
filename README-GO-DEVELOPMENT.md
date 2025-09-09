# Go Development with Trusted HTTPS Capture

🐹 **Develop Go applications with full HTTPS traffic capture - no `InsecureSkipVerify` needed!**

## ✨ Features

- **🔐 Trusted Certificates**: No `InsecureSkipVerify` required in your Go code
- **📦 Persistent Module Cache**: Download dependencies once, use forever
- **🕵️ Full HTTPS Capture**: See complete request/response bodies
- **⚡ Fast Development**: Quick container startup with cached modules
- **🛡️ Multiple Fallback Options**: Works in any Docker environment

## 🚀 Quick Start

### Option 1: All-in-One Go Development (Recommended)

```bash
# Set up everything for Go development
./GO-DEV-WITH-TRUSTED-CERTS.sh ~/temp/aa/cmd/api

# Start development container
./run-go-dev.sh

# In the container, run your app
go run cmd/api/main.go

# Monitor captures (in another terminal)
./monitor-captures.sh
```

### Option 2: Use Existing Certificate Trust Solutions

```bash
# Fast setup (best for most cases)
./FAST-CERT-TRUST.sh

# Or bulletproof setup (handles package issues)
./BULLETPROOF-CERT-TRUST.sh

# Or complete solution (all features)
./COMPLETE-TRUST-SOLUTION.sh
```

## 🎯 Your Go Code Requirements

### With Trusted Certificates (Recommended)
```go
// No special configuration needed!
client := &http.Client{}
resp, err := client.Get("https://api.example.com")
```

### With Environment Proxy (Alternative)
```go
client := &http.Client{
    Transport: &http.Transport{
        Proxy: http.ProxyFromEnvironment, // Uses HTTP_PROXY env var
        // No InsecureSkipVerify needed with trusted certs!
    },
}
```

## 📋 Available Solutions

### 🐹 Go Development Solutions
- **`GO-DEV-WITH-TRUSTED-CERTS.sh`** - Complete Go dev environment
- **`run-go-dev.sh`** - Start development container (auto-generated)
- **`monitor-captures.sh`** - Monitor HTTPS captures (auto-generated)

### 🔐 Certificate Trust Solutions
- **`COMPLETE-TRUST-SOLUTION.sh`** - Full-featured comprehensive solution
- **`BULLETPROOF-CERT-TRUST.sh`** - Multiple fallbacks for APK issues
- **`FAST-CERT-TRUST.sh`** - Speed-optimized avoiding slow networks
- **`FIX-PACKAGE-ERRORS.sh`** - Resolves curl/ca-certificates errors

### 🐳 Docker Container Options
- **22 specialized Dockerfiles** for different environments
- **Alpine variants**: 3.19, 3.22, latest, minimal, robust
- **Ubuntu/Debian**: Fast alternatives to Alpine
- **Go-specific**: Optimized for Go development
- **Official images**: Guaranteed compatibility

## 🔧 Advanced Usage

### Custom Go Application Path
```bash
./GO-DEV-WITH-TRUSTED-CERTS.sh ~/my-go-project
```

### Development Workflow
```bash
# 1. Set up environment (one time)
./GO-DEV-WITH-TRUSTED-CERTS.sh ~/temp/aa

# 2. Start development container
./run-go-dev.sh

# 3. In container: develop your app
go mod tidy           # Download/update dependencies (cached)
go run cmd/api/main.go    # Run your application
go build cmd/api/main.go  # Build your application
go test ./...         # Run tests

# 4. Monitor captures in another terminal
./monitor-captures.sh
```

### Persistent Caching
Your Go modules and build cache are stored in Docker volumes:
- **`go-dev-cache`** - Go build cache (`GOCACHE`)
- **`go-dev-modules`** - Go module cache (`GOMODCACHE`)

Dependencies are downloaded once and reused across container restarts.

## 🛠️ Troubleshooting

### Package Installation Issues
```bash
# If Alpine packages fail
./FIX-PACKAGE-ERRORS.sh

# Use Ubuntu-based solution
./BULLETPROOF-CERT-TRUST.sh
```

### Slow Network Issues
```bash
# Bypass slow apt-get
./FAST-CERT-TRUST.sh
```

### Certificate Trust Issues
```bash
# Clean setup with certificate verification
./COMPLETE-TRUST-SOLUTION.sh
```

## 📊 What Gets Captured

All HTTP/HTTPS traffic from your Go application:
- **Request headers and bodies**
- **Response headers and bodies**  
- **JSON payloads**
- **Form data**
- **Query parameters**
- **Authentication tokens**

## 🔍 Viewing Captures

### Real-time Monitoring
```bash
./monitor-captures.sh
# or
docker logs -f mitmproxy
```

### Captured Files
- **Location**: `./captured/` directory
- **Format**: JSON files organized by service
- **Content**: Complete request/response data

## 🌟 Benefits Over Main Branch

| Feature | Main Branch | This Branch |
|---------|-------------|-------------|
| **Certificate Trust** | ❌ Requires `--insecure` | ✅ Automatic trust |
| **Go Code Changes** | ❌ Needs `InsecureSkipVerify` | ✅ No changes needed |
| **Module Downloads** | ❌ Every container restart | ✅ Cached permanently |
| **Package Issues** | ❌ Manual fixes | ✅ Multiple fallbacks |
| **Network Issues** | ❌ Manual troubleshooting | ✅ Automatic alternatives |

## 📚 Examples

### Basic Go HTTP Client
```go
package main

import (
    "fmt"
    "io"
    "net/http"
)

func main() {
    // Works automatically with trusted certificates!
    resp, err := http.Get("https://api.github.com/users/octocat")
    if err != nil {
        panic(err)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("Response: %s\n", body)
}
```

### Custom HTTP Client
```go
package main

import (
    "fmt"
    "net/http"
    "os"
)

func main() {
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment, // Optional: uses HTTP_PROXY if set
            // No TLS config needed - certificates are trusted!
        },
    }
    
    resp, err := client.Get("https://api.example.com/data")
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    fmt.Printf("Status: %s\n", resp.Status)
}
```

## 🎯 Migration from Main Branch

### Before (Main Branch)
```go
// Required InsecureSkipVerify
client := &http.Client{
    Transport: &http.Transport{
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: true, // ❌ Security risk
        },
    },
}
```

### After (This Branch)
```go
// Clean, secure code
client := &http.Client{} // ✅ Certificates trusted automatically
```

## 🔗 Integration with Existing Tools

### Docker Compose
The certificate trust solutions work alongside existing `docker-compose.yml` files.

### CI/CD Pipelines
Use the containerized solutions in CI/CD for API testing and debugging.

### IDE Integration
Mount your source code and use your favorite IDE while the container handles the runtime environment.

## 📞 Support

If you encounter issues:
1. Try different solutions in order: `FAST-CERT-TRUST.sh` → `BULLETPROOF-CERT-TRUST.sh` → `COMPLETE-TRUST-SOLUTION.sh`
2. Check the specific error handling scripts: `FIX-PACKAGE-ERRORS.sh`, `FIX-APK-PACKAGES.sh`
3. Use the 22 different Docker variants for your specific environment

---

**🎉 Happy Go Development with Trusted HTTPS Capture!** 🐹