package main

import (
    "crypto/tls"
    "fmt"
    "io"
    "net/http"
    "net/url"
    "os"
)

func main() {
    // This GUARANTEES proxy usage
    proxyURL, _ := url.Parse("http://localhost:8084")
    
    client := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyURL(proxyURL),
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true, // Accept the mitmproxy certificate
            },
        },
    }
    
    fmt.Println("Making HTTPS request through proxy...")
    resp, err := client.Get("https://api.github.com/users/github")
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        os.Exit(1)
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("Success! Response: %.100s...\n", string(body))
    fmt.Println("\nCheck ./captured/ for the captured traffic!")
}