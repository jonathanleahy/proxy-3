package main

import (
    "fmt"
    "net/http"
    "log"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from test server on port 8089!\n")
        log.Printf("Request: %s %s", r.Method, r.URL.Path)
    })
    
    http.HandleFunc("/api/test", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        fmt.Fprintf(w, `{"message": "API test response", "timestamp": "%s"}`, http.TimeFormat)
        log.Printf("API Request: %s %s", r.Method, r.URL.Path)
    })
    
    log.Println("Starting server on :8089")
    log.Fatal(http.ListenAndServe(":8089", nil))
}
