package main

import (
	"fmt"
	"log"
	"net/http"
	"time"
)

func main() {
	// Simple test endpoint
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "TEST SERVER RESPONSE - Time: %s\n", time.Now().Format(time.RFC3339))
		log.Printf("Received request: %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
	})

	http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok","server":"test-server","time":"%s"}`+"\n", time.Now().Format(time.RFC3339))
		log.Printf("Test endpoint hit from %s", r.RemoteAddr)
	})

	fmt.Println("=================================")
	fmt.Println("TEST SERVER STARTING ON PORT 8080")
	fmt.Println("=================================")
	fmt.Println("Endpoints:")
	fmt.Println("  http://localhost:8080/")
	fmt.Println("  http://localhost:8080/test")
	fmt.Println("")
	
	log.Fatal(http.ListenAndServe("0.0.0.0:8080", nil))
}