# 🎯 The Complete Dummy's Guide to the Mock API Server

> **For absolute beginners:** This guide assumes you know nothing about API mocking or proxies. We'll walk through everything step-by-step!

## 📚 Table of Contents
1. [What Is This Thing?](#what-is-this-thing)
2. [Quick Start - Just Make It Work!](#quick-start---just-make-it-work)
3. [Capturing Real API Responses](#capturing-real-api-responses)
4. [Creating Your Own Mock Routes](#creating-your-own-mock-routes)
5. [Common Problems & Solutions](#common-problems--solutions)
6. [Cheat Sheet](#cheat-sheet)

---

## 🤔 What Is This Thing?

This is a **Mock API Server** - think of it as a fake API that pretends to be your real backend services.

### Why Use It?
- **Testing without real APIs** - No need for internet or real backend
- **Capture real responses** - Record what real APIs return and replay them
- **Control everything** - Make APIs return exactly what you want
- **Never goes down** - Unlike real APIs, this always works

### Two Main Parts:
1. **Mock Server** - The fake API that returns pre-configured responses
2. **Capture Proxy** - Records real API responses to use as mocks

---

## 🚀 Quick Start - Just Make It Work!

### Step 1: Start the Mock Server

Open a terminal in the project folder and run:

```bash
# This starts the fake API server
go run cmd/main.go
```

You'll see:
```
Mock API Server starting on port 8090
Loading routes from: ./configs
```

✅ **That's it! Your mock server is running at http://localhost:8090**

### Step 2: Test It

Open a new terminal and try:

```bash
# Test if it's working
curl http://localhost:8090/v2/accounts/123
```

If you get a JSON response, it's working! If you get `404`, that route isn't configured yet.

### Step 3: Your App Uses It

Instead of pointing your app to real APIs like:
```
https://api.yourcompany.com/accounts
```

Point it to your mock:
```
http://localhost:8090/accounts
```

---

## 📸 Capturing Real API Responses

> **Goal:** Record what real APIs return so you can use those responses as mocks

### Method 1: The Super Easy Way

#### Step 1: Generate the Setup Script
```bash
./capture-real-apis.sh intercept
```

This creates a file called `run-capture-proxy.sh`

#### Step 2: Edit the Script
Open `run-capture-proxy.sh` in a text editor and replace the example URLs with your real ones:

**Change this:**
```bash
export ACCOUNTS_API_URL="https://api-accounts.example.com"
```

**To your real API:**
```bash
export ACCOUNTS_API_URL="https://api.yourcompany.com/accounts"
```

#### Step 3: Run the Capture Proxy
```bash
./run-capture-proxy.sh
```

You'll see:
```
Capture Proxy starting on port 8091
```

#### Step 4: Update Your App's Configuration

In your app's `.env` file, change:

**From:**
```
ACCOUNTS_API_URL=https://api.yourcompany.com/accounts
```

**To:**
```
ACCOUNTS_API_URL=http://localhost:8091/accounts
```

#### Step 5: Use Your App Normally
Just use your application as you normally would. Every API call gets recorded!

#### Step 6: Save the Captures
When you're done using the app:
```bash
curl http://localhost:8091/capture/save
```

#### Step 7: Use Captured Data as Mocks
```bash
# Copy captured data to the mock server's config folder
cp captured/accounts-captured.json configs/
```

Now restart the mock server and it will use your captured data!

---

## 🛠️ Creating Your Own Mock Routes

### The Simple Way: Edit JSON Files

All mock responses are defined in JSON files in the `configs/` folder.

#### Example: Create a New User Endpoint

Create a file `configs/users.json`:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/users/123",
      "status": 200,
      "response": {
        "id": 123,
        "name": "John Doe",
        "email": "john@example.com"
      }
    }
  ]
}
```

**That's it!** The server automatically loads it. Test with:
```bash
curl http://localhost:8090/users/123
```

### Making Routes Dynamic

Use `{parameter}` in paths and `{{parameter}}` in responses:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/users/{userId}",
      "status": 200,
      "response": {
        "id": "{{userId}}",
        "name": "User {{userId}}",
        "message": "This is user number {{userId}}"
      }
    }
  ]
}
```

Now ANY user ID works:
- `/users/1` returns `{"id": "1", "name": "User 1"...}`
- `/users/999` returns `{"id": "999", "name": "User 999"...}`
- `/users/abc` returns `{"id": "abc", "name": "User abc"...}`

### Simulating Errors

Want to test error handling? Create error responses:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/users/666",
      "status": 404,
      "response": {
        "error": "User not found",
        "code": "USER_NOT_FOUND"
      }
    },
    {
      "method": "POST",
      "path": "/users",
      "status": 500,
      "response": {
        "error": "Database connection failed",
        "code": "DB_ERROR"
      }
    }
  ]
}
```

### Adding Delays

Simulate slow networks:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/slow-endpoint",
      "status": 200,
      "delay": 3000,
      "response": {
        "message": "This took 3 seconds"
      }
    }
  ]
}
```

