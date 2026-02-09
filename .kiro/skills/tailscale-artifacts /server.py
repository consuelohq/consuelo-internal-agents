#!/usr/bin/env python3
"""artifact server — serves files + /api/list endpoint for the index page."""
import http.server, json, os, pathlib

DIR = pathlib.Path(os.environ.get("ARTIFACTS_DIR", os.getcwd()))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(DIR), **kw)

    def do_GET(self):
        if self.path == "/api/list":
            htmls = [f for f in DIR.glob("*.html") if f.name != "index.html"]
            htmls.sort(key=lambda f: f.stat().st_mtime, reverse=True)
            files = [f.name for f in htmls]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(files).encode())
        else:
            super().do_GET()

if __name__ == "__main__":
    s = http.server.HTTPServer(("127.0.0.1", 8445), Handler)
    print(f"serving {DIR} on http://127.0.0.1:8445")
    s.serve_forever()
