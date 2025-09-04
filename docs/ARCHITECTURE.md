# 🏗️ System Architecture

## Overview

```
┌──────────────────────────────────────────────────────────────┐
│                        RECORD MODE                            │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│   Your App ──HTTP──► Capture Proxy ──Forward──► Real APIs    │
│      │                    │                         │         │
│      │                    │                         ▼         │
│      │                    └────────► Saves      Returns      │
│      │                              Responses    Real Data    │
│      ▼                                 │                      │
│   Gets Data                            ▼                      │
│                                   captured/*.json             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                        REPLAY MODE                            │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│   Your App ──HTTP──► Mock Server ◄── Reads ── configs/*.json │
│      │                    │                                   │
│      │                    │                                   │
│      ▼                    ▼                                   │
│   Gets Data         Returns Mocked                            │
│                     Responses                                 │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Capture Proxy (Port 8091)
```
Purpose: Intercept and record API responses
Location: cmd/capture/main.go

Features:
- Transparent proxy for HTTP/HTTPS
- Automatic path normalization
- Response recording to JSON
- Multiple API endpoint support
- Request body capture for POST/PUT
```

### 2. Mock Server (Port 8090)
```
Purpose: Serve recorded responses as mocks
Location: cmd/main.go

Features:
- Dynamic route loading from JSON
- Hot reload on config changes
- Path parameter support
- Response templating
- Custom headers and delays
```

### 3. Configuration Files
```
configs/*.json
├── Route definitions
├── Response templates
├── Status codes
├── Headers
└── Delays

captured/*.json
├── Recorded responses
├── Grouped by service
├── Normalized paths
└── Request bodies
```

## Data Flow

### Recording Flow
```
1. App makes HTTP request
   ↓
2. HTTP_PROXY env var redirects to proxy
   ↓
3. Proxy forwards to real API
   ↓
4. Real API returns response
   ↓
5. Proxy captures response
   ↓
6. Proxy returns response to app
   ↓
7. Save captures to JSON files
```

### Replay Flow
```
1. App makes HTTP request
   ↓
2. Request goes to mock server
   ↓
3. Mock server matches route
   ↓
4. Loads response from config
   ↓
5. Applies path parameters
   ↓
6. Returns mocked response
```

## Path Normalization

The capture proxy automatically normalizes paths:

```
INPUT                           →  NORMALIZED
/users/123                      →  /users/{id}
/accounts/ACC-456               →  /accounts/{id}
/posts/789/comments/321         →  /posts/{id}/comments/{id}
/api/v2/orders/ORD-789          →  /api/v2/orders/{id}
```

## Service Detection

The proxy groups captures by detected service type:

```
Path Contains        →  Service Name
/accounts           →  accounts
/customers          →  customers
/cards, /wallet     →  cards
/ledger             →  ledger
/statements         →  statements
/authorizations     →  authorizations
(others)            →  misc
```

## JSON Structure

### Route Configuration
```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/users/{id}",
      "status": 200,
      "headers": {
        "Content-Type": "application/json"
      },
      "delay": 100,
      "response": {
        "id": "{{id}}",
        "name": "User {{id}}"
      }
    }
  ]
}
```

### Captured Response
```json
{
  "method": "GET",
  "path": "/users/{id}",
  "status": 200,
  "response": {...actual response...},
  "headers": {...},
  "description": "Captured from accounts",
  "captured_at": "2025-01-01T10:00:00Z",
  "request_body": {...if POST/PUT/PATCH...}
}
```

## Environment Variables

### Capture Proxy
- `CAPTURE_PORT` - Proxy port (8091)
- `OUTPUT_DIR` - Where to save captures
- `*_API_URL` - Real API endpoints

### Mock Server
- `PORT` - Server port (8090)
- `CONFIG_PATH` - Config directory

### Application
- `HTTP_PROXY` - Redirect through proxy
- `HTTPS_PROXY` - For HTTPS traffic
- Custom API URLs for direct mock access

## Docker Architecture

```
┌─────────────────────────────────────────┐
│         Docker Network: api-network      │
├─────────────────────────────────────────┤
│                                          │
│  ┌──────────────┐    ┌──────────────┐   │
│  │ Mock Server  │    │ Capture Proxy│   │
│  │   Port 8090  │    │   Port 8091  │   │
│  └──────────────┘    └──────────────┘   │
│          ▲                    ▲          │
│          │                    │          │
│  ┌──────────────────────────────────┐   │
│  │        Example App               │   │
│  │         Port 8080                │   │
│  └──────────────────────────────────┘   │
│                                          │
└─────────────────────────────────────────┘
```

## Usage Patterns

### Development Testing
```bash
# Record once
make record
# Develop with mocks
make replay
# Test changes
make test
```

### CI/CD Pipeline
```bash
# Use pre-recorded mocks
cp saved-mocks/*.json configs/
make mock &
npm test
```

### Team Collaboration
```bash
# Share captures via Git
git add captured/*.json
git commit -m "Updated API mocks"
git push
```

### Performance Testing
```bash
# Add delays to simulate slow networks
# Edit configs/*.json → add "delay": 3000
make replay
# Run performance tests
```