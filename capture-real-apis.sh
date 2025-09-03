#!/bin/bash

echo "==================================="
echo "API Response Capture Tool"
echo "==================================="
echo ""
echo "This tool will capture real API responses and convert them to mock configs."
echo ""

MODE=${1:-proxy}

if [ "$MODE" == "intercept" ]; then
    echo "Mode: INTERCEPT - Modify your .env to point APIs through the capture proxy"
    echo ""
    echo "Add these to your .env file on the machine with real API access:"
    echo ""
    echo "# Original API URLs (save these first!)"
    echo "# ACCOUNTS_API_URL=https://api-accounts.example.com"
    echo "# ACCOUNTS_CORE_API_URL=https://accounts-core-api.example.com"
    echo "# WALLET_API_URL=https://cards-api.example.com"
    echo "# LEDGER_API_API_URL=https://api-ledger.example.com"
    echo "# STATEMENTS_API_V2_URL=https://statements-api.example.com"
    echo "# AUTHORISATIONS_API_URL=https://api-authorizations.example.com"
    echo ""
    echo "# Capture proxy URLs"
    echo "ACCOUNTS_API_URL=http://localhost:8091/accounts"
    echo "ACCOUNTS_CORE_API_URL=http://localhost:8091/accounts-core"
    echo "WALLET_API_URL=http://localhost:8091/wallet"
    echo "LEDGER_API_API_URL=http://localhost:8091/ledger"
    echo "STATEMENTS_API_V2_URL=http://localhost:8091/statements"
    echo "AUTHORISATIONS_API_URL=http://localhost:8091/authorizations"
    echo ""
    echo "Then run the capture proxy with real API URLs as environment variables:"
    echo ""
    
    cat << 'EOF' > run-capture-proxy.sh
#!/bin/bash
export CAPTURE_PORT=8091
export OUTPUT_DIR=./captured

# Set these to the REAL API URLs
export ACCOUNTS_API_URL="https://api-accounts.example.com"
export ACCOUNTS_CORE_API_URL="https://accounts-core-api.example.com"
export WALLET_API_URL="https://cards-api.example.com"
export LEDGER_API_API_URL="https://api-ledger.example.com"
export STATEMENTS_API_V2_URL="https://statements-api.example.com"
export AUTHORISATIONS_API_URL="https://api-authorizations.example.com"

cd mock-api-server
go run cmd/capture/main.go
EOF
    chmod +x run-capture-proxy.sh
    echo "Created: run-capture-proxy.sh"
    echo ""
    echo "Steps:"
    echo "1. Run: ./run-capture-proxy.sh"
    echo "2. Update your app's .env with proxy URLs (shown above)"
    echo "3. Use the app normally to generate traffic"
    echo "4. Save captures: curl http://localhost:8091/capture/save"
    echo "5. Find JSON files in ./mock-api-server/captured/"

elif [ "$MODE" == "logging" ]; then
    echo "Mode: LOGGING - Add logging to your existing HTTP client"
    echo ""
    echo "Add this to internal/app/adapter/secondary/httpproxy/httpproxy.go:"
    echo ""
    cat << 'EOF'
// Add this function to capture responses
func (c *HTTPClientImpl) captureResponse(method, url string, statusCode int, responseBody []byte) {
    capture := map[string]interface{}{
        "method":      method,
        "path":        extractPath(url),
        "status":      statusCode,
        "response":    json.RawMessage(responseBody),
        "captured_at": time.Now(),
    }
    
    // Save to file
    captureDir := os.Getenv("CAPTURE_DIR")
    if captureDir == "" {
        captureDir = "./captured"
    }
    
    os.MkdirAll(captureDir, 0755)
    filename := fmt.Sprintf("%s/capture_%d.json", captureDir, time.Now().Unix())
    
    data, _ := json.MarshalIndent(capture, "", "  ")
    os.WriteFile(filename, data, 0644)
}

// Call this in the DoRequest method after getting response:
// c.captureResponse(req.Method, req.URL.String(), resp.StatusCode, bodyBytes)
EOF
    echo ""
    echo "Then set CAPTURE_DIR environment variable when running the app:"
    echo "CAPTURE_DIR=./captured make run-api"

else
    echo "Usage: ./capture-real-apis.sh [intercept|logging]"
    echo ""
    echo "  intercept - Run a proxy server to capture API calls"
    echo "  logging   - Add logging to existing code"
fi

echo ""
echo "==================================="
echo "Converting Captured Data"
echo "==================================="
echo ""
echo "After capturing, the JSON files can be directly used by the mock server."
echo "Just copy them to ./mock-api-server/configs/"
echo ""
echo "The captured format is already compatible with the mock server!"