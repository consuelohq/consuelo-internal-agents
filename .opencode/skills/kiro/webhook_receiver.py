#!/usr/bin/env python3
"""
Linear Agent Webhook Receiver

POST /webhook/linear  — AgentSessionEvent (created/prompted/stopped)
GET  /oauth/callback   — OAuth code exchange
GET  /health           — health check

No external deps — uses http.server + urllib.
"""

import hashlib
import hmac
import json
import os
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

# paths
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
SKILLS_ROOT = os.path.dirname(SKILL_DIR)
sys.path.insert(0, SKILL_DIR)
sys.path.insert(0, os.path.join(SKILLS_ROOT, "kiro-acp"))
sys.path.insert(0, os.path.join(SKILLS_ROOT, "github-dev"))

# ── config ───────────────────────────────────────────────────────────────────

def _load_config():
    result = subprocess.run(
        ["bash", "-c", f"set -a && source {SKILL_DIR}/config.sh && env"],
        capture_output=True, text=True,
    )
    env = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            env[k] = v
    return env

_cfg = _load_config()

def _c(key): return os.getenv(key, _cfg.get(key, ""))

PORT = int(_c("WEBHOOK_PORT") or "8847")
WEBHOOK_SECRET = _c("LINEAR_WEBHOOK_SECRET")
OAUTH_CLIENT_ID = _c("LINEAR_OAUTH_CLIENT_ID")
OAUTH_CLIENT_SECRET = _c("LINEAR_OAUTH_CLIENT_SECRET")
OAUTH_CALLBACK_URL = _c("LINEAR_OAUTH_CALLBACK_URL")
TOKEN_FILE = os.path.join(SKILL_DIR, ".oauth-token.json")

# active kiro sessions: agent_session_id -> Thread
_sessions: dict = {}

# ── linear API helpers ───────────────────────────────────────────────────────

def _get_token() -> str:
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            t = json.load(f).get("access_token")
            if t: return t
    return _c("LINEAR_API_KEY")


def _gql(query: str, variables: dict = None) -> dict:
    token = _get_token()
    if not token:
        raise RuntimeError("no linear token")
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    auth = f"Bearer {token}" if "oauth" in token else token
    req = urllib.request.Request(
        "https://api.linear.app/graphql", data=payload,
        headers={"Authorization": auth, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def send_thought(sid, body, ephemeral=False):
    _send_activity(sid, {"type": "thought", "body": body}, ephemeral)

def send_action(sid, action, parameter, result=None, ephemeral=False):
    c = {"type": "action", "action": action, "parameter": parameter}
    if result: c["result"] = result
    _send_activity(sid, c, ephemeral)

def send_response(sid, body):
    _send_activity(sid, {"type": "response", "body": body})

def send_error(sid, body):
    _send_activity(sid, {"type": "error", "body": body})

def update_plan(sid, steps):
    """steps: [{"content": "...", "status": "pending|inProgress|completed|canceled"}]"""
    m = """mutation($id: String!, $input: AgentSessionUpdateInput!) {
        agentSessionUpdate(id: $id, input: $input) { success }
    }"""
    _gql(m, {"id": sid, "input": {"plan": steps}})

def _send_activity(sid, content, ephemeral=False):
    m = """mutation($input: AgentActivityCreateInput!) {
        agentActivityCreate(input: $input) { success agentActivity { id } }
    }"""
    inp = {"agentSessionId": sid, "content": content}
    if ephemeral: inp["ephemeral"] = True
    try:
        r = _gql(m, {"input": inp})
        if r.get("errors"):
            print(f"[activity-err] {r['errors']}", flush=True)
    except Exception as e:
        print(f"[activity-err] {e}", flush=True)


# ── signature verification ───────────────────────────────────────────────────

def verify_sig(body: bytes, sig: str) -> bool:
    if not WEBHOOK_SECRET: return True
    expected = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)


# ── kiro session spawning ───────────────────────────────────────────────────

def spawn_kiro(session_id: str, issue: dict, prompt_context: str):
    def _run():
        try:
            send_thought(session_id, "reading the task and codebase...")

            from kiro_agent import run_coding_task

            identifier = issue.get("identifier", "UNKNOWN")
            title = issue.get("title", "untitled")
            desc = issue.get("description", "")

            task = f"{identifier}: {title}\n\n{desc}"
            if prompt_context:
                task += f"\n\n## context from linear\n{prompt_context}"

            slug = title[:30].lower().replace(" ", "-").replace("/", "-")
            branch = f"kiro/{identifier.lower()}-{slug}"

            plan = [
                {"content": "read codebase", "status": "inProgress"},
                {"content": "implement changes", "status": "pending"},
                {"content": "commit & create PR", "status": "pending"},
            ]
            update_plan(session_id, plan)
            send_action(session_id, "spawning kiro", parameter=f"branch: {branch}")

            result = run_coding_task(
                task_description=task,
                branch_name=branch,
                linear_task_id=identifier,
                on_progress=lambda msg: send_thought(session_id, msg),
            )

            plan[0]["status"] = "completed"
            plan[1]["status"] = "completed"
            plan[2]["status"] = "completed"
            update_plan(session_id, plan)

            summary = result.get("response", "done")[:3000]
            send_response(session_id, summary)

        except Exception as e:
            send_error(session_id, f"kiro failed: {e}")
        finally:
            _sessions.pop(session_id, None)

    t = threading.Thread(target=_run, daemon=True)
    _sessions[session_id] = t
    t.start()


# ── HTTP handler ─────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)

        if p.path == "/health":
            self._json(200, {"status": "ok", "active_sessions": len(_sessions)})

        elif p.path == "/oauth/callback":
            code = urllib.parse.parse_qs(p.query).get("code", [None])[0]
            if not code:
                self._json(400, {"error": "missing code"})
                return
            try:
                token = self._exchange_code(code)
                with open(TOKEN_FILE, "w") as f:
                    json.dump(token, f, indent=2)
                self._json(200, {"status": "authorized", "scope": token.get("scope", "")})
                print(f"[oauth] token saved", flush=True)
            except Exception as e:
                self._json(500, {"error": str(e)})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/webhook/linear":
            self._json(404, {"error": "not found"})
            return

        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        if not verify_sig(body, self.headers.get("Linear-Signature", "")):
            self._json(401, {"error": "bad signature"})
            return

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self._json(400, {"error": "bad json"})
            return

        action = payload.get("action", "")
        ptype = payload.get("type", "")
        print(f"[webhook] type={ptype} action={action}", flush=True)

        # respond fast — linear requires <5s response
        self._json(200, {"status": "accepted"})

        if ptype != "AgentSessionEvent":
            return

        # extract session id — could be at top level or nested
        sid = (payload.get("agentSession") or {}).get("id") or payload.get("agentSessionId")
        issue = (payload.get("agentSession") or {}).get("issue") or payload.get("issue") or {}
        prompt_context = payload.get("promptContext", "")

        if not sid:
            print(f"[webhook] no session id found in payload", flush=True)
            return

        if action == "created":
            spawn_kiro(sid, issue, prompt_context)

        elif action == "prompted":
            # user sent follow-up — message is in agentActivity.body
            msg = (payload.get("agentActivity") or {}).get("body") or prompt_context
            if sid in _sessions:
                send_thought(sid, "got your follow-up, processing...")
                # TODO: forward msg to running kiro session when we support multi-turn
            else:
                spawn_kiro(sid, issue, msg)

        elif action == "stopped":
            _sessions.pop(sid, None)

    def _json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _exchange_code(self, code):
        data = urllib.parse.urlencode({
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAUTH_CALLBACK_URL,
            "client_id": OAUTH_CLIENT_ID,
            "client_secret": OAUTH_CLIENT_SECRET,
        }).encode()
        req = urllib.request.Request(
            "https://api.linear.app/oauth/token", data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())

    def log_message(self, fmt, *args):
        print(f"[http] {args[0]}", flush=True)


def main():
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[webhook-receiver] listening on :{PORT}", flush=True)
    print(f"  POST /webhook/linear", flush=True)
    print(f"  GET  /oauth/callback", flush=True)
    print(f"  GET  /health", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[webhook-receiver] shutting down", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
