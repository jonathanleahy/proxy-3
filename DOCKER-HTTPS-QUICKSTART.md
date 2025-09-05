# 🔒 Docker HTTPS Capture (No Admin Needed!)

## Quick Fix for Your Docker Issues

### Step 1: Start mitmproxy Container
```bash
# Simple one-liner that should work:
docker run -d --name mitm-proxy -p 8080:8080 -v $(pwd)/captured:/captured -v $(pwd)/scripts:/scripts mitmproxy/mitmproxy mitmdump -s /scripts/mitm_capture.py

# Or if you prefer docker-compose:
docker-compose --profile mitm up -d
```

### Step 2: Get the Certificate (Fixed Method)
```bash
# Create certs directory
mkdir -p certs

# Wait a few seconds for mitmproxy to generate certs
sleep 5

# Extract directly from running container
docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem

# Verify it worked
ls -la certs/mitmproxy-ca.pem
```

### Step 3: Run Your App (No Admin!)
```bash
# Set the certificate path (no admin needed!)
export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem

# Set proxy
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080

# Run your app - HTTPS will be fully captured!
./your-app
```

### Step 4: View Captured HTTPS Content
```bash
# Check captures were saved
ls -la captured/

# View in browser (start viewer if needed)
docker-compose up mock-server -d
open http://localhost:8090/viewer
```

---

## If Docker Compose Fails

Use standalone Docker commands instead:

```bash
# 1. Run mitmproxy
docker run -d \
  --name mitm-proxy \
  -p 8080:8080 \
  -v $(pwd)/captured:/captured \
  -v $(pwd)/scripts:/scripts \
  mitmproxy/mitmproxy \
  mitmdump -s /scripts/mitm_capture.py

# 2. Run mock server for viewer
docker run -d \
  --name mock-server \
  -p 8090:8090 \
  -v $(pwd)/configs:/app/configs \
  -v $(pwd)/captured:/app/captured \
  -v $(pwd)/viewer.html:/app/viewer.html \
  golang:1.21-alpine \
  sh -c "cd /app && go run cmd/main.go"
```

---

## Testing It Works

```bash
# Test HTTPS capture with curl
curl --cacert certs/mitmproxy-ca.pem \
     -x http://localhost:8080 \
     https://api.github.com/user

# You should see the request in:
# - Terminal logs
# - captured/ directory
# - Web viewer at http://localhost:8090/viewer
```

---

## Common Fixes

### "ca-certificates not found"
Already fixed - we removed that dependency

### "Permission denied"
```bash
# Make sure Docker is running
docker ps

# Make scripts executable
chmod +x scripts/*.sh
chmod +x scripts/*.py
```

### "Certificate not found"
```bash
# Make sure container is running
docker ps | grep mitm

# Try extracting again
docker cp mitm-proxy:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem certs/mitmproxy-ca.pem
```

### "HTTPS not being captured"
```bash
# Verify environment variables are set
echo $SSL_CERT_FILE
echo $HTTP_PROXY
echo $HTTPS_PROXY

# Make sure they point to the right places
```

---

## What You Get

With this setup, you can capture:
- ✅ Full HTTPS request bodies (decrypted!)
- ✅ Full HTTPS response bodies (decrypted!)
- ✅ All headers including auth tokens
- ✅ Cookies and sessions
- ✅ Everything, even encrypted traffic!

All without admin rights - just Docker and environment variables!