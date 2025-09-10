package main

import (
    "fmt"
    "io"
    "net/http"
    "log"
)

func main() {
    log.Println("Making HTTPS request to GitHub API...")
    
    resp, err := http.Get("https://api.github.com/users/github")
    if err != nil {
        log.Fatal("Error:", err)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("Status: %s\n", resp.Status)
    fmt.Printf("Response length: %d bytes\n", len(body))
    log.Println("Request completed successfully")
}
