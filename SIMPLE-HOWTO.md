# 🎯 Super Simple API Capture Guide

## The Easiest Way (No Docker, No Certificates!)

### 1. Start the Capture System
```bash
./orchestrate.sh
# Press 1 for RECORD MODE
```

### 2. Run Your App with Proxy
```bash
# In a new terminal:
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
./your-app
```

### 3. View What's Being Captured
Open browser: http://localhost:8090/viewer
Click "Live Captures"

### 4. Save Your Captures
In orchestrate menu, press 4 (or run: `curl http://localhost:8091/capture/save`)

**That's it!** ✅

---

## What You'll See

- ✅ All HTTP requests and responses
- ✅ Headers, bodies, query parameters
- ⚠️ HTTPS connections (but not decrypted content)

---

## If You Get Errors

### "Permission denied"
Run without Docker - just use `./orchestrate.sh`

### "Port already in use"
```bash
# Kill any running processes
pkill -f "cmd/main.go"
pkill -f "cmd/capture"
# Try again
```

### "Can't see HTTPS content"
This is normal! The basic proxy can't decrypt HTTPS. You'll see the connection was made but not the content.

---

## Alternative: Without orchestrate.sh

```bash
# Terminal 1 - Start capture proxy
CAPTURE_PORT=8091 TRANSPARENT_MODE=true go run cmd/capture/main.go

# Terminal 2 - Start viewer
PORT=8090 go run cmd/main.go

# Terminal 3 - Run your app
export HTTP_PROXY=http://localhost:8091
export HTTPS_PROXY=http://localhost:8091
./your-app
```

---

## Need to See HTTPS Content?

Only if you REALLY need to decrypt HTTPS:

1. Install Docker
2. Run: `docker-compose --profile mitm up`
3. Follow the MITM setup guide

But for most cases, the basic capture (above) is enough!