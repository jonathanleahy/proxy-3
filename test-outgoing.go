package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

func main() {
	// This test app makes outgoing API calls that should be captured by the proxy
	
	fmt.Println("Testing outgoing API call capture...")
	fmt.Printf("HTTP_PROXY is set to: %s\n", os.Getenv("HTTP_PROXY"))
	fmt.Printf("HTTPS_PROXY is set to: %s\n", os.Getenv("HTTPS_PROXY"))
	fmt.Println()

	// Test 1: Simple GET request
	fmt.Println("Test 1: Making GET request to external API...")
	resp, err := http.Get("https://jsonplaceholder.typicode.com/users/1")
	if err != nil {
		log.Printf("Error making request: %v", err)
	} else {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		fmt.Printf("Response status: %d\n", resp.StatusCode)
		fmt.Printf("Response length: %d bytes\n", len(body))
	}

	// Test 2: Another API call
	fmt.Println("\nTest 2: Making another GET request...")
	resp2, err := http.Get("https://jsonplaceholder.typicode.com/posts/1")
	if err != nil {
		log.Printf("Error making request: %v", err)
	} else {
		defer resp2.Body.Close()
		body, _ := io.ReadAll(resp2.Body)
		fmt.Printf("Response status: %d\n", resp2.StatusCode)
		fmt.Printf("Response length: %d bytes\n", len(body))
	}

	fmt.Println("\n✅ Tests complete!")
	fmt.Println("Check the viewer at http://localhost:8090/viewer")
	fmt.Println("Select 'Live Captures' to see if these calls were captured")
}