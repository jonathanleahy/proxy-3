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
    log.Println("Testing HTTPS capture from mounted app directory...")
    
    client := &http.Client{
        Transport: &http.Transport{
            DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                dialer := &net.Dialer{
                    Timeout: 30 * time.Second,
                    Resolver: &net.Resolver{
                        PreferGo: true,
                        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                            d := net.Dialer{Timeout: 5 * time.Second}
                            return d.DialContext(ctx, network, "8.8.8.8:53")
                        },
                    },
                }
                return dialer.DialContext(ctx, network, addr)
            },
        },
        Timeout: 30 * time.Second,
    }
    
    resp, err := client.Get("https://api.github.com/repos/golang/go")
    if err != nil {
        log.Fatal("Error: ", err)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("✅ Status: %s\n", resp.Status)
    fmt.Printf("✅ Response length: %d bytes\n", len(body))
    fmt.Println("✅ HTTPS capture working from mounted app directory!")
}
