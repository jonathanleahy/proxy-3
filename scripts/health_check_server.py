#!/usr/bin/env python3
"""
Health check server for mitmproxy transparent proxy
Provides endpoints for monitoring proxy status and capture statistics
"""

import json
import os
import glob
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
import subprocess

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.health_check()
        elif self.path == '/capture/status':
            self.capture_status()
        elif self.path == '/cert/status':
            self.cert_status()
        elif self.path == '/iptables/status':
            self.iptables_status()
        else:
            self.send_error(404)
    
    def health_check(self):
        """Overall health check"""
        try:
            # Check if mitmproxy is running
            pid_file = '/tmp/mitmproxy.pid'
            mitm_running = False
            mitm_pid = None
            
            if os.path.exists(pid_file):
                with open(pid_file, 'r') as f:
                    mitm_pid = f.read().strip()
                    try:
                        os.kill(int(mitm_pid), 0)
                        mitm_running = True
                    except:
                        pass
            
            # Check capture directory
            capture_dir = '/captured'
            capture_count = len(glob.glob(f'{capture_dir}/*.json'))
            
            # Check certificate
            cert_exists = os.path.exists('/certs/mitmproxy-ca-cert.pem')
            
            response = {
                'status': 'healthy' if mitm_running else 'unhealthy',
                'timestamp': datetime.now().isoformat(),
                'checks': {
                    'mitmproxy': {
                        'running': mitm_running,
                        'pid': mitm_pid
                    },
                    'captures': {
                        'directory': capture_dir,
                        'file_count': capture_count
                    },
                    'certificate': {
                        'exists': cert_exists,
                        'path': '/certs/mitmproxy-ca-cert.pem'
                    }
                }
            }
            
            self.send_response(200 if mitm_running else 503)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except Exception as e:
            self.send_error(500, str(e))
    
    def capture_status(self):
        """Capture statistics"""
        try:
            capture_dir = '/captured'
            all_captured = f'{capture_dir}/all-captured.json'
            
            total_captures = 0
            latest_capture = None
            
            if os.path.exists(all_captured):
                with open(all_captured, 'r') as f:
                    data = json.load(f)
                    total_captures = len(data.get('routes', []))
                    latest_capture = data.get('last_updated')
            
            # Get recent files
            json_files = sorted(glob.glob(f'{capture_dir}/mitm_captured_*.json'), 
                              key=os.path.getmtime, reverse=True)[:5]
            
            recent_files = []
            for f in json_files:
                stat = os.stat(f)
                recent_files.append({
                    'name': os.path.basename(f),
                    'size': stat.st_size,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()
                })
            
            response = {
                'total_captures': total_captures,
                'latest_update': latest_capture,
                'recent_files': recent_files,
                'capture_directory': capture_dir
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except Exception as e:
            self.send_error(500, str(e))
    
    def cert_status(self):
        """Certificate status"""
        try:
            cert_path = '/certs/mitmproxy-ca-cert.pem'
            cert_exists = os.path.exists(cert_path)
            cert_info = {}
            
            if cert_exists:
                stat = os.stat(cert_path)
                cert_info = {
                    'exists': True,
                    'path': cert_path,
                    'size': stat.st_size,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'readable': os.access(cert_path, os.R_OK)
                }
            else:
                cert_info = {
                    'exists': False,
                    'path': cert_path
                }
            
            self.send_response(200 if cert_exists else 404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(cert_info, indent=2).encode())
            
        except Exception as e:
            self.send_error(500, str(e))
    
    def iptables_status(self):
        """iptables rules status"""
        try:
            result = subprocess.run(['iptables', '-t', 'nat', '-L', 'OUTPUT', '-v', '-n'],
                                  capture_output=True, text=True)
            
            rules = []
            for line in result.stdout.split('\n'):
                if 'REDIRECT' in line and ('80' in line or '443' in line):
                    parts = line.split()
                    if len(parts) >= 2:
                        rules.append({
                            'packets': parts[0],
                            'bytes': parts[1],
                            'rule': ' '.join(parts[2:])
                        })
            
            response = {
                'rules_active': len(rules) > 0,
                'redirect_rules': rules
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except Exception as e:
            self.send_error(500, str(e))
    
    def log_message(self, format, *args):
        """Override to reduce verbosity"""
        if '/health' not in args[0]:
            super().log_message(format, *args)

if __name__ == '__main__':
    port = int(os.environ.get('HEALTH_PORT', '8085'))
    server = HTTPServer(('0.0.0.0', port), HealthCheckHandler)
    print(f"🏥 Health check server running on port {port}", flush=True)
    print(f"   GET /health - Overall health status", flush=True)
    print(f"   GET /capture/status - Capture statistics", flush=True)
    print(f"   GET /cert/status - Certificate status", flush=True)
    print(f"   GET /iptables/status - iptables rules status", flush=True)
    server.serve_forever()