#!/usr/bin/env python3
"""
mitmproxy script to capture HTTP/HTTPS traffic in the same format as the Go proxy.
This allows full HTTPS content capture with automatic certificate generation.
"""

import json
import time
import os
from datetime import datetime
from pathlib import Path
from mitmproxy import http
from mitmproxy.net.http import Headers

class CaptureAddon:
    def __init__(self):
        self.captures = []
        self.output_dir = os.environ.get('OUTPUT_DIR', '/captured')
        Path(self.output_dir).mkdir(parents=True, exist_ok=True)
        print(f"🎯 mitmproxy capture addon initialized")
        print(f"📁 Output directory: {self.output_dir}")
        
    def request(self, flow: http.HTTPFlow) -> None:
        """Called when a request is received"""
        flow.request_time = time.time()
    
    def response(self, flow: http.HTTPFlow) -> None:
        """Called when a response is received"""
        try:
            # Calculate response time
            response_time = int((time.time() - flow.request_time) * 1000) if hasattr(flow, 'request_time') else 0
            
            # Parse request body
            request_body = None
            if flow.request.content:
                try:
                    request_body = json.loads(flow.request.content)
                except:
                    request_body = flow.request.text or flow.request.content.decode('utf-8', errors='ignore')
            
            # Parse response body
            response_body = None
            if flow.response.content:
                try:
                    response_body = json.loads(flow.response.content)
                except:
                    # If not JSON, store as string (truncate if too long)
                    body_str = flow.response.text or flow.response.content.decode('utf-8', errors='ignore')
                    if len(body_str) > 10000:
                        body_str = body_str[:10000] + "... (truncated)"
                    response_body = body_str
            
            # Extract query parameters
            query_params = {}
            if flow.request.query:
                query_params = dict(flow.request.query)
            
            # Convert headers to dict
            request_headers = dict(flow.request.headers)
            response_headers = dict(flow.response.headers)
            
            # Normalize path for template (replace IDs with {id})
            path = flow.request.path_components
            normalized_path = flow.request.path
            if path:
                parts = list(path)
                for i, part in enumerate(parts):
                    if part.isdigit() or len(part) == 36:  # UUID-like
                        parts[i] = '{id}'
                normalized_path = '/' + '/'.join(parts)
            
            # Create capture in the same format as the Go proxy
            capture = {
                'method': flow.request.method,
                'path': normalized_path,
                'status': flow.response.status_code,
                'response': response_body,
                'headers': response_headers,  # For backward compatibility
                'description': f'Captured via mitmproxy from {flow.request.host}',
                'captured_at': datetime.now().isoformat(),
                'request_body': request_body,
                # Extended details
                'full_url': flow.request.pretty_url,
                'response_headers': response_headers,
                'request_headers': request_headers,
                'query_params': query_params,
                'response_time_ms': response_time,
                'host': flow.request.host,
            }
            
            self.captures.append(capture)
            print(f"✅ Captured: {flow.request.method} {flow.request.path} -> {flow.response.status_code} ({response_time}ms)")
            
            # Auto-save every 10 captures
            if len(self.captures) % 10 == 0:
                self.save_captures()
                
        except Exception as e:
            print(f"❌ Error capturing flow: {e}")
    
    def save_captures(self):
        """Save captures to JSON file"""
        if not self.captures:
            print("No captures to save")
            return
            
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = os.path.join(self.output_dir, f'mitm_captured_{timestamp}.json')
        
        output = {
            'routes': self.captures,
            'captured_via': 'mitmproxy',
            'timestamp': datetime.now().isoformat()
        }
        
        with open(filename, 'w') as f:
            json.dump(output, f, indent=2, default=str)
        
        print(f"💾 Saved {len(self.captures)} captures to {filename}")
        
        # Also save to the standard all-captured.json for compatibility
        all_captured = os.path.join(self.output_dir, 'all-captured.json')
        with open(all_captured, 'w') as f:
            json.dump(output, f, indent=2, default=str)
        
    def done(self):
        """Called when mitmproxy is shutting down"""
        self.save_captures()
        print("🏁 mitmproxy capture addon shutting down")

addons = [CaptureAddon()]