package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type CapturedRoute struct {
	Method      string                 `json:"method"`
	Path        string                 `json:"path"`
	Status      int                    `json:"status"`
	Response    interface{}            `json:"response"`
	Headers     map[string]string      `json:"headers"` // Keep for backward compatibility
	Description string                 `json:"description"`
	CapturedAt  time.Time              `json:"captured_at"`
	RequestBody interface{}            `json:"request_body,omitempty"`
	// Extended capture details (won't break playback)
	FullURL         string                 `json:"full_url,omitempty"`
	ResponseHeaders map[string]string      `json:"response_headers,omitempty"`
	RequestHeaders  map[string]string      `json:"request_headers,omitempty"`
	QueryParams     map[string]string      `json:"query_params,omitempty"`
	ResponseTime    int64                  `json:"response_time_ms,omitempty"`
	Host            string                 `json:"host,omitempty"`
}

type CaptureProxy struct {
	targetHosts map[string]*url.URL
	captures    []CapturedRoute
	mu          sync.Mutex
	outputDir   string
	client      *http.Client
}

func NewCaptureProxy(outputDir string) *CaptureProxy {
	// Create HTTP client that handles HTTPS
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	
	return &CaptureProxy{
		targetHosts: make(map[string]*url.URL),
		captures:    make([]CapturedRoute, 0),
		outputDir:   outputDir,
		client: &http.Client{
			Transport: tr,
			Timeout:   30 * time.Second,
		},
	}
}

func (cp *CaptureProxy) AddTarget(name string, targetURL string) error {
	u, err := url.Parse(targetURL)
	if err != nil {
		return err
	}
	cp.targetHosts[name] = u
	log.Printf("Added target: %s -> %s", name, targetURL)
	return nil
}

