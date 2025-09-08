#!/usr/bin/env python3
"""
Improved mitmproxy script to capture HTTP/HTTPS traffic with better saving and monitoring.
Features:
- Automatic flushing of output
- Periodic saving (time-based and count-based)
- Signal handling for graceful shutdown
- Better error handling
- File permission management
"""

import json
import time
import os
import sys
import signal
import threading
from datetime import datetime
from pathlib import Path
from mitmproxy import http

class ImprovedCaptureAddon:
    def __init__(self):
        self.captures = []
        self.output_dir = os.environ.get('OUTPUT_DIR', '/captured')
        self.save_interval = int(os.environ.get('SAVE_INTERVAL', '30'))  # seconds
        self.save_count = int(os.environ.get('SAVE_COUNT', '10'))  # number of captures
        self.last_save_time = time.time()
        self.capture_count = 0
        self.total_captured = 0
        
        # Ensure output directory exists with proper permissions
        Path(self.output_dir).mkdir(parents=True, exist_ok=True)
        os.chmod(self.output_dir, 0o755)
        
        print(f"🎯 Improved mitmproxy capture addon initialized", flush=True)
        print(f"📁 Output directory: {self.output_dir}", flush=True)
        print(f"⏰ Save interval: {self.save_interval}s or every {self.save_count} captures", flush=True)
        
        # Set up signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGUSR1, self._signal_handler)
        
        # Start periodic save timer
        self._start_timer()
        
    def _signal_handler(self, signum, frame):
        """Handle signals for graceful shutdown"""
        print(f"📍 Received signal {signum}, saving captures...", flush=True)
        self.save_captures(force=True)
        if signum in [signal.SIGTERM, signal.SIGINT]:
            sys.exit(0)
    
    def _start_timer(self):
        """Start periodic save timer"""
        def timer_callback():
            while True:
                time.sleep(self.save_interval)
                if self.captures:
                    print(f"⏰ Timer triggered save after {self.save_interval}s", flush=True)
                    self.save_captures()
        
        timer_thread = threading.Thread(target=timer_callback, daemon=True)
        timer_thread.start()
    
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
                    if len(str(request_body)) > 10000:
                        request_body = str(request_body)[:10000] + "... (truncated)"
            
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
                    # Check for numeric IDs or UUID-like strings
                    if part.isdigit() or (len(part) == 36 and part.count('-') == 4):
                        parts[i] = '{id}'
                normalized_path = '/' + '/'.join(parts)
            
            # Create capture in the same format as the Go proxy
            capture = {
                'method': flow.request.method,
                'path': normalized_path,
                'original_path': flow.request.path,
                'status': flow.response.status_code,
                'response': response_body,
                'headers': response_headers,
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
            self.capture_count += 1
            self.total_captured += 1
            
            print(f"✅ [{self.total_captured}] Captured: {flow.request.method} {flow.request.path} -> {flow.response.status_code} ({response_time}ms)", flush=True)
            
            # Check if we should save based on count
            if self.capture_count >= self.save_count:
                print(f"📊 Reached {self.save_count} captures, triggering save", flush=True)
                self.save_captures()
                
        except Exception as e:
            print(f"❌ Error capturing flow: {e}", flush=True)
            import traceback
            traceback.print_exc()
    
    def save_captures(self, force=False):
        """Save captures to JSON file"""
        if not self.captures:
            if force:
                print("📭 No captures to save", flush=True)
            return
        
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = os.path.join(self.output_dir, f'mitm_captured_{timestamp}.json')
            
            output = {
                'routes': self.captures,
                'captured_via': 'mitmproxy_improved',
                'timestamp': datetime.now().isoformat(),
                'total_captures': len(self.captures)
            }
            
            # Write with proper permissions
            with open(filename, 'w') as f:
                json.dump(output, f, indent=2, default=str)
            os.chmod(filename, 0o644)
            
            print(f"💾 Saved {len(self.captures)} captures to {filename}", flush=True)
            
            # Also update the all-captured.json file
            all_captured = os.path.join(self.output_dir, 'all-captured.json')
            
            # Load existing captures if file exists
            existing_captures = []
            if os.path.exists(all_captured):
                try:
                    with open(all_captured, 'r') as f:
                        existing_data = json.load(f)
                        existing_captures = existing_data.get('routes', [])
                except:
                    pass
            
            # Append new captures
            all_output = {
                'routes': existing_captures + self.captures,
                'captured_via': 'mitmproxy_improved',
                'last_updated': datetime.now().isoformat(),
                'total_captures': len(existing_captures) + len(self.captures)
            }
            
            with open(all_captured, 'w') as f:
                json.dump(all_output, f, indent=2, default=str)
            os.chmod(all_captured, 0o644)
            
            print(f"📋 Updated all-captured.json (total: {all_output['total_captures']} captures)", flush=True)
            
            # Clear captures after saving
            self.captures = []
            self.capture_count = 0
            self.last_save_time = time.time()
            
        except Exception as e:
            print(f"❌ Error saving captures: {e}", flush=True)
            import traceback
            traceback.print_exc()
    
    def done(self):
        """Called when mitmproxy is shutting down"""
        print("🏁 mitmproxy capture addon shutting down, saving final captures...", flush=True)
        self.save_captures(force=True)
        print(f"📊 Total captures in session: {self.total_captured}", flush=True)

# Create addon instance
addons = [ImprovedCaptureAddon()]