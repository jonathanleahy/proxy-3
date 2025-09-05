package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
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
	Headers     map[string]string      `json:"headers"`
	Description string                 `json:"description"`
	CapturedAt  time.Time              `json:"captured_at"`
	RequestBody interface{}            `json:"request_body,omitempty"`
}

type CaptureProxy struct {
	targetHosts map[string]*url.URL
	captures    []CapturedRoute
	mu          sync.Mutex
	outputDir   string
}

func NewCaptureProxy(outputDir string) *CaptureProxy {
	return &CaptureProxy{
		targetHosts: make(map[string]*url.URL),
		captures:    make([]CapturedRoute, 0),
		outputDir:   outputDir,
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
	var targetURL *url.URL
	var serviceName string

	// Check if we're in transparent mode
	transparentMode := os.Getenv("TRANSPARENT_MODE") == "true"
	
	if transparentMode {
		// In transparent mode, extract the actual destination from the request
		// The request URL contains the full destination
		if r.URL.Scheme == "" {
			r.URL.Scheme = "http"
		}
		if r.URL.Host == "" {
			// For CONNECT method or when Host is in header
			r.URL.Host = r.Host
		}
		
		// Build target URL from the request
		targetURL = &url.URL{
			Scheme: r.URL.Scheme,
			Host:   r.URL.Host,
			Path:   "/",
		}
		
		// If it's a proxy request, the full URL is already in r.URL
		if r.URL.Scheme != "" && r.URL.Host != "" {
			targetURL = r.URL
		}
		
		serviceName = r.URL.Host
		log.Printf("Transparent proxy: forwarding to %s%s", r.URL.Host, r.URL.Path)
	} else {
		// Original behavior - use configured targets
		for name, target := range cp.targetHosts {
			if strings.Contains(r.Host, name) || strings.Contains(r.URL.Path, "/"+name+"/") {
				targetURL = target
				serviceName = name
				break
			}
		}

		if targetURL == nil {
			targetURL = cp.targetHosts["default"]
			serviceName = "default"
		}

		if targetURL == nil {
			http.Error(w, "No target configured", http.StatusBadGateway)
			return
		}
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)
	
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		if transparentMode {
			// In transparent mode, preserve the original request
			req.URL = r.URL
			req.Host = r.Host
			
			// Ensure scheme is set
			if req.URL.Scheme == "" {
				if req.TLS != nil {
					req.URL.Scheme = "https"
				} else {
					req.URL.Scheme = "http"
				}
			}
		} else {
			// Original behavior for configured targets
			originalDirector(req)
			req.Host = targetURL.Host
			req.URL.Scheme = targetURL.Scheme
			req.URL.Host = targetURL.Host
			
			if strings.HasPrefix(req.URL.Path, "/"+serviceName+"/") {
				req.URL.Path = strings.TrimPrefix(req.URL.Path, "/"+serviceName)
			}
		}
		
		log.Printf("Proxying %s %s to %s", req.Method, req.URL.Path, req.URL.Host)
	}

	proxy.ModifyResponse = func(resp *http.Response) error {
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return err
		}
		resp.Body = io.NopCloser(bytes.NewBuffer(body))

		var jsonBody interface{}
		if err := json.Unmarshal(body, &jsonBody); err == nil {
			headers := make(map[string]string)
			for key, values := range resp.Header {
				if key == "Content-Type" || key == "Cache-Control" {
					headers[key] = values[0]
				}
			}

			captured := CapturedRoute{
				Method:      r.Method,
				Path:        normalizePathForTemplate(r.URL.Path),
				Status:      resp.StatusCode,
				Response:    jsonBody,
				Headers:     headers,
				Description: fmt.Sprintf("Captured from %s", serviceName),
				CapturedAt:  time.Now(),
			}

			if r.Method == "POST" || r.Method == "PUT" || r.Method == "PATCH" {
				if r.Body != nil {
					bodyBytes, _ := io.ReadAll(r.Body)
					r.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
					var reqBody interface{}
					if json.Unmarshal(bodyBytes, &reqBody) == nil {
						captured.RequestBody = reqBody
					}
				}
			}

			cp.mu.Lock()
			cp.captures = append(cp.captures, captured)
			cp.mu.Unlock()

			log.Printf("Captured: %s %s -> %d", r.Method, r.URL.Path, resp.StatusCode)
		}

		return nil
	}

	proxy.ServeHTTP(w, r)
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
	}
	return "misc"
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

	http.HandleFunc("/capture/save", func(w http.ResponseWriter, r *http.Request) {
		if err := proxy.SaveCaptures(); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Write([]byte("Captures saved successfully\n"))
	})

	http.HandleFunc("/capture/status", func(w http.ResponseWriter, r *http.Request) {
		proxy.mu.Lock()
		count := len(proxy.captures)
		proxy.mu.Unlock()
		
		response := map[string]interface{}{
			"captured_routes": count,
			"output_dir":      outputDir,
		}
		json.NewEncoder(w).Encode(response)
	})

	http.Handle("/", proxy)

	log.Printf("Capture Proxy starting on port %s", port)
	log.Printf("Output directory: %s", outputDir)
	log.Println("Configure your app to use this proxy by setting API URLs to http://localhost:" + port)
	log.Println("Save captures: curl http://localhost:" + port + "/capture/save")
	log.Println("Check status: curl http://localhost:" + port + "/capture/status")
	
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}