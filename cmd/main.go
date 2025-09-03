package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

type RouteConfig struct {
	Method      string                 `json:"method"`
	Path        string                 `json:"path"`
	Status      int                    `json:"status"`
	Response    interface{}            `json:"response"`
	Headers     map[string]string      `json:"headers"`
	Delay       int                    `json:"delay"`
	Description string                 `json:"description"`
}

type RoutesFile struct {
	Routes []RouteConfig `json:"routes"`
}

type MockServer struct {
	echo       *echo.Echo
	routes     map[string]RouteConfig
	routesMu   sync.RWMutex
	configPath string
}

func NewMockServer(configPath string) *MockServer {
	e := echo.New()
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
		AllowOrigins: []string{"*"},
		AllowMethods: []string{echo.GET, echo.PUT, echo.POST, echo.DELETE, echo.PATCH, echo.OPTIONS},
		AllowHeaders: []string{"*"},
	}))

	ms := &MockServer{
		echo:       e,
		routes:     make(map[string]RouteConfig),
		configPath: configPath,
	}

	e.Any("/*", ms.handleRequest)

	return ms
}

func (ms *MockServer) loadRoutes() error {
	ms.routesMu.Lock()
	defer ms.routesMu.Unlock()

	ms.routes = make(map[string]RouteConfig)

	pattern := filepath.Join(ms.configPath, "*.json")
	files, err := filepath.Glob(pattern)
	if err != nil {
		return fmt.Errorf("failed to glob config files: %w", err)
	}

	totalRoutes := 0
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			log.Printf("Error reading file %s: %v", file, err)
			continue
		}

		var routesFile RoutesFile
		if err := json.Unmarshal(data, &routesFile); err != nil {
			log.Printf("Error parsing JSON from %s: %v", file, err)
			continue
		}

		for _, route := range routesFile.Routes {
			key := fmt.Sprintf("%s:%s", strings.ToUpper(route.Method), route.Path)
			ms.routes[key] = route
			totalRoutes++
		}

		log.Printf("Loaded %d routes from %s", len(routesFile.Routes), filepath.Base(file))
	}

	log.Printf("Total routes loaded: %d", totalRoutes)
	return nil
}

func (ms *MockServer) handleRequest(c echo.Context) error {
	ms.routesMu.RLock()
	defer ms.routesMu.RUnlock()

	path := c.Request().URL.Path
	method := c.Request().Method

	var matchedRoute *RouteConfig
	var matchedParams map[string]string

	for key, route := range ms.routes {
		routeMethod := strings.Split(key, ":")[0]
		if routeMethod != method {
			continue
		}

		params, matched := matchPath(route.Path, path)
		if matched {
			matchedRoute = &route
			matchedParams = params
			break
		}
	}

	if matchedRoute == nil {
		log.Printf("No route found for %s %s", method, path)
		return c.JSON(http.StatusNotFound, map[string]interface{}{
			"error":   "Route not found",
			"method":  method,
			"path":    path,
			"message": "This endpoint has not been configured in the mock server",
		})
	}

	log.Printf("Matched route: %s %s -> %s", method, path, matchedRoute.Description)

	if matchedRoute.Delay > 0 {
		time.Sleep(time.Duration(matchedRoute.Delay) * time.Millisecond)
	}

	for key, value := range matchedRoute.Headers {
		c.Response().Header().Set(key, value)
	}

	response := matchedRoute.Response
	if responseStr, ok := response.(string); ok {
		response = replacePlaceholders(responseStr, matchedParams)
		var jsonResponse interface{}
		if err := json.Unmarshal([]byte(response.(string)), &jsonResponse); err == nil {
			response = jsonResponse
		}
	}

	status := matchedRoute.Status
	if status == 0 {
		status = http.StatusOK
	}

	return c.JSON(status, response)
}

func matchPath(pattern, path string) (map[string]string, bool) {
	patternParts := strings.Split(pattern, "/")
	pathParts := strings.Split(path, "/")

	if len(patternParts) != len(pathParts) {
		return nil, false
	}

	params := make(map[string]string)

	for i, part := range patternParts {
		if strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") {
			paramName := part[1 : len(part)-1]
			params[paramName] = pathParts[i]
		} else if part != pathParts[i] {
			return nil, false
		}
	}

	return params, true
}

func replacePlaceholders(template string, params map[string]string) string {
	result := template
	for key, value := range params {
		placeholder := fmt.Sprintf("{{%s}}", key)
		result = strings.ReplaceAll(result, placeholder, value)
	}
	return result
}

func (ms *MockServer) watchConfigFiles() {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Printf("Failed to create file watcher: %v", err)
		return
	}
	defer watcher.Close()

	err = watcher.Add(ms.configPath)
	if err != nil {
		log.Printf("Failed to watch config directory: %v", err)
		return
	}

	log.Printf("Watching for changes in %s", ms.configPath)

	for {
		select {
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			if event.Op&fsnotify.Write == fsnotify.Write || event.Op&fsnotify.Create == fsnotify.Create {
				if strings.HasSuffix(event.Name, ".json") {
					log.Printf("Config file changed: %s", event.Name)
					time.Sleep(100 * time.Millisecond)
					if err := ms.loadRoutes(); err != nil {
						log.Printf("Error reloading routes: %v", err)
					}
				}
			}
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			log.Printf("Watcher error: %v", err)
		}
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8090"
	}

	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "./configs"
	}

	server := NewMockServer(configPath)

	if err := server.loadRoutes(); err != nil {
		log.Printf("Warning: Failed to load initial routes: %v", err)
	}

	go server.watchConfigFiles()

	log.Printf("Mock API Server starting on port %s", port)
	log.Printf("Loading route configurations from: %s", configPath)
	log.Printf("Place your route JSON files in the configs directory")
	
	if err := server.echo.Start(":" + port); err != nil {
		log.Fatal(err)
	}
}