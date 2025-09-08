package main

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

func main() {
	fmt.Println("Testing HTTP/HTTPS connectivity...")
	
	// Test HTTP first
	fmt.Println("\n1. Testing HTTP (httpbin.org)...")
	testURL("http://httpbin.org/get")
	
	// Test HTTPS
	fmt.Println("\n2. Testing HTTPS (httpbin.org)...")
	testURL("https://httpbin.org/get")
	
	// Test another HTTPS endpoint
	fmt.Println("\n3. Testing HTTPS (api.github.com)...")
	testURL("https://api.github.com")
}

func testURL(url string) {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}
	
	fmt.Printf("   Fetching: %s\n", url)
	resp, err := client.Get(url)
	if err != nil {
		fmt.Printf("   ❌ Error: %v\n", err)
		return
	}
	defer resp.Body.Close()
	
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("   ❌ Error reading body: %v\n", err)
		return
	}
	
	fmt.Printf("   ✅ Success! Status: %d, Body length: %d bytes\n", resp.StatusCode, len(body))
	if len(body) > 100 {
		fmt.Printf("   First 100 chars: %s...\n", string(body[:100]))
	}
}