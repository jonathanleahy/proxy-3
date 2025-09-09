#!/usr/bin/env python3
"""
Mitmproxy script to capture HTTPS traffic content
Saves full request/response details to JSON files
"""

import json
import os
from datetime import datetime
from mitmproxy import http
import hashlib

class HTTPSCapture:
    def __init__(self):
        self.capture_dir = "/captured"
        os.makedirs(self.capture_dir, exist_ok=True)
        
    def request(self, flow: http.HTTPFlow) -> None:
        """Capture the request details"""
        flow.request_time = datetime.now().isoformat()
        
    def response(self, flow: http.HTTPFlow) -> None:
        """Capture full HTTPS request/response content"""
        
        # Build capture data
        capture = {
            "timestamp": datetime.now().isoformat(),
            "request": {
                "method": flow.request.method,
                "url": flow.request.pretty_url,
                "host": flow.request.host,
                "port": flow.request.port,
                "path": flow.request.path,
                "headers": dict(flow.request.headers),
                "body": flow.request.text if flow.request.text else None
            },
            "response": {
                "status_code": flow.response.status_code,
                "headers": dict(flow.response.headers),
                "body": flow.response.text if flow.response.text else None
            }
        }
        
        # Generate filename based on request
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        method = flow.request.method
        host = flow.request.host.replace(".", "_")
        path_hash = hashlib.md5(flow.request.path.encode()).hexdigest()[:8]
        
        filename = f"{timestamp}_{method}_{host}_{path_hash}.json"
        filepath = os.path.join(self.capture_dir, filename)
        
        # Save to file
        with open(filepath, 'w') as f:
            json.dump(capture, f, indent=2)
            
        print(f"✅ Captured: {flow.request.method} {flow.request.pretty_url}")
        print(f"   Saved to: {filename}")
        
        # Also create a summary file
        summary_file = os.path.join(self.capture_dir, "captures_summary.txt")
        with open(summary_file, 'a') as f:
            f.write(f"{datetime.now().isoformat()} - {flow.request.method} {flow.request.pretty_url}\n")

addons = [HTTPSCapture()]