# 🚀 Quick Start Guide - API Capture Proxy

## What This Does
Captures all HTTP/HTTPS API calls from your application and saves them for mocking/replay.

## Three Ways to Capture

### 1️⃣ **Easiest: Transparent Mode (No Certificates!)**
```bash
# Start the transparent capture system
./transparent-capture.sh start

# Run your app - ALL HTTPS will be captured automatically
./transparent-capture.sh run 'curl https://api.github.com'
./transparent-capture.sh run 'go run your-app.go'
./transparent-capture.sh run 'npm start'

# View captures at: http://localhost:8090/viewer
```
**Pros:** No certificates, no proxy settings, works with everything  
**Cons:** Requires Docker

---

### 2️⃣ **Simple: HTTP-Only Capture**
```bash
# Start the capture proxy
go run cmd/capture/main.go

# In another terminal, run your app with proxy
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
./your-app

# Save captures
curl http://localhost:8091/capture/save
```
**Pros:** No Docker needed, simple setup  
**Cons:** HTTPS shows connections only (not content)

---

### 3️⃣ **Full HTTPS with Certificates**
```bash
# Start MITM proxy with certificate generation
./start-https-capture.sh

# Copy the export commands it shows you:
export SSL_CERT_FILE=/path/to/certs/mitmproxy-ca.pem
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
./your-app
```
**Pros:** Full HTTPS decryption, works without containers  
**Cons:** Requires certificate trust

---

## Viewing Captured Data

1. **Web Viewer:** http://localhost:8090/viewer
2. **JSON Files:** Check `./captured/` directory
3. **Use as Mocks:** Copy files from `captured/` to `configs/`

## Requirements

- **For Transparent Mode:** Docker + Docker Compose
- **For Basic Mode:** Go 1.21+
- **For HTTPS Mode:** Docker

## First Time Setup

```bash
# Clone the repo
git clone https://github.com/yourusername/proxy-3.git
cd proxy-3

# For transparent mode (recommended)
chmod +x transparent-capture.sh
./transparent-capture.sh start

# For basic HTTP mode
go mod download
go run cmd/capture/main.go
```

## Common Use Cases

### Capture from a Go app
```bash
./transparent-capture.sh run 'go run main.go'
```

### Capture from Node.js
```bash
./transparent-capture.sh run 'npm start'
```

### Capture from Python
```bash
./transparent-capture.sh run 'python app.py'
```

### Capture from curl/wget
```bash
./transparent-capture.sh run 'curl https://api.example.com/data'
```

### Interactive testing
```bash
# Get a shell where ALL commands are captured
./transparent-capture.sh exec

# Now run any commands
curl https://api.github.com
wget https://example.com/api/data
# Everything is captured!
```

## Files You'll See

- `captured/` - Your captured API calls
- `configs/` - Mock server configurations  
- `viewer.html` - Web UI for viewing captures

## Need Help?

- Full docs: [README.md](README.md)
- Transparent mode: [docs/TRANSPARENT-MODE.md](docs/TRANSPARENT-MODE.md)
- HTTPS setup: [docs/MITM-SETUP.md](docs/MITM-SETUP.md)

## Quick Commands Reference

```bash
# Transparent mode (no certs needed!)
./transparent-capture.sh start|stop|run|exec|logs

# Basic HTTP capture
go run cmd/capture/main.go

# HTTPS with certs
./start-https-capture.sh

# View captures
open http://localhost:8090/viewer
```

That's it! Pick the method that works for your setup and start capturing!