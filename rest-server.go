package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

type Response struct {
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	Path      string    `json:"path"`
}

func handler(w http.ResponseWriter, r *http.Request) {
	response := Response{
		Message:   "Hello from REST server inside transparent proxy!",
		Timestamp: time.Now(),
		Path:      r.URL.Path,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

	// Make an outbound HTTPS request (this will be captured!)
	go func() {
		log.Println("Making outbound HTTPS request (will be captured)...")
		resp, err := http.Get("https://api.github.com/users/github")
		if err != nil {
			log.Printf("Outbound request failed: %v", err)
		} else {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			log.Printf("Outbound request successful: %d bytes received", len(body))
		}
	}()
}

func main() {
	http.HandleFunc("/", handler)
	http.HandleFunc("/api/test", handler)
	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	})

	fmt.Println("🚀 REST server starting on :8083")
	fmt.Println("📡 All outbound HTTPS requests will be transparently captured")
	fmt.Println("🌐 Access from outside: http://localhost:8083")
	
	log.Fatal(http.ListenAndServe(":8083", nil))
}