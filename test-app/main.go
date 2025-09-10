package main

import (
    "fmt"
    "log"
    "net/http"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from test app on port 8095!\n")
        log.Printf("Request: %s %s", r.Method, r.URL.Path)
    })
    
    log.Println("Starting server on :8095")
    log.Fatal(http.ListenAndServe(":8095", nil))
}
