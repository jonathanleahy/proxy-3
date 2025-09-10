package main

import (
    "crypto/tls"
    "fmt"
    "io"
    "net/http"
    "os"
)

func main() {
    fmt.Println("=== Test Without DNS Lookup ===")
    fmt.Printf("SSL_CERT_FILE: %s\n", os.Getenv("SSL_CERT_FILE"))
    fmt.Printf("HTTP_PROXY: %s\n", os.Getenv("HTTP_PROXY"))
    fmt.Printf("HTTPS_PROXY: %s\n\n", os.Getenv("HTTPS_PROXY"))
    
    // Test 1: Direct IP with Host header (bypasses DNS)
    fmt.Println("Test 1: Using IP address with Host header...")
    
    client1 := &http.Client{
        Transport: &http.Transport{
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true, // For testing only
            },
        },
    }
    
    req1, _ := http.NewRequest("GET", "https://34.107.221.82/get", nil)
    req1.Host = "httpbin.org"
    req1.Header.Set("Host", "httpbin.org")
    
    resp1, err1 := client1.Do(req1)
    if err1 != nil {
        fmt.Printf("❌ Direct IP failed: %v\n", err1)
    } else {
        body, _ := io.ReadAll(resp1.Body)
        fmt.Printf("✅ Direct IP success: %s\n", resp1.Status)
        if len(body) > 0 && len(body) < 500 {
            fmt.Printf("Response: %s\n", string(body))
        }
        resp1.Body.Close()
    }
    
    // Test 2: Local test (no external DNS needed)
    fmt.Println("\nTest 2: Local connectivity test...")
    
    // Try to connect to the proxy directly
    proxyURL := os.Getenv("HTTP_PROXY")
    if proxyURL != "" {
        resp2, err2 := http.Get("http://localhost:8080/health")
        if err2 != nil {
            fmt.Printf("❌ Local test failed: %v\n", err2)
        } else {
            fmt.Printf("✅ Local test success: %s\n", resp2.Status)
            resp2.Body.Close()
        }
    } else {
        fmt.Println("⚠️  No proxy configured")
    }
    
    // Test 3: Simple HTTP (no SSL complications)
    fmt.Println("\nTest 3: Simple HTTP request...")
    resp3, err3 := http.Get("http://34.107.221.82/get")
    if err3 != nil {
        fmt.Printf("❌ HTTP failed: %v\n", err3)
    } else {
        fmt.Printf("✅ HTTP success: %s\n", resp3.Status)
        resp3.Body.Close()
    }
    
    fmt.Println("\n=== Summary ===")
    if err1 == nil || err3 == nil {
        fmt.Println("✅ Network connectivity is working")
        if err1 != nil {
            fmt.Println("⚠️  HTTPS has issues - likely certificate trust")
        }
    } else {
        fmt.Println("❌ Network connectivity issues detected")
        fmt.Println("   The proxy may not be intercepting traffic correctly")
    }
}