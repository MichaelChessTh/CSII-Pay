import os
import sys
import time
import random
import threading
import mimetypes
import urllib.request
import urllib.error
import urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

from auth import load_dotenv

DEFAULT_CANDIDATE_PORTS = [8000, 8001, 8002, 8003]
GATEWAY_PORT = 8080

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# Browser origins allowed to call the API. Empty = any origin (development only).
ALLOWED_ORIGINS = {o.strip() for o in os.environ.get("CSII_ALLOWED_ORIGINS", "").split(",") if o.strip()}
# Only claim HTTPS to the nodes when a TLS terminator (e.g. Cloudflare Tunnel) really sits in front.
TLS_TERMINATED = os.environ.get("CSII_GATEWAY_TLS_TERMINATED", "0") == "1"
# Client-supplied forwarding headers are never trusted; the gateway sets its own.
HOP_BY_HOP_OR_SPOOFABLE = ("host", "content-length", "forwarded", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host", "x-real-ip")
WEB_DIR = os.path.join(BASE_DIR, "csii_pay_app", "build", "web")
mimetypes.init()
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/css", ".css")
mimetypes.add_type("application/json", ".json")
mimetypes.add_type("font/ttf", ".ttf")
mimetypes.add_type("font/otf", ".otf")
mimetypes.add_type("font/woff", ".woff")
mimetypes.add_type("font/woff2", ".woff2")

API_ENDPOINTS = (
    "/status",
    "/account",
    "/accounts",
    "/operator",
    "/transactions",
    "/activity",
    "/marketplace",
    "/groups",
    "/mempool",
    "/gateway",
    "/peers",
    "/register",
    "/login",
    "/broadcast",
    "/escrow",
    "/orders",
    "/submit_transaction",
    "/chain",
    "/balance",
    "/order",
    "/tx",
    "/contracts",
    "/contract",
    "/auth",
)

class NodeRegistry:
    def __init__(self, candidate_ports):
        self.candidate_ports = candidate_ports
        self.healthy_ports = []
        self.lock = threading.Lock()
        self._running = True

    def start(self):
        t = threading.Thread(target=self._health_loop, daemon=True)
        t.start()

    def _check_node(self, port):
        url = f"http://127.0.0.1:{port}/status"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "CSII-Pay-Gateway/1.0"})
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                return resp.status == 200
        except Exception:
            return False

    def _health_loop(self):
        while self._running:
            active = []
            for port in self.candidate_ports:
                if self._check_node(port):
                    active.append(port)
            with self.lock:
                self.healthy_ports = active
            time.sleep(3.0)

    def get_random_node(self):
        with self.lock:
            ports = list(self.healthy_ports)
        if not ports:
            # Fallback quick scan if list empty
            for port in self.candidate_ports:
                if self._check_node(port):
                    ports.append(port)
        if not ports:
            return None
        return random.choice(ports)

    def get_all_healthy(self):
        with self.lock:
            return list(self.healthy_ports)


class GatewayHandler(BaseHTTPRequestHandler):
    registry: NodeRegistry = None

    def log_message(self, format, *args):
        # Custom clean logging
        pass

    def _send_cors_headers(self):
        origin = self.headers.get("Origin")
        if not origin:
            return
        if not ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", "*")
        elif origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        else:
            return
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Expose-Headers", "X-Routed-Node, X-Gateway")
        self.send_header("Access-Control-Max-Age", "600")

    def _is_api_path(self, path):
        clean = path.split("?")[0]
        return any(clean == ep or clean.startswith(ep + "/") or clean.startswith(ep + "?") for ep in API_ENDPOINTS)

    def _serve_static_file(self, file_path):
        try:
            mime_type, _ = mimetypes.guess_type(file_path)
            if not mime_type:
                mime_type = "application/octet-stream"
            with open(file_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", mime_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(content)
            return True
        except Exception as e:
            print(f"[Gateway] Error serving {file_path}: {e}")
            return False

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_HEAD(self):
        if self._is_api_path(self.path) or not os.path.exists(WEB_DIR):
            self._proxy_request("HEAD")
            return

        rel_path = urllib.parse.unquote(self.path.split("?")[0]).lstrip("/")
        if not rel_path:
            rel_path = "index.html"
        target_file = os.path.join(WEB_DIR, rel_path)
        if not os.path.isfile(target_file):
            target_file = os.path.join(WEB_DIR, "index.html")

        if os.path.isfile(target_file):
            mime_type, _ = mimetypes.guess_type(target_file)
            if not mime_type:
                mime_type = "application/octet-stream"
            file_size = os.path.getsize(target_file)
            self.send_response(200)
            self.send_header("Content-Type", mime_type)
            self.send_header("Content-Length", str(file_size))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self._send_cors_headers()
            self.end_headers()
        else:
            self._proxy_request("HEAD")

    def do_GET(self):
        if self.path == "/gateway/status":
            self._handle_gateway_status()
            return

        # If it's an API route or no web bundle exists, proxy to healthy node
        if self._is_api_path(self.path) or not os.path.exists(WEB_DIR):
            self._proxy_request("GET")
            return

        # Otherwise serve Flutter Web static assets or SPA index.html
        rel_path = urllib.parse.unquote(self.path.split("?")[0]).lstrip("/")
        if not rel_path:
            rel_path = "index.html"
        target_file = os.path.join(WEB_DIR, rel_path)

        if os.path.isfile(target_file):
            self._serve_static_file(target_file)
            return

        # SPA Fallback for browser client routing
        index_file = os.path.join(WEB_DIR, "index.html")
        if os.path.isfile(index_file):
            self._serve_static_file(index_file)
            return

        # Fallback to node proxy
        self._proxy_request("GET")

    def do_POST(self):
        self._proxy_request("POST")

    def do_PUT(self):
        self._proxy_request("PUT")

    def do_DELETE(self):
        self._proxy_request("DELETE")

    def _handle_gateway_status(self):
        healthy = self.registry.get_all_healthy()
        payload = f'{{"gateway": "online", "healthy_nodes": {healthy}, "strategy": "random_per_request"}}'.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(payload)

    def _proxy_request(self, method):
        target_port = self.registry.get_random_node()
        if not target_port:
            msg = b'{"error": "No healthy CSII-Pay nodes available on localhost"}'
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(msg)
            print(f"[{time.strftime('%H:%M:%S')}] {method} {self.path} -> 503 (No nodes alive)")
            return

        target_url = f"http://127.0.0.1:{target_port}{self.path}"
        
        # Read body if any
        content_length = self.headers.get("Content-Length")
        body = None
        if content_length:
            try:
                body = self.rfile.read(int(content_length))
            except Exception:
                body = None

        # Build forward request
        req = urllib.request.Request(target_url, data=body, method=method)
        for h, v in self.headers.items():
            if h.lower() not in HOP_BY_HOP_OR_SPOOFABLE:
                req.add_header(h, v)
        req.add_header("X-Forwarded-For", self.client_address[0])
        req.add_header("X-Forwarded-Proto", "https" if TLS_TERMINATED else "http")
        req.add_header("User-Agent", self.headers.get("User-Agent", "CSII-Pay-Gateway"))

        try:
            with urllib.request.urlopen(req, timeout=10.0) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                for h, v in resp.headers.items():
                    if h.lower() not in ("transfer-encoding", "content-length") and not h.lower().startswith("access-control-"):
                        self.send_header(h, v)
                self.send_header("Content-Length", str(len(resp_body)))
                self.send_header("X-Routed-Node", str(target_port))
                self.send_header("X-Gateway", "CSII-Pay-LoadBalancer")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(resp_body)
                print(f"[{time.strftime('%H:%M:%S')}] {method} {self.path} -> Node :{target_port} ({resp.status})")
        except urllib.error.HTTPError as e:
            err_body = e.read()
            self.send_response(e.code)
            for h, v in e.headers.items():
                if h.lower() not in ("transfer-encoding", "content-length") and not h.lower().startswith("access-control-"):
                    self.send_header(h, v)
            self.send_header("Content-Length", str(len(err_body)))
            self.send_header("X-Routed-Node", str(target_port))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(err_body)
            print(f"[{time.strftime('%H:%M:%S')}] {method} {self.path} -> Node :{target_port} ({e.code})")
        except Exception as e:
            err_msg = f'{{"error": "Failed to connect to node {target_port}: {str(e)}"}}'.encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_msg)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(err_msg)
            print(f"[{time.strftime('%H:%M:%S')}] {method} {self.path} -> Node :{target_port} (502: {e})")


def run_gateway(port=GATEWAY_PORT, candidate_ports=None):
    if candidate_ports is None:
        candidate_ports = DEFAULT_CANDIDATE_PORTS
    registry = NodeRegistry(candidate_ports)
    registry.start()
    
    # Wait 1s for initial health scan
    time.sleep(1.0)
    print(f"=== CSII-Pay Gateway starting on http://127.0.0.1:{port} ===")
    print(f"Candidate ports: {candidate_ports}")
    if not ALLOWED_ORIGINS:
        print("[!] WARNING: CSII_ALLOWED_ORIGINS is not set; CORS allows any origin.")
    if not TLS_TERMINATED:
        print("[!] Gateway is serving plain HTTP. Put it behind TLS before exposing it (CSII_GATEWAY_TLS_TERMINATED=1 once done).")
    print(f"Initial healthy nodes: {registry.get_all_healthy()}")

    GatewayHandler.registry = registry
    server = ThreadingHTTPServer(("0.0.0.0", port), GatewayHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping gateway...")
        server.server_close()


if __name__ == "__main__":
    p = int(sys.argv[1]) if len(sys.argv) > 1 else GATEWAY_PORT
    run_gateway(p)
