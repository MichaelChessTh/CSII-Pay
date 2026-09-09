#!/usr/bin/env python3
"""
CSII-Pay Cloudflare Tunnel Supervisor
1. Launches the multi-node Gateway proxy on port 8080 (if not already running).
2. Starts Cloudflare Quick Tunnel to expose the gateway publicly.
3. Automatically parses the dynamic https://*.trycloudflare.com URL.
4. Registers the active URL in Firebase Firestore (network_config/gateway).
5. Maintains heartbeats and cleans up on shutdown.
"""

import os
import re
import sys
import time
import signal
import datetime
import threading
import subprocess
import urllib.request
import urllib.error
import json
import ssl

try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass

def _get_ssl_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl.create_default_context()
    except Exception:
        pass
    return ssl._create_unverified_context()

FIRESTORE_GATEWAY_DOC = "https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/network_config/gateway"
GATEWAY_PORT = 8080

class TunnelManager:
    def __init__(self):
        self.tunnel_process = None
        self.gateway_process = None
        self.current_url = None
        self.running = True
        self.ssl_ctx = _get_ssl_context()

    def publish_to_firestore(self, url, status="online"):
        try:
            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
            payload = json.dumps({
                "fields": {
                    "url": {"stringValue": url},
                    "updated_at": {"timestampValue": now_iso},
                    "status": {"stringValue": status}
                }
            }).encode("utf-8")
            req = urllib.request.Request(
                FIRESTORE_GATEWAY_DOC,
                data=payload,
                method="PATCH",
                headers={"Content-Type": "application/json"}
            )
            try:
                with urllib.request.urlopen(req, timeout=5.0, context=self.ssl_ctx) as resp:
                    if resp.status in (200, 204):
                        print(f"[{time.strftime('%H:%M:%S')}] ✓ Published gateway URL to Firestore: {url} ({status})")
                        return True
            except Exception as ssl_err:
                if "CERTIFICATE_VERIFY_FAILED" in str(ssl_err) or "certificate verify failed" in str(ssl_err):
                    self.ssl_ctx = ssl._create_unverified_context()
                    with urllib.request.urlopen(req, timeout=5.0, context=self.ssl_ctx) as resp:
                        if resp.status in (200, 204):
                            print(f"[{time.strftime('%H:%M:%S')}] ✓ Published gateway URL to Firestore: {url} ({status})")
                            return True
                raise ssl_err
        except Exception as e:
            print(f"[{time.strftime('%H:%M:%S')}] ⚠ Failed to publish to Firestore: {e}")
            return False

    def is_gateway_running(self):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{GATEWAY_PORT}/gateway/status")
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                return resp.status == 200
        except Exception:
            return False

    def start_gateway(self):
        if self.is_gateway_running():
            print(f"[{time.strftime('%H:%M:%S')}] Gateway already running on port {GATEWAY_PORT}")
            return
        print(f"[{time.strftime('%H:%M:%S')}] Launching gateway.py on port {GATEWAY_PORT}...")
        self.gateway_process = subprocess.Popen(
            [sys.executable, "gateway.py", str(GATEWAY_PORT)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        for _ in range(10):
            time.sleep(0.5)
            if self.is_gateway_running():
                print(f"[{time.strftime('%H:%M:%S')}] ✓ Gateway started successfully")
                return
        print(f"[{time.strftime('%H:%M:%S')}] Warning: Gateway took longer than expected to initialize")

    def _heartbeat_loop(self):
        while self.running:
            time.sleep(45)
            if self.current_url and self.running:
                self.publish_to_firestore(self.current_url, status="online")

    def start_tunnel(self):
        self.start_gateway()

        cloudflared_bin = "cloudflared"
        # Check standard brew location if not in PATH
        if not subprocess.run(["which", "cloudflared"], capture_output=True).returncode == 0:
            if os.path.exists("/opt/homebrew/bin/cloudflared"):
                cloudflared_bin = "/opt/homebrew/bin/cloudflared"
            else:
                print("Error: cloudflared binary not found! Install via: brew install cloudflared")
                return

        print(f"[{time.strftime('%H:%M:%S')}] Starting Cloudflare Quick Tunnel to http://127.0.0.1:{GATEWAY_PORT}...")
        cmd = [cloudflared_bin, "tunnel", "--url", f"http://127.0.0.1:{GATEWAY_PORT}"]
        
        self.tunnel_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        url_regex = re.compile(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
        url_found = False

        # Start background heartbeat thread
        hb_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        hb_thread.start()

        try:
            for line in self.tunnel_process.stdout:
                line_str = line.strip()
                if not url_found:
                    match = url_regex.search(line_str)
                    if match:
                        self.current_url = match.group(0)
                        url_found = True
                        print("\n" + "=" * 65)
                        print(f"⚡ CLOUDFLARE TUNNEL ONLINE ⚡")
                        print(f"Public Gateway URL: {self.current_url}")
                        print(f"Target Load Balancer: http://127.0.0.1:{GATEWAY_PORT}")
                        print("=" * 65 + "\n")
                        
                        # Save to local scratch
                        os.makedirs("scratch", exist_ok=True)
                        with open("scratch/gateway_url.txt", "w") as f:
                            f.write(self.current_url + "\n")

                        # Publish to Cloud Firestore
                        self.publish_to_firestore(self.current_url, status="online")
                # Suppress spammy lines, print key ones
                if "Registered tunnel connection" in line_str or "Connection" in line_str and "registered" in line_str:
                    print(f"[{time.strftime('%H:%M:%S')}] Cloudflare: {line_str}")
        except KeyboardInterrupt:
            print("\nShutting down tunnel...")
        finally:
            self.shutdown()

    def shutdown(self):
        self.running = False
        if self.current_url:
            print(f"[{time.strftime('%H:%M:%S')}] Marking gateway offline in Firestore...")
            self.publish_to_firestore(self.current_url, status="offline")
        if self.tunnel_process:
            self.tunnel_process.terminate()
            try:
                self.tunnel_process.wait(timeout=3)
            except Exception:
                self.tunnel_process.kill()
        if self.gateway_process:
            self.gateway_process.terminate()
        print(f"[{time.strftime('%H:%M:%S')}] Tunnel manager terminated cleanly.")


def main():
    manager = TunnelManager()

    def handle_sig(sig, frame):
        manager.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)
    manager.start_tunnel()


if __name__ == "__main__":
    main()
