package main

import (
    "context"
    "crypto/tls"
    "io"
    "net"
    "net/http"
    "log"
    "os"
    "time"
)

func main() {
    log.Println("=== HTTPS Debug Test ===")
    
    // Check environment
    certFile := os.Getenv("SSL_CERT_FILE")
    if certFile != "" {
        log.Printf("✅ SSL_CERT_FILE set: %s", certFile)
        if _, err := os.Stat(certFile); err == nil {
            log.Println("✅ Certificate file exists")
        } else {
            log.Printf("❌ Certificate file not found: %v", err)
        }
    } else {
        log.Println("⚠️  SSL_CERT_FILE not set")
    }
    
    // Test 1: Try with custom DNS and default certificate handling
    log.Println("\n--- Test 1: Custom DNS with default certs ---")
    client1 := &http.Client{
        Transport: &http.Transport{
            DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                log.Printf("  Dialing %s %s", network, addr)
                dialer := &net.Dialer{
                    Timeout: 30 * time.Second,
                    Resolver: &net.Resolver{
                        PreferGo: true,
                        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                            log.Printf("  DNS lookup via 8.8.8.8")
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
    
    resp1, err1 := client1.Get("https://api.github.com/meta")
    if err1 != nil {
        log.Printf("❌ Test 1 failed: %v", err1)
    } else {
        body, _ := io.ReadAll(resp1.Body)
        resp1.Body.Close()
        log.Printf("✅ Test 1 success: Status %s, Body length: %d bytes", resp1.Status, len(body))
    }
    
    // Test 2: Try with custom DNS and skip certificate verification (INSECURE - just for testing)
    log.Println("\n--- Test 2: Custom DNS with certificate verification disabled (TESTING ONLY) ---")
    client2 := &http.Client{
        Transport: &http.Transport{
            TLSClientConfig: &tls.Config{
                InsecureSkipVerify: true, // ONLY for testing!
            },
            DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
                log.Printf("  Dialing %s %s", network, addr)
                dialer := &net.Dialer{
                    Timeout: 30 * time.Second,
                    Resolver: &net.Resolver{
                        PreferGo: true,
                        Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
                            log.Printf("  DNS lookup via 8.8.8.8")
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
    
    resp2, err2 := client2.Get("https://api.github.com/meta")
    if err2 != nil {
        log.Printf("❌ Test 2 failed: %v", err2)
    } else {
        body, _ := io.ReadAll(resp2.Body)
        resp2.Body.Close()
        log.Printf("✅ Test 2 success: Status %s, Body length: %d bytes", resp2.Status, len(body))
        
        // If this works but Test 1 doesn't, it's a certificate issue
        if err1 != nil {
            log.Println("\n⚠️  DIAGNOSIS: Certificate trust issue detected!")
            log.Println("   The proxy's certificate is not trusted.")
            log.Println("   Make sure SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem is set")
        }
    }
    
    // Test 3: Try a simpler endpoint
    log.Println("\n--- Test 3: Testing simpler endpoint (httpbin.org) ---")
    resp3, err3 := client2.Get("https://httpbin.org/get")
    if err3 != nil {
        log.Printf("❌ Test 3 failed: %v", err3)
    } else {
        body, _ := io.ReadAll(resp3.Body)
        resp3.Body.Close()
        log.Printf("✅ Test 3 success: Status %s, Body length: %d bytes", resp3.Status, len(body))
        if len(body) < 500 {
            log.Printf("   Response: %s", string(body))
        }
    }
    
    // Summary
    log.Println("\n=== SUMMARY ===")
    if err1 == nil {
        log.Println("✅ HTTPS capture is working correctly!")
    } else if err2 == nil {
        log.Println("⚠️  HTTPS works but certificate trust needs fixing")
        log.Println("   Solution: export SSL_CERT_FILE=/certs/mitmproxy-ca-cert.pem")
    } else {
        log.Println("❌ HTTPS interception may not be working")
        log.Println("   Run ./diagnose-proxy.sh for detailed diagnostics")
    }
}