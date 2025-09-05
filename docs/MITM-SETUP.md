# MITM Proxy Setup - Full HTTPS Content Capture

## Overview

This guide shows how to capture **full HTTPS content** (including encrypted request/response bodies) using mitmproxy in Docker. Perfect for restricted environments where you don't have admin access.

## Quick Start (Docker)

### 1. Start the MITM Proxy

```bash
# Start mitmproxy with Docker
docker-compose --profile mitm up

# Or run standalone
docker run -it -p 8080:8080 -v $(pwd)/captured:/captured -v $(pwd)/scripts:/scripts mitmproxy/mitmproxy mitmdump -s /scripts/mitm_capture.py
```

### 2. Extract the CA Certificate (No Admin Required!)

```bash
# Run our helper script
./scripts/get-mitm-cert.sh

# This creates certs/mitmproxy-ca.pem
```

### 3. Use the Proxy

#### Option A: With curl (No Admin Required)
```bash
# Tell curl to trust our CA certificate
curl --cacert certs/mitmproxy-ca.pem -x http://localhost:8080 https://api.github.com/user

# Or set environment variable
export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem
curl -x http://localhost:8080 https://api.github.com/user
```

#### Option B: With Go Apps (No Admin Required)
```bash
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem
go run your-app.go
```

#### Option C: With Node.js Apps (No Admin Required)
```bash
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
export NODE_EXTRA_CA_CERTS=$(pwd)/certs/mitmproxy-ca.pem
node your-app.js
```

#### Option D: With Python Apps (No Admin Required)
```bash
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
export REQUESTS_CA_BUNDLE=$(pwd)/certs/mitmproxy-ca.pem
python your-app.py
```

## What Gets Captured

With MITM proxy, you get **EVERYTHING**:

- ✅ Full request bodies (even for HTTPS)
- ✅ Full response bodies (decrypted)
- ✅ All headers (request and response)
- ✅ Query parameters
- ✅ Response times
- ✅ Cookies and authentication tokens
- ✅ WebSocket traffic
- ✅ Binary data

## Viewing Captures

### Option 1: Web Viewer
```bash
# Start the mock server if not running
docker-compose up mock-server

# Open viewer
open http://localhost:8090/viewer

# Select "Captured" to see saved files
```

### Option 2: JSON Files
```bash
# Captures are saved to
ls -la captured/mitm_captured_*.json
ls -la captured/all-captured.json  # Latest captures
```

## Comparison: MITM vs CONNECT Proxy

| Feature | CONNECT Proxy (Port 8091) | MITM Proxy (Port 8080) |
|---------|---------------------------|------------------------|
| HTTPS Support | ✅ Yes | ✅ Yes |
| See HTTPS Content | ❌ No (encrypted) | ✅ Yes (decrypted) |
| Certificates Needed | ❌ No | ✅ Yes (but we handle it) |
| Admin Rights | ❌ Not required | ❌ Not required* |
| Speed | Fast | Slightly slower |
| Security Warning | None | Browser warnings** |

*Using environment variables
**Unless CA is trusted system-wide

## No Admin? No Problem!

For restricted environments without admin access:

### 1. Use Environment Variables
```bash
# Create a script: setup-mitm-env.sh
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem
export REQUESTS_CA_BUNDLE=$(pwd)/certs/mitmproxy-ca.pem
export NODE_EXTRA_CA_CERTS=$(pwd)/certs/mitmproxy-ca.pem

# Source it before running your app
source setup-mitm-env.sh
your-app
```

### 2. Application-Specific Trust
Most applications respect these environment variables without needing system-wide CA installation:
- `SSL_CERT_FILE` - Generic SSL certificate bundle
- `REQUESTS_CA_BUNDLE` - Python requests library
- `NODE_EXTRA_CA_CERTS` - Node.js
- `CURL_CA_BUNDLE` - curl command

### 3. Docker-Only Approach
Run your application inside Docker where the CA is pre-trusted:
```bash
docker run --rm -it \
  -v $(pwd)/certs/mitmproxy-ca.pem:/usr/local/share/ca-certificates/mitmproxy.crt \
  -e HTTP_PROXY=http://host.docker.internal:8080 \
  -e HTTPS_PROXY=http://host.docker.internal:8080 \
  your-app-image
```

## Troubleshooting

### "Certificate verify failed"
- Make sure you've extracted the CA: `./scripts/get-mitm-cert.sh`
- Verify the cert exists: `ls -la certs/mitmproxy-ca.pem`
- Set the environment variable: `export SSL_CERT_FILE=$(pwd)/certs/mitmproxy-ca.pem`

### "Connection refused on port 8080"
- Start the proxy: `docker-compose --profile mitm up`
- Check it's running: `docker ps | grep mitm`

### "Not capturing HTTPS content"
- Make sure you're using port 8080 (MITM) not 8091 (CONNECT)
- Verify proxy settings: `echo $HTTP_PROXY $HTTPS_PROXY`

### "Browser shows security warning"
This is normal for MITM. Options:
1. Click "Advanced" → "Proceed anyway" (for testing only!)
2. Import the CA cert into your browser (requires browser settings access)
3. Use curl/applications with the CA cert file instead

## Security Warning

⚠️ **IMPORTANT**: MITM proxy can see ALL traffic including passwords and tokens!
- Only use for development/testing
- Never use on production traffic
- Don't share the CA certificate
- Delete the CA cert when done: `rm -rf certs/`

## Advanced Features

### Custom Filtering
Edit `scripts/mitm_capture.py` to:
- Filter specific hosts
- Modify requests/responses
- Add custom headers
- Block certain requests

### Concurrent Capture
Run both proxies simultaneously:
```bash
# Terminal 1: CONNECT proxy (port 8091) - for non-sensitive traffic
./orchestrate.sh

# Terminal 2: MITM proxy (port 8080) - for full HTTPS inspection
docker-compose --profile mitm up
```

### Export for Postman/Insomnia
The captured format is compatible with most API tools:
```bash
# Convert to Postman collection (you'd need to write a converter)
cat captured/all-captured.json | jq '.routes[] | {method, path, headers, body: .request_body}'
```

## Summary

- **Easy**: Docker-based, no compilation needed
- **Powerful**: Full HTTPS decryption and capture
- **Flexible**: Works without admin rights using env vars
- **Compatible**: Same output format as the Go proxy

Choose based on your needs:
- Use **CONNECT proxy (8091)** for basic capture without certificates
- Use **MITM proxy (8080)** for full HTTPS content inspection