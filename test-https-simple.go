package main

import (
    "fmt"
    "os/exec"
    "log"
)

func main() {
    log.Println("Testing HTTPS capture with curl...")
    
    cmd := exec.Command("wget", "-q", "-O", "-", "https://api.github.com/users/github")
    output, err := cmd.CombinedOutput()
    
    if err != nil {
        log.Printf("Error: %v\n", err)
        log.Printf("Output: %s\n", output)
    } else {
        fmt.Printf("Success! Response length: %d bytes\n", len(output))
        if len(output) > 200 {
            fmt.Printf("First 200 chars: %s...\n", string(output[:200]))
        }
    }
}