func (cp *CaptureProxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received request: %s %s", r.Method, r.URL.String())
	
	// Handle CONNECT method for HTTPS tunneling
	if r.Method == "CONNECT" {
		cp.handleConnect(w, r)
		return
	}
	
	transparentMode := os.Getenv("TRANSPARENT_MODE") == "true"
	
	var targetURL string
	var serviceName string
	
	if transparentMode {
		// In transparent mode, forward to the actual destination
		if r.URL.IsAbs() {
			// Absolute URL (proxy request)
			targetURL = r.URL.String()
			serviceName = r.URL.Host
		} else {
			// Relative URL - shouldn't happen in proxy mode
			http.Error(w, "Invalid proxy request", http.StatusBadRequest)
			return
		}
		
		log.Printf("Transparent proxy: %s %s", r.Method, targetURL)
	} else {
		// Original configured mode
		http.Error(w, "Non-transparent mode not supported in this version", http.StatusBadRequest)
		return
	}
	
	// Track request start time
	startTime := time.Now()
	
	// Parse the URL to extract query parameters
	parsedURL, _ := url.Parse(targetURL)
	queryParams := make(map[string]string)
	for key, values := range parsedURL.Query() {
		if len(values) > 0 {
			queryParams[key] = values[0]
		}
	}
	
	// Capture request headers
	requestHeaders := make(map[string]string)
	for key, values := range r.Header {
		if len(values) > 0 && !strings.HasPrefix(key, "Proxy-") {
			requestHeaders[key] = values[0]
		}
	}
	
	// Create new request to forward
	proxyReq, err := http.NewRequest(r.Method, targetURL, r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	
	// Copy headers from original request
	for key, values := range r.Header {
		for _, value := range values {
			proxyReq.Header.Add(key, value)
		}
	}
	
	// Remove hop-by-hop headers
	proxyReq.Header.Del("Proxy-Connection")
	proxyReq.Header.Del("Proxy-Authenticate")
	proxyReq.Header.Del("Proxy-Authorization")
	proxyReq.Header.Del("Connection")
	
	// Capture request body if present
	var requestBody interface{}
	if r.Method == "POST" || r.Method == "PUT" || r.Method == "PATCH" {
		if r.Body != nil {
			bodyBytes, _ := io.ReadAll(r.Body)
			r.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
			proxyReq.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
			
			// Try to parse as JSON
			var reqBody interface{}
			if json.Unmarshal(bodyBytes, &reqBody) == nil {
				requestBody = reqBody
			} else if len(bodyBytes) > 0 {
				// If not JSON, store as string
				requestBody = string(bodyBytes)
			}
		}
	}
	
	// Make the request
	resp, err := cp.client.Do(proxyReq)
	if err != nil {
		log.Printf("Error forwarding request: %v", err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	
	// Read response body
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	
	// Calculate response time
	responseTime := time.Since(startTime).Milliseconds()
	
	// Capture response headers
	responseHeaders := make(map[string]string)
	for key, values := range resp.Header {
		if len(values) > 0 {
			responseHeaders[key] = values[0]
		}
	}
	
	// Try to parse response body
	var responseBody interface{}
	var jsonBody interface{}
	if err := json.Unmarshal(respBody, &jsonBody); err == nil {
		responseBody = jsonBody
	} else if len(respBody) > 0 {
		// If not JSON, store as string (truncate if too long)
		bodyStr := string(respBody)
		if len(bodyStr) > 10000 {
			bodyStr = bodyStr[:10000] + "... (truncated)"
		}
		responseBody = bodyStr
	}
	
	// Always capture the request/response, even if not JSON
	captured := CapturedRoute{
		Method:      r.Method,
		Path:        normalizePathForTemplate(parsedURL.Path),
		Status:      resp.StatusCode,
		Response:    responseBody,
		Headers:     responseHeaders, // For backward compatibility
		Description: fmt.Sprintf("Captured from %s", serviceName),
		CapturedAt:  time.Now(),
		RequestBody: requestBody,
		// Extended details
		FullURL:         targetURL,
		ResponseHeaders: responseHeaders,
		RequestHeaders:  requestHeaders,
		QueryParams:     queryParams,
		ResponseTime:    responseTime,
		Host:            parsedURL.Host,
	}
	
	cp.mu.Lock()
	cp.captures = append(cp.captures, captured)
	cp.mu.Unlock()
	
	log.Printf("✅ Captured: %s %s -> %d (%dms)", r.Method, parsedURL.Path, resp.StatusCode, responseTime)
	
	// Copy response headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	
	// Write status code
	w.WriteHeader(resp.StatusCode)
	
	// Write response body
	w.Write(respBody)
}

func normalizePathForTemplate(path string) string {
	parts := strings.Split(path, "/")
	for i, part := range parts {
		if isNumeric(part) || isUUID(part) || (len(part) > 10 && !strings.Contains(part, "-")) {
			parts[i] = "{id}"
		} else if strings.HasPrefix(part, "CUST-") || strings.HasPrefix(part, "ACC-") {
			parts[i] = "{id}"
		}
	}
	return strings.Join(parts, "/")
}

func isNumeric(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(s) > 0
}

func isUUID(s string) bool {
	return len(s) == 36 && strings.Count(s, "-") == 4
}

func (cp *CaptureProxy) SaveCaptures() error {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	if len(cp.captures) == 0 {
		return fmt.Errorf("no captures to save")
	}

	groupedByService := make(map[string][]CapturedRoute)
	for _, capture := range cp.captures {
		service := extractServiceName(capture.Path)
		groupedByService[service] = append(groupedByService[service], capture)
	}

	os.MkdirAll(cp.outputDir, 0755)

	for service, routes := range groupedByService {
		filename := filepath.Join(cp.outputDir, fmt.Sprintf("%s-captured.json", service))
		
		output := map[string][]CapturedRoute{
			"routes": routes,
		}

		data, err := json.MarshalIndent(output, "", "  ")
		if err != nil {
			return err
		}

		if err := os.WriteFile(filename, data, 0644); err != nil {
			return err
		}

		log.Printf("Saved %d routes to %s", len(routes), filename)
	}

	combinedFile := filepath.Join(cp.outputDir, "all-captured.json")
	allRoutes := map[string][]CapturedRoute{
		"routes": cp.captures,
	}

	data, err := json.MarshalIndent(allRoutes, "", "  ")
	if err != nil {
		return err
	}

	if err := os.WriteFile(combinedFile, data, 0644); err != nil {
		return err
	}

	log.Printf("Saved all %d captures to %s", len(cp.captures), combinedFile)
	
	cp.captures = make([]CapturedRoute, 0)
	
	return nil
}

func extractServiceName(path string) string {
	if strings.Contains(path, "/accounts") {
		return "accounts"
	} else if strings.Contains(path, "/customers") {
		return "customers"
	} else if strings.Contains(path, "/cards") || strings.Contains(path, "/wallet") {
		return "cards"
	} else if strings.Contains(path, "/ledger") {
		return "ledger"
	} else if strings.Contains(path, "/statements") {
		return "statements"
	} else if strings.Contains(path, "/authorizations") {
		return "authorizations"
	} else if strings.Contains(path, "/users") {
		return "users"
	} else if strings.Contains(path, "/posts") {
		return "posts"
	}
	return "misc"
}

// handleConnect handles CONNECT method for HTTPS tunneling
func (cp *CaptureProxy) handleConnect(w http.ResponseWriter, r *http.Request) {
	log.Printf("🔒 CONNECT tunnel requested for: %s", r.Host)
	
	// Establish connection to the target
	targetConn, err := net.Dial("tcp", r.Host)
	if err != nil {
		log.Printf("Error connecting to %s: %v", r.Host, err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer targetConn.Close()
	
	// Hijack the connection first
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}
	
	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer clientConn.Close()
	
	// Send 200 Connection Established response
	clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	
	// Capture request headers
	requestHeaders := make(map[string]string)
	for key, values := range r.Header {
		if len(values) > 0 && !strings.HasPrefix(key, "Proxy-") {
			requestHeaders[key] = values[0]
		}
	}
	
	// Log that we're tunneling HTTPS (can't capture content without MITM)
	cp.mu.Lock()
	cp.captures = append(cp.captures, CapturedRoute{
		Method:      "CONNECT",
		Path:        r.Host,
		Status:      200,
		Response:    map[string]string{"note": "HTTPS tunnel established", "info": "Content not captured (encrypted). Use MITM proxy for full capture."},
		Headers:     map[string]string{"Connection": "Established"},
		Description: fmt.Sprintf("HTTPS tunnel to %s", r.Host),
		CapturedAt:  time.Now(),
		// Extended details
		FullURL:         "https://" + r.Host,
		ResponseHeaders: map[string]string{"Connection": "Established"},
		RequestHeaders:  requestHeaders,
		Host:            r.Host,
	})
	cp.mu.Unlock()
	
	log.Printf("✅ HTTPS tunnel established to %s (content not captured)", r.Host)
	
	// Start bidirectional copy
	go io.Copy(targetConn, clientConn)
	io.Copy(clientConn, targetConn)
}

func main() {
	port := os.Getenv("CAPTURE_PORT")
	if port == "" {
		port = "8091"
	}

	outputDir := os.Getenv("OUTPUT_DIR")
	if outputDir == "" {
		outputDir = "./captured"
	}

	transparentMode := os.Getenv("TRANSPARENT_MODE") == "true"

	proxy := NewCaptureProxy(outputDir)

	if transparentMode {
		log.Println("🔍 TRANSPARENT MODE ENABLED")
		log.Println("The proxy will automatically detect and forward to actual destinations")
		log.Println("No configuration needed - all HTTP/HTTPS traffic will be captured")
	} else {
		// Only configure specific targets if not in transparent mode
		if accountsAPI := os.Getenv("ACCOUNTS_API_URL"); accountsAPI != "" {
			proxy.AddTarget("accounts", accountsAPI)
		}
		if accountsCoreAPI := os.Getenv("ACCOUNTS_CORE_API_URL"); accountsCoreAPI != "" {
			proxy.AddTarget("accounts-core", accountsCoreAPI)
		}
		if walletAPI := os.Getenv("WALLET_API_URL"); walletAPI != "" {
			proxy.AddTarget("wallet", walletAPI)
		}
		if ledgerAPI := os.Getenv("LEDGER_API_API_URL"); ledgerAPI != "" {
			proxy.AddTarget("ledger", ledgerAPI)
		}
		if statementsAPI := os.Getenv("STATEMENTS_API_V2_URL"); statementsAPI != "" {
			proxy.AddTarget("statements", statementsAPI)
		}
		if authAPI := os.Getenv("AUTHORISATIONS_API_URL"); authAPI != "" {
			proxy.AddTarget("authorizations", authAPI)
		}

		if defaultTarget := os.Getenv("DEFAULT_TARGET"); defaultTarget != "" {
			proxy.AddTarget("default", defaultTarget)
		}
	}

	// Create a custom mux
	mux := http.NewServeMux()
	
	mux.HandleFunc("/capture/save", func(w http.ResponseWriter, r *http.Request) {
		if err := proxy.SaveCaptures(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Write([]byte("Captures saved successfully\n"))
	})

	mux.HandleFunc("/capture/status", func(w http.ResponseWriter, r *http.Request) {
		proxy.mu.Lock()
		count := len(proxy.captures)
		proxy.mu.Unlock()
		
		response := map[string]interface{}{
			"captured_routes": count,
			"output_dir":      outputDir,
		}
		json.NewEncoder(w).Encode(response)
	})

	mux.HandleFunc("/capture/live", func(w http.ResponseWriter, r *http.Request) {
		proxy.mu.Lock()
		captures := make([]CapturedRoute, len(proxy.captures))
		copy(captures, proxy.captures)
		proxy.mu.Unlock()
		
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"routes": captures,
			"count":  len(captures),
		})
	})
	
	mux.HandleFunc("/capture/clear", func(w http.ResponseWriter, r *http.Request) {
		proxy.mu.Lock()
		proxy.captures = make([]CapturedRoute, 0)
		proxy.mu.Unlock()
		
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Write([]byte("Captures cleared successfully\n"))
		log.Println("🗑️  Captures cleared")
	})

	// Custom handler that checks path before delegating
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// If it's a capture endpoint, use the mux
		if strings.HasPrefix(r.URL.Path, "/capture/") {
			mux.ServeHTTP(w, r)
		} else {
			// Otherwise use the proxy
			proxy.ServeHTTP(w, r)
		}
	})

	log.Printf("Capture Proxy starting on port %s", port)
	log.Printf("Output directory: %s", outputDir)
	log.Println("Configure your app to use this proxy by setting API URLs to http://localhost:" + port)
	log.Println("Save captures: curl http://localhost:" + port + "/capture/save")
	log.Println("Check status: curl http://localhost:" + port + "/capture/status")
	
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}