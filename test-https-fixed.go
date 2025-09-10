package main

import (
    "fmt"
    "io"
    "net"
    "net/http"
    "log"
    "time"
)

func main() {
    log.Println("Making HTTPS request to GitHub API with custom resolver...")
    
    // Create custom HTTP client with DNS resolver
    client := &http.Client{
        Transport: &http.Transport{
            DialContext: (&net.Dialer{
                Timeout: 30 * time.Second,
                Resolver: &net.Resolver{
                    PreferGo: true,
                    Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                        d := net.Dialer{}
                        return d.DialContext(ctx, network, "8.8.8.8:53")
                    },
                },
            }).DialContext,
        },
    }
    
    resp, err := client.Get("https://api.github.com/users/github")
    if err != nil {
        log.Fatal("Error:", err)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("Status: %s\n", resp.Status)
    fmt.Printf("Response length: %d bytes\n", len(body))
    
    // Print first 200 chars of response
    if len(body) > 200 {
        fmt.Printf("First 200 chars: %s...\n", string(body[:200]))
    } else {
        fmt.Printf("Response: %s\n", string(body))
    }
    
    log.Println("Request completed successfully")
}