---

## 🔧 Common Problems & Solutions

### Problem: "404 Not Found"
**Solution:** The route isn't configured. Check:
1. Is there a JSON file in `configs/` with that path?
2. Is the path exactly right? `/users` ≠ `/user`
3. Is the method right? GET ≠ POST

### Problem: "Connection Refused"
**Solution:** The server isn't running. Start it with:
```bash
go run cmd/main.go
```

### Problem: "No such file or directory"
**Solution:** You're in the wrong folder. Make sure you're in the project root where `go.mod` exists.

### Problem: Captures Not Saving
**Solution:** 
1. Make sure the proxy is running (`./run-capture-proxy.sh`)
2. Check you actually made some API calls
3. Run the save command: `curl http://localhost:8091/capture/save`

### Problem: Real APIs Not Being Called
**Solution:** The proxy needs real API URLs. Edit `run-capture-proxy.sh` and add your real API URLs.

---

## 📋 Cheat Sheet

### Essential Commands

| What You Want | Command |
|--------------|---------|
| Start mock server | `go run cmd/main.go` |
| Start capture proxy | `./run-capture-proxy.sh` |
| Create capture script | `./capture-real-apis.sh intercept` |
| Save captures | `curl http://localhost:8091/capture/save` |
| Check capture status | `curl http://localhost:8091/capture/status` |
| Test a mock endpoint | `curl http://localhost:8090/your-endpoint` |

### Port Reference

| Service | Port | URL |
|---------|------|-----|
| Mock Server | 8090 | http://localhost:8090 |
| Capture Proxy | 8091 | http://localhost:8091 |

### File Locations

| What | Where |
|------|-------|
| Mock configurations | `configs/*.json` |
| Captured responses | `captured/*.json` |
| Main mock server | `cmd/main.go` |
| Capture proxy | `cmd/capture/main.go` |

### JSON Route Template

Copy and modify this for new routes:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/your-endpoint/{id}",
      "status": 200,
      "delay": 0,
      "headers": {
        "Content-Type": "application/json"
      },
      "response": {
        "id": "{{id}}",
        "your": "data here"
      }
    }
  ]
}
```

---

## 🎓 Step-by-Step Tutorial: Your First Mock

Let's create a complete mock API for a todo list:

### 1. Create the Config File

Create `configs/todos.json`:

```json
{
  "routes": [
    {
      "method": "GET",
      "path": "/todos",
      "status": 200,
      "response": [
        {"id": 1, "title": "Buy milk", "done": false},
        {"id": 2, "title": "Walk dog", "done": true}
      ]
    },
    {
      "method": "GET",
      "path": "/todos/{id}",
      "status": 200,
      "response": {
        "id": "{{id}}",
        "title": "Todo item {{id}}",
        "done": false
      }
    },
    {
      "method": "POST",
      "path": "/todos",
      "status": 201,
      "response": {
        "id": 3,
        "title": "New todo",
        "done": false,
        "message": "Todo created successfully"
      }
    },
    {
      "method": "DELETE",
      "path": "/todos/{id}",
      "status": 204,
      "response": null
    }
  ]
}
```

### 2. Start the Server

```bash
go run cmd/main.go
```

### 3. Test Your Endpoints

```bash
# Get all todos
curl http://localhost:8090/todos

# Get specific todo
curl http://localhost:8090/todos/1

# Create a todo (mock always returns same response)
curl -X POST http://localhost:8090/todos

# Delete a todo
curl -X DELETE http://localhost:8090/todos/1
```

🎉 **Congratulations! You've created a complete mock API!**

---

## 💡 Pro Tips

1. **Keep configs organized** - One file per service (users.json, orders.json, etc.)
2. **Version your configs** - Add them to git so everyone has the same mocks
3. **Test error cases** - Add routes for 400, 401, 403, 404, 500 errors
4. **Use realistic data** - Copy from real API responses when possible
5. **Document special cases** - Add comments in a README about tricky endpoints

---

## 🆘 Need More Help?

1. **Check the main README.md** - More technical details
2. **Look at existing configs** - `configs/accounts-api.json` has examples
3. **Run with verbose logging** - See what's happening
4. **Ask for help** - Create an issue on GitHub

---

**Remember:** This is just a fake API for testing. It doesn't save data or talk to real databases. Every time you restart it, everything resets. That's the point - it's predictable and reliable for testing!