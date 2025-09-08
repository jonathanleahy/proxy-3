package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

// Simple REST server that makes external API calls
// Perfect for demonstrating proxy recording and replay

type Response struct {
	Message   string      `json:"message"`
	Timestamp time.Time   `json:"timestamp"`
	Data      interface{} `json:"data,omitempty"`
	Source    string      `json:"source"`
}

// FetchUsers gets user data from external API
func FetchUsers(w http.ResponseWriter, r *http.Request) {
	apiURL := os.Getenv("USERS_API_URL")
	if apiURL == "" {
		apiURL = "https://jsonplaceholder.typicode.com"
	}

	log.Printf("Fetching users from: %s", apiURL)

	// Create standard HTTP client with timeout
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("%s/users", apiURL))
	if err != nil {
		json.NewEncoder(w).Encode(Response{
			Message:   "Error fetching users",
			Timestamp: time.Now(),
			Source:    "error",
		})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var users interface{}
	json.Unmarshal(body, &users)

	json.NewEncoder(w).Encode(Response{
		Message:   "Users fetched successfully",
		Timestamp: time.Now(),
		Data:      users,
		Source:    apiURL,
	})
}

// FetchPosts gets posts from external API
func FetchPosts(w http.ResponseWriter, r *http.Request) {
	apiURL := os.Getenv("POSTS_API_URL")
	if apiURL == "" {
		apiURL = "https://jsonplaceholder.typicode.com"
	}

	log.Printf("Fetching posts from: %s", apiURL)

	// Create standard HTTP client with timeout
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("%s/posts?_limit=5", apiURL))
	if err != nil {
		json.NewEncoder(w).Encode(Response{
			Message:   "Error fetching posts",
			Timestamp: time.Now(),
			Source:    "error",
		})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var posts interface{}
	json.Unmarshal(body, &posts)

	json.NewEncoder(w).Encode(Response{
		Message:   "Posts fetched successfully",
		Timestamp: time.Now(),
		Data:      posts,
		Source:    apiURL,
	})
}

// HealthCheck endpoint
func HealthCheck(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(Response{
		Message:   "Service is healthy",
		Timestamp: time.Now(),
		Source:    "internal",
	})
}

// AggregateData combines data from multiple external sources
func AggregateData(w http.ResponseWriter, r *http.Request) {
	apiURL := os.Getenv("API_BASE_URL")
	if apiURL == "" {
		apiURL = "https://jsonplaceholder.typicode.com"
	}

	log.Printf("Aggregating data from: %s", apiURL)

	// Create standard HTTP client with timeout
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	// Fetch user
	userResp, err := client.Get(fmt.Sprintf("%s/users/1", apiURL))
	var userBody []byte
	if err != nil {
		log.Printf("Error fetching user: %v", err)
	} else {
		defer userResp.Body.Close()
		userBody, _ = io.ReadAll(userResp.Body)
	}

	// Fetch posts
	postsResp, err := client.Get(fmt.Sprintf("%s/posts?userId=1&_limit=3", apiURL))
	var postsBody []byte
	if err != nil {
		log.Printf("Error fetching posts: %v", err)
	} else {
		defer postsResp.Body.Close()
		postsBody, _ = io.ReadAll(postsResp.Body)
	}

	// Fetch todos
	todosResp, err := client.Get(fmt.Sprintf("%s/todos?userId=1&_limit=3", apiURL))
	var todosBody []byte
	if err != nil {
		log.Printf("Error fetching todos: %v", err)
	} else {
		defer todosResp.Body.Close()
		todosBody, _ = io.ReadAll(todosResp.Body)
	}

	var user, posts, todos interface{}
	if len(userBody) > 0 {
		json.Unmarshal(userBody, &user)
	}
	if len(postsBody) > 0 {
		json.Unmarshal(postsBody, &posts)
	}
	if len(todosBody) > 0 {
		json.Unmarshal(todosBody, &todos)
	}

	aggregated := map[string]interface{}{
		"user":  user,
		"posts": posts,
		"todos": todos,
	}

	json.NewEncoder(w).Encode(Response{
		Message:   "Data aggregated successfully",
		Timestamp: time.Now(),
		Data:      aggregated,
		Source:    apiURL,
	})
}

func main() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Check if proxy is set
	if proxy := os.Getenv("HTTP_PROXY"); proxy != "" {
		log.Printf("📸 Using HTTP proxy: %s", proxy)
	} else {
		log.Println("🎭 No proxy set - direct connections")
	}

	// Setup routes
	http.HandleFunc("/health", HealthCheck)
	http.HandleFunc("/users", FetchUsers)
	http.HandleFunc("/posts", FetchPosts)
	http.HandleFunc("/aggregate", AggregateData)

	// Start server
	log.Printf("🚀 Example REST API starting on port %s", port)
	log.Println("Available endpoints:")
	log.Println("  GET /health    - Health check")
	log.Println("  GET /users     - Fetch users from external API")
	log.Println("  GET /posts     - Fetch posts from external API")
	log.Println("  GET /aggregate - Aggregate data from multiple sources")
	
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}