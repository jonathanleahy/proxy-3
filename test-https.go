package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

func main() {
	fmt.Println("Testing HTTPS connection through transparent proxy...")
	fmt.Printf("SSL_CERT_FILE: %s\n", os.Getenv("SSL_CERT_FILE"))
	
	client := &http.Client{
		Timeout: 10 * time.Second,
	}
	
	resp, err := client.Get("https://jsonplaceholder.typicode.com/users/1")
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()
	
	body, _ := io.ReadAll(resp.Body)
	fmt.Printf("SUCCESS! Status: %d, Body length: %d bytes\n", resp.StatusCode, len(body))
	
	// Print first 200 chars of body
	if len(body) > 200 {
		fmt.Printf("Body preview: %s...\n", string(body[:200]))
	} else {
		fmt.Printf("Body: %s\n", string(body))
	}
}