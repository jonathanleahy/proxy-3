package main

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

func main() {
	fmt.Println("🚀 Test app starting - making HTTPS requests...")

	// Test HTTPS request to GitHub
	fmt.Println("📡 Making HTTPS request to api.github.com...")
	resp, err := http.Get("https://api.github.com/users/github")
	if err != nil {
		fmt.Printf("❌ GitHub HTTPS request failed: %v\n", err)
	} else {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("✅ GitHub Response (%d): %s\n", resp.StatusCode, string(body)[:200]+"...")
	}

	time.Sleep(1 * time.Second)

	// Test HTTPS request to JSONPlaceholder
	fmt.Println("📡 Making HTTPS request to jsonplaceholder...")
	resp, err = http.Get("https://jsonplaceholder.typicode.com/posts/1")
	if err != nil {
		fmt.Printf("❌ JSONPlaceholder HTTPS request failed: %v\n", err)
	} else {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("✅ JSONPlaceholder Response (%d): %s\n", resp.StatusCode, string(body)[:200]+"...")
	}

	time.Sleep(1 * time.Second)

	// Test HTTPS request to HTTPBin
	fmt.Println("📡 Making HTTPS request to httpbin.org...")
	resp, err = http.Get("https://httpbin.org/json")
	if err != nil {
		fmt.Printf("❌ HTTPBin HTTPS request failed: %v\n", err)
	} else {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		fmt.Printf("✅ HTTPBin Response (%d): %s\n", resp.StatusCode, string(body)[:200]+"...")
	}

	fmt.Println("🎉 Test app completed - all HTTPS traffic should be captured!")
}