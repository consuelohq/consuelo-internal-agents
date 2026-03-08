#!/usr/bin/env python3
"""Linear webhook relay — receives webhooks, queues in Redis."""
import hashlib, hmac, json, os
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request

REDIS_URL = os.environ["REDIS_URL"]
WEBHOOK_SECRET = os.environ.get("LINEAR_WEBHOOK_SECRET", "")
PORT = int(os.environ.get("PORT", "8080"))

# minimal redis client (no deps) — just LPUSH and RPOP via RESP protocol
import socket

class Redis:
    def __init__(self, url):
        from urllib.parse import urlparse
        p = urlparse(url)
        self.host, self.port = p.hostname, p.port or 6379
        self.password = p.password
    def _cmd(self, *args):
        s = socket.create_connection((self.host, self.port), timeout=5)
        try:
            cmd = f"*{len(args)}\r\n"
            for a in args:
                a = str(a)
                cmd += f"${len(a)}\r\n{a}\r\n"
            if self.password:
                auth = f"*2\r\n$4\r\nAUTH\r\n${len(self.password)}\r\n{self.password}\r\n"
                s.sendall(auth.encode())
                s.recv(1024)
            s.sendall(cmd.encode())
            return s.recv(65536).decode()
        finally:
            s.close()
    def lpush(self, key, val): self._cmd("LPUSH", key, val)
    def rpop(self, key):
        r = self._cmd("RPOP", key)
        if r.startswith("$-1"): return None
        lines = r.split("\r\n")
        return lines[1] if len(lines) > 1 else None

redis = Redis(REDIS_URL)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/webhook/linear":
            return self._json(404, {"error": "not found"})
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if WEBHOOK_SECRET:
            sig = self.headers.get("Linear-Signature", "")
            expected = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected, sig):
                return self._json(401, {"error": "bad sig"})
        payload = json.loads(body)
        self._json(200, {"status": "accepted"})
        if payload.get("type") == "AgentSessionEvent":
            redis.lpush("kiro:webhooks", body.decode())
            print(f"[queued] {payload.get('action')} session={payload.get('agentSession',{}).get('id','?')}", flush=True)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok"})
        if self.path == "/tasks/pending":
            item = redis.rpop("kiro:webhooks")
            if item:
                return self._json(200, json.loads(item))
            return self._json(204, None)
        self._json(404, {"error": "not found"})

    def _json(self, code, data):
        body = json.dumps(data).encode() if data else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body: self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[http] {args[0]}", flush=True)

if __name__ == "__main__":
    print(f"[relay] listening on :{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
