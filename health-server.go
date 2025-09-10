package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"
)

type HealthResponse struct {
    Status      string    `json:"status"`
    Service     string    `json:"service"`
    Timestamp   time.Time `json:"timestamp"`
    ProxyActive bool      `json:"proxy_active"`
    Message     string    `json:"message"`
}

func main() {
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        health := HealthResponse{
            Status:      "healthy",
            Service:     "transparent-proxy-system",
            Timestamp:   time.Now(),
            ProxyActive: true,
            Message:     "System ready for HTTPS capture",
        }
        
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(health)
        log.Printf("Health check from %s", r.RemoteAddr)
    })
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Transparent Proxy System\n")
        fmt.Fprintf(w, "========================\n\n")
        fmt.Fprintf(w, "Endpoints:\n")
        fmt.Fprintf(w, "  /health - Health check\n")
        fmt.Fprintf(w, "  /status - Detailed status\n\n")
        fmt.Fprintf(w, "To capture HTTPS traffic, run your app with:\n")
        fmt.Fprintf(w, "  ./run-app.sh 'go run yourapp.go'\n")
    })
    
    http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
        status := map[string]interface{}{
            "status": "operational",
            "services": map[string]string{
                "proxy":       "running on :8084",
                "mock-viewer": "running on :8090",
                "health":      "running on :8080",
            },
            "capture": map[string]string{
                "mode":      "transparent",
                "user":      "appuser (UID 1000)",
                "ports":     "80, 443",
                "directory": "/captured",
            },
        }
        
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(status)
    })
    
    log.Println("Health server starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}