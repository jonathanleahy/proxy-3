.PHONY: help record replay test clean status docker-up docker-down quick-demo

# Default target
help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "   🎯 Mock API Server - Make Commands"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "Quick Commands:"
	@echo "  make record      - Start capture proxy for recording"
	@echo "  make replay      - Start mock server with captured data"
	@echo "  make test        - Test current setup"
	@echo "  make quick-demo  - Run complete demo flow"
	@echo ""
	@echo "Server Commands:"
	@echo "  make mock        - Run mock server"
	@echo "  make capture     - Run capture proxy"
	@echo "  make example     - Run example app"
	@echo "  make save        - Save current captures"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make docker-up   - Start all services with Docker"
	@echo "  make docker-down - Stop Docker services"
	@echo "  make docker-logs - View Docker logs"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make status      - Check system status"
	@echo "  make clean       - Clean captured files"
	@echo "  make install     - Install dependencies"

# Quick commands
record:
	@echo "📸 Starting RECORD mode..."
	@./quick-test.sh record

replay:
	@echo "🎭 Starting REPLAY mode..."
	@./quick-test.sh replay

test:
	@echo "🧪 Running tests..."
	@./quick-test.sh test

quick-demo:
	@echo "🚀 Running complete demo flow..."
	@echo "Step 1: Recording API calls..."
	@./quick-test.sh record
	@sleep 2
	@echo ""
	@echo "Step 2: Starting replay mode..."
	@./quick-test.sh replay &
	@sleep 3
	@echo ""
	@echo "Step 3: Testing mocked endpoints..."
	@curl -s http://localhost:8090/users/1 | jq '.' || echo "Mock test complete"
	@echo ""
	@echo "✅ Demo complete! Mock server running on port 8090"

# Server commands
mock:
	@echo "Starting mock server on port 8090..."
	@go run cmd/main.go

capture:
	@echo "Starting capture proxy on port 8091..."
	@go run cmd/capture/main.go

example:
	@echo "Starting example app on port 8080..."
	@cd example-app && go run main.go

save:
	@echo "💾 Saving captures..."
	@curl -s http://localhost:8091/capture/save || echo "No captures to save"

# Docker commands
docker-up:
	@echo "🐳 Starting services with Docker..."
	@docker-compose up -d
	@echo "✅ Services started:"
	@echo "  - Mock Server: http://localhost:8090"
	@echo "  - Capture Proxy: http://localhost:8091 (if profile=capture)"
	@echo "  - Example App: http://localhost:8080 (if profile=demo)"

docker-down:
	@echo "🛑 Stopping Docker services..."
	@docker-compose down

docker-logs:
	@docker-compose logs -f

docker-capture:
	@echo "🐳 Starting capture services..."
	@docker-compose --profile capture up -d

docker-demo:
	@echo "🐳 Starting demo services..."
	@docker-compose --profile demo up -d

# Utility commands
status:
	@echo "📊 System Status"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo -n "Mock Server (8090): "
	@curl -s http://localhost:8090 > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"
	@echo -n "Capture Proxy (8091): "
	@curl -s http://localhost:8091/capture/status > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"
	@echo -n "Example App (8080): "
	@curl -s http://localhost:8080/health > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"
	@echo ""
	@echo "Captured files:"
	@ls -la captured/*.json 2>/dev/null || echo "  No captures yet"
	@echo ""
	@echo "Config files:"
	@ls -la configs/*.json 2>/dev/null || echo "  No configs yet"

clean:
	@echo "🧹 Cleaning captured files..."
	@rm -rf captured/*.json
	@echo "✅ Cleaned"

install:
	@echo "📦 Installing dependencies..."
	@go mod download
	@echo "✅ Dependencies installed"

# Development helpers
dev-record:
	@echo "Starting development record mode..."
	@HTTP_PROXY=http://localhost:8091 go run example-app/main.go

dev-replay:
	@echo "Starting development replay mode..."
	@cp captured/*.json configs/ 2>/dev/null || true
	@API_BASE_URL=http://localhost:8090 go run example-app/main.go