package main

import (
    "context"
    "fmt"
    "io"
    "net"
    "net/http"
    "log"
    "time"
)

func main() {
    log.Println("Testing HTTPS with custom DNS resolver...")
    
    // Create a custom HTTP client with Google DNS
    client := &http.Client{
        Transport: &http.Transport{
            DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                // Custom dialer with Google DNS
                dialer := &net.Dialer{
                    Timeout: 30 * time.Second,
                    Resolver: &net.Resolver{
                        PreferGo: true,
                        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                            d := net.Dialer{
                                Timeout: time.Second * 5,
                            }
                            // Use Google's DNS server
                            return d.DialContext(ctx, network, "8.8.8.8:53")
                        },
                    },
                }
                return dialer.DialContext(ctx, network, addr)
            },
        },
        Timeout: 30 * time.Second,
    }
    
    // Make HTTPS request
    resp, err := client.Get("https://api.github.com/users/github")
    if err != nil {
        log.Fatal("Error: ", err)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("✅ Status: %s\n", resp.Status)
    fmt.Printf("✅ Response length: %d bytes\n", len(body))
    
    // Show first 300 chars
    if len(body) > 300 {
        fmt.Printf("First 300 chars:\n%s...\n", string(body[:300]))
    } else {
        fmt.Printf("Response:\n%s\n", string(body))
    }
    
    log.Println("✅ Request completed successfully!")
}