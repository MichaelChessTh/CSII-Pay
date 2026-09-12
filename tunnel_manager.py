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
        return ssl._create_unverified_context()
    except Exception:
        pass
    return None

FIRESTORE_GATEWAY_DOC = "https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/network_config/gateway"
GATEWAY_PORT = 8080
COUNCIL_PORT = 5050
DEFAULT_CUSTOM_DOMAIN = "csiipay.app"

def get_local_ip() -> str:
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip

class TunnelManager:
    def __init__(self, custom_domain=DEFAULT_CUSTOM_DOMAIN, token=None, force_quick=False):
        self.custom_domain = custom_domain
        self.token = token
        self.force_quick = force_quick
        self.tunnel_process = None
        self.gateway_process = None
        self.portal_process = None
        self.current_url = None
        self.running = True
        self.ssl_ctx = _get_ssl_context()

    def publish_to_firestore(self, url, status="online"):
        try:
            lan_ip = get_local_ip()
            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
            payload = json.dumps({
                "fields": {
                    "url": {"stringValue": url},
                    "lan_url": {"stringValue": f"http://{lan_ip}:8000"},
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
                print(f"[{time.strftime('%H:%M:%S')}] ✓ Gateway started successfully (http://127.0.0.1:{GATEWAY_PORT})")
                return
        print(f"[{time.strftime('%H:%M:%S')}] Warning: Gateway took longer than expected to initialize")

    def is_portal_running(self):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{COUNCIL_PORT}/")
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                return resp.status in (200, 302)
        except Exception:
            return False

    def start_portal(self):
        if self.is_portal_running():
            print(f"[{time.strftime('%H:%M:%S')}] Council Portal already running on port {COUNCIL_PORT}")
            return
        print(f"[{time.strftime('%H:%M:%S')}] Launching council_portal.py on port {COUNCIL_PORT} (for faculty.csiipay.app)...")
        env = dict(os.environ)
        env["NODE_URL"] = f"http://127.0.0.1:{GATEWAY_PORT}"
        self.portal_process = subprocess.Popen(
            [sys.executable, "council_portal.py"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        for _ in range(10):
            time.sleep(0.5)
            if self.is_portal_running():
                print(f"[{time.strftime('%H:%M:%S')}] ✓ Council Portal started successfully (http://127.0.0.1:{COUNCIL_PORT})")
                return
        print(f"[{time.strftime('%H:%M:%S')}] Warning: Council Portal took longer than expected to initialize")

    def _heartbeat_loop(self):
        while self.running:
            time.sleep(45)
            if self.current_url and self.running:
                self.publish_to_firestore(self.current_url, status="online")

    def start_tunnel(self):
        self.start_gateway()
        self.start_portal()

        cloudflared_bin = "cloudflared"
        # Check standard brew location if not in PATH
        if not subprocess.run(["which", "cloudflared"], capture_output=True).returncode == 0:
            if os.path.exists("/opt/homebrew/bin/cloudflared"):
                cloudflared_bin = "/opt/homebrew/bin/cloudflared"
            else:
                print("Error: cloudflared binary not found! Install via: brew install cloudflared")
                return

        # Check for token in file if not passed
        if not self.token and os.path.exists("scratch/cloudflare_token.txt"):
            try:
                with open("scratch/cloudflare_token.txt", "r") as f:
                    tok = f.read().strip()
                    if tok:
                        self.token = tok
            except Exception:
                pass

        if self.token and not self.force_quick:
            # Dedicated Custom Domain Tunnel via Cloudflare Token
            print("\n" + "=" * 65)
            print("⚡ CLOUDFLARE MULTI-HOSTNAME CUSTOM TUNNEL ⚡")
            print("Target Ingress Routes:")
            print(f"  1. https://csiipay.app        --> http://127.0.0.1:{GATEWAY_PORT} (Web App + Gateway)")
            print(f"  2. https://api.csiipay.app    --> http://127.0.0.1:{GATEWAY_PORT} (Gateway API)")
            print(f"  3. https://faculty.csiipay.app--> http://127.0.0.1:{COUNCIL_PORT} (Council Portal)")
            print("=" * 65 + "\n")

            cmd = [cloudflared_bin, "tunnel", "run", "--token", self.token]
            self.current_url = f"https://{self.custom_domain}"
            os.makedirs("scratch", exist_ok=True)
            with open("scratch/gateway_url.txt", "w") as f:
                f.write(self.current_url + "\n")

            # Publish custom domain to Firestore immediately
            self.publish_to_firestore(self.current_url, status="online")

            # Start background heartbeat thread
            hb_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
            hb_thread.start()

            self.tunnel_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            try:
                for line in self.tunnel_process.stdout:
                    line_str = line.strip()
                    if "Registered tunnel connection" in line_str or "Connection" in line_str and "registered" in line_str:
                        print(f"[{time.strftime('%H:%M:%S')}] Cloudflare: {line_str}")
            except KeyboardInterrupt:
                print("\nShutting down tunnel...")
            finally:
                self.shutdown()
            return

        # Fallback / Quick Tunnel Mode
        if not self.token:
            print("\n" + "=" * 68)
            print("⚡ NOTICE: CUSTOM DOMAIN & HOSTNAME SETUP INSTRUCTIONS ⚡")
            print("In Cloudflare Dashboard -> Zero Trust -> Networks -> Tunnels:")
            print("Under your tunnel -> Public Hostnames tab, configure:")
            print(f"  1. csiipay.app         --> Service: HTTP://localhost:{GATEWAY_PORT} (Flutter Web)")
            print(f"  2. api.csiipay.app     --> Service: HTTP://localhost:{GATEWAY_PORT} (API Proxy)")
            print(f"  3. faculty.csiipay.app --> Service: HTTP://localhost:{COUNCIL_PORT} (Council Portal)")
            print("=" * 68)
            print("[*] Starting Quick Tunnel in the meantime...\n")

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
        if self.portal_process:
            self.portal_process.terminate()
        print(f"[{time.strftime('%H:%M:%S')}] Tunnel manager terminated cleanly.")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="CSII-Pay Cloudflare Tunnel Supervisor")
    parser.add_argument("--domain", default=DEFAULT_CUSTOM_DOMAIN, help="Custom domain for tunnel (default: csiipay.app or api.csiipay.app)")
    parser.add_argument("--token", default=os.getenv("CLOUDFLARE_TUNNEL_TOKEN", None), help="Cloudflare Tunnel Token")
    parser.add_argument("--quick", action="store_true", help="Force Quick Tunnel mode (trycloudflare.com)")
    args = parser.parse_args()

    manager = TunnelManager(custom_domain=args.domain, token=args.token, force_quick=args.quick)

    def handle_sig(sig, frame):
        manager.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)
    manager.start_tunnel()


if __name__ == "__main__":
    main()
