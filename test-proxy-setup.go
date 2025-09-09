package main

import (
    "fmt"
    "io"
    "net/http"
    "net/url"
    "os"
)

func main() {
    // Show environment
    fmt.Println("=== Environment Variables ===")
    fmt.Printf("HTTP_PROXY: %s\n", os.Getenv("HTTP_PROXY"))
    fmt.Printf("HTTPS_PROXY: %s\n", os.Getenv("HTTPS_PROXY"))
    fmt.Println()

    // Test 1: Using ProxyFromEnvironment
    fmt.Println("=== Test 1: ProxyFromEnvironment ===")
    client1 := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyFromEnvironment,
        },
    }
    testRequest(client1, "ProxyFromEnvironment")

    // Test 2: Using hardcoded proxy
    fmt.Println("\n=== Test 2: Hardcoded Proxy ===")
    proxyURL, _ := url.Parse("http://172.17.0.1:8084")
    client2 := &http.Client{
        Transport: &http.Transport{
            Proxy: http.ProxyURL(proxyURL),
        },
    }
    testRequest(client2, "Hardcoded proxy")

    // Test 3: Using DefaultTransport
    fmt.Println("\n=== Test 3: DefaultTransport (http.Get) ===")
    resp, err := http.Get("https://api.github.com/users/github")
    if err != nil {
        fmt.Printf("Error: %v\n", err)
    } else {
        fmt.Printf("Success! Status: %d\n", resp.StatusCode)
        resp.Body.Close()
    }
}

func testRequest(client *http.Client, method string) {
    resp, err := client.Get("https://api.github.com/users/github")
    if err != nil {
        fmt.Printf("%s failed: %v\n", method, err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    fmt.Printf("%s success! Response length: %d bytes\n", method, len(body))
}