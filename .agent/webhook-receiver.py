#!/usr/bin/env python3
"""
Linear Agent Webhook Receiver

Two modes:
  @mention in comment → kiro-cli chat (non-interactive, per turn)
  assign/delegate     → run-tasks.sh in tmux session "dev"

POST /webhook/linear  — AgentSessionEvent
GET  /oauth/callback   — OAuth code exchange
GET  /health           — health check

No external deps — stdlib only.
"""

import hashlib, hmac, json, os, re, subprocess, sys, threading, time
import urllib.error, urllib.parse, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── config ───────────────────────────────────────────────────────────────────

def _load_config():
    r = subprocess.run(
        ["bash", "-c", f"set -a && source {SCRIPT_DIR}/config.sh && env"],
        capture_output=True, text=True,
    )
    env = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            env[k] = v
    return env

_cfg = _load_config()
def _c(key): return os.getenv(key, _cfg.get(key, ""))

PORT = int(_c("WEBHOOK_PORT") or "8848")
WEBHOOK_SECRET = _c("LINEAR_WEBHOOK_SECRET")
OAUTH_CLIENT_ID = _c("LINEAR_OAUTH_CLIENT_ID")
OAUTH_CLIENT_SECRET = _c("LINEAR_OAUTH_CLIENT_SECRET")
OAUTH_CALLBACK_URL = _c("LINEAR_OAUTH_CALLBACK_URL")
TOKEN_FILE = os.path.join(SCRIPT_DIR, ".oauth-token.json")
KIRO_CLI = os.environ.get("KIRO_CLI", "kiro-cli")
TMUX = "/opt/homebrew/bin/tmux"
TMUX_SESSION = "dev"
TMUX_MENTION = "linear"
MENTION_DIR = "/tmp/kiro-mentions"
GITHUB_WEBHOOK_SECRET = _c("GITHUB_WEBHOOK_SECRET")
LINEAR_API_KEY = _c("LINEAR_API_KEY")
REVIEW_LABEL = _c("LINEAR_REVIEW_LABEL_ID")   # [review]
OPENSAAS_LABEL = _c("LINEAR_OPENSAAS_LABEL_ID") # opensaas
TEAM_ID = _c("LINEAR_TEAM_ID")
TRIAGE_STATE = _c("LINEAR_TRIAGE_STATE_ID")
REVIEW_BOTS = {"coderabbitai[bot]": "CodeRabbit", "qodo-code-review[bot]": "Qodo"}
_running: dict = {}  # session_id -> {"pid": str, "output": path, "done": path}
_pending_reviews: dict = {}  # (pr_number, bot_login) -> timestamp

# ── linear API ───────────────────────────────────────────────────────────────

def _refresh_oauth_token():
    """refresh the oauth token using the refresh_token grant."""
    if not os.path.exists(TOKEN_FILE):
        return None
    with open(TOKEN_FILE) as f:
        old = json.load(f)
    rt = old.get("refresh_token")
    if not rt or not OAUTH_CLIENT_ID or not OAUTH_CLIENT_SECRET:
        return None
    try:
        data = urllib.parse.urlencode({
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": OAUTH_CLIENT_ID,
            "client_secret": OAUTH_CLIENT_SECRET,
        }).encode()
        req = urllib.request.Request(
            "https://api.linear.app/oauth/token", data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req) as resp:
            new_token = json.loads(resp.read())
        with open(TOKEN_FILE, "w") as f:
            json.dump(new_token, f, indent=2)
        print(f"[oauth] token refreshed", flush=True)
        return new_token.get("access_token")
    except Exception as e:
        print(f"[oauth-refresh-err] {e}", flush=True)
        return None

def _get_token():
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            data = json.load(f)
        t = data.get("access_token")
        if t:
            age = time.time() - os.path.getmtime(TOKEN_FILE)
            if age > 82800:  # refresh if older than 23 hours
                refreshed = _refresh_oauth_token()
                if refreshed:
                    return refreshed
            return t
    return _c("LINEAR_API_KEY")

def _gql(query, variables=None):
    token = _get_token()
    if not token: raise RuntimeError("no linear token")
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    def _do(t):
        req = urllib.request.Request(
            "https://api.linear.app/graphql", data=payload,
            headers={"Authorization": f"Bearer {t}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    try:
        return _do(token)
    except urllib.error.HTTPError as e:
        if e.code == 401:
            refreshed = _refresh_oauth_token()
            if refreshed:
                return _do(refreshed)
        raise

def send_thought(sid, body, ephemeral=False):
    _send_activity(sid, {"type": "thought", "body": body}, ephemeral)

def send_response(sid, body):
    _send_activity(sid, {"type": "response", "body": body})

def send_error(sid, body):
    _send_activity(sid, {"type": "error", "body": body})

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

# ── conversation history ─────────────────────────────────────────────────────

def fetch_history(session_id):
    """rebuild conversation from agent activities for multi-turn context."""
    q = """query($id: String!) {
        agentSession(id: $id) {
            activities { edges { node {
                content {
                    ... on AgentActivityThoughtContent { __typename body }
                    ... on AgentActivityResponseContent { __typename body }
                    ... on AgentActivityPromptContent { __typename body }
                    ... on AgentActivityErrorContent { __typename body }
                }
            }}}
        }
    }"""
    try:
        r = _gql(q, {"id": session_id})
        edges = r.get("data", {}).get("agentSession", {}).get("activities", {}).get("edges", [])
        parts = []
        for e in edges:
            c = (e.get("node") or {}).get("content") or {}
            typename = c.get("__typename", "")
            body = c.get("body", "")
            if not body: continue
            if "Prompt" in typename:
                parts.append(f"[user]: {body}")
            elif "Response" in typename:
                parts.append(f"[assistant]: {body}")
        return "\n\n".join(parts)
    except Exception as e:
        print(f"[history-err] {e}", flush=True)
        return ""

# ── mention flow: kiro-cli in tmux ──────────────────────────────────────────

ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[\d*;?\d*m')

def handle_mention(session_id, prompt_context, user_message=None, is_followup=False):
    """run kiro-cli in tmux linear session, poll for output, post to linear."""
    # send thought SYNCHRONOUSLY before thread — must hit linear within 10s
    send_thought(session_id, "thinking...")

    def _run():
        try:
            os.makedirs(MENTION_DIR, exist_ok=True)
            sid = session_id[:8]
            prompt_file = f"{MENTION_DIR}/{sid}.prompt"
            output_file = f"{MENTION_DIR}/{sid}.output"
            done_file = f"{MENTION_DIR}/{sid}.done"

            for f in (output_file, done_file):
                if os.path.exists(f): os.remove(f)

            # build prompt
            if is_followup:
                history = fetch_history(session_id)
                prompt = ""
                if history:
                    prompt += f"<conversation_history>\n{history}\n</conversation_history>\n\n"
                prompt += f"[user]: {user_message}"
            else:
                prompt = prompt_context

            with open(prompt_file, "w") as f:
                f.write(prompt)

            # check tmux session
            check = subprocess.run([TMUX, "has-session", "-t", TMUX_MENTION], capture_output=True)
            if check.returncode != 0:
                send_error(session_id, f"tmux session '{TMUX_MENTION}' not found")
                return

            _running[session_id] = {"output": output_file, "done": done_file}

            cmd = (
                f"cat {prompt_file} | {KIRO_CLI} chat --no-interactive --trust-all-tools "
                f"--agent orchestrator 2>&1 | tee {output_file}; "
                f"echo $? > {done_file}"
            )
            subprocess.run([TMUX, "send-keys", "-t", TMUX_MENTION, cmd, "Enter"], capture_output=True)
            print(f"[mention] sent kiro-cli to tmux:{TMUX_MENTION} for {sid}", flush=True)

            # poll for completion (max 10 min)
            # send periodic thoughts every ~30s to keep linear session alive (30-min window)
            deadline = time.time() + 600
            last_thought = time.time()
            prev_size = 0
            while time.time() < deadline:
                if os.path.exists(done_file):
                    break
                # keep-alive: send thought every 30s so linear doesn't show stale
                if time.time() - last_thought >= 30:
                    cur_size = os.path.getsize(output_file) if os.path.exists(output_file) else 0
                    if cur_size > prev_size:
                        send_thought(session_id, f"working... ({cur_size} bytes of output so far)")
                        prev_size = cur_size
                    else:
                        send_thought(session_id, "still working...")
                    last_thought = time.time()
                time.sleep(5)
            else:
                _running.pop(session_id, None)
                send_error(session_id, "timed out after 10 minutes")
                return

            _running.pop(session_id, None)

            exit_code = open(done_file).read().strip() if os.path.exists(done_file) else "?"
            raw = open(output_file).read() if os.path.exists(output_file) else ""
            output = ANSI_RE.sub('', raw).strip()

            print(f"[kiro] exit={exit_code} output={len(output)} chars", flush=True)

            if output:
                print(f"[kiro] posting {len(output)} chars to linear", flush=True)
                send_response(session_id, output)
            else:
                send_error(session_id, f"kiro returned empty (exit={exit_code})")

        except Exception as e:
            _running.pop(session_id, None)
            print(f"[mention-err] {e}", flush=True)
            send_error(session_id, f"failed: {e}")

    threading.Thread(target=_run, daemon=True).start()

def handle_assign_direct(identifier):
    """run run-tasks.sh for a single issue in tmux dev — no agent session needed."""
    def _run():
        try:
            check = subprocess.run([TMUX, "has-session", "-t", TMUX_SESSION], capture_output=True)
            if check.returncode != 0:
                print(f"[assign-direct] tmux session '{TMUX_SESSION}' not found", flush=True)
                return
            cmd = f"bash {SCRIPT_DIR}/run-tasks.sh --linear --issue {identifier}"
            subprocess.run([TMUX, "send-keys", "-t", TMUX_SESSION, cmd, "Enter"], capture_output=True)
            print(f"[assign-direct] sent to tmux:{TMUX_SESSION}: {cmd}", flush=True)
        except Exception as e:
            print(f"[assign-direct-err] {e}", flush=True)
    threading.Thread(target=_run, daemon=True).start()

# ── assign flow: run-tasks.sh in tmux ────────────────────────────────────────

def handle_assign(session_id, issue):
    """send run-tasks.sh to tmux dev session, monitor completion."""
    identifier = issue.get("identifier", "UNKNOWN")

    def _run():
        try:
            # check tmux session exists
            check = subprocess.run(
                [TMUX, "has-session", "-t", TMUX_SESSION],
                capture_output=True,
            )
            if check.returncode != 0:
                send_error(session_id, f"tmux session '{TMUX_SESSION}' not found. start it first.")
                return

            send_thought(session_id, f"starting run-tasks.sh for {identifier} in tmux:{TMUX_SESSION}")

            # create a marker file to detect completion
            marker = f"/tmp/agent-task-{session_id[:8]}.done"
            cmd = (
                f"bash {SCRIPT_DIR}/run-tasks.sh --linear --issue {identifier}; "
                f"echo $? > {marker}"
            )

            subprocess.run(
                [TMUX, "send-keys", "-t", TMUX_SESSION, cmd, "Enter"],
                capture_output=True,
            )

            # poll for completion (check every 30s, max 2 hours)
            for _ in range(240):
                time.sleep(30)
                if os.path.exists(marker):
                    with open(marker) as f:
                        exit_code = f.read().strip()
                    os.remove(marker)
                    if exit_code == "0":
                        send_response(session_id, f"✅ run-tasks.sh completed for {identifier}")
                    else:
                        send_error(session_id, f"run-tasks.sh exited with code {exit_code} for {identifier}")
                    return

            send_error(session_id, f"run-tasks.sh timed out after 2 hours for {identifier}")

        except Exception as e:
            print(f"[assign-err] {e}", flush=True)
            send_error(session_id, f"failed to start: {e}")

    threading.Thread(target=_run, daemon=True).start()

# ── stop handling ────────────────────────────────────────────────────────────

def handle_stop(session_id):
    info = _running.pop(session_id, None)
    if info:
        print(f"[stop] sending C-c to tmux:{TMUX_MENTION} for {session_id[:8]}", flush=True)
        subprocess.run([TMUX, "send-keys", "-t", TMUX_MENTION, "C-c", ""], capture_output=True)
        # write done file so poll loop exits
        done = info.get("done")
        if done:
            with open(done, "w") as f: f.write("130")
    send_response(session_id, "stopped.")

# ── signature verification ───────────────────────────────────────────────────

def verify_sig(body, sig):
    if not WEBHOOK_SECRET: return True
    expected = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)

def verify_github_sig(body, sig):
    if not GITHUB_WEBHOOK_SECRET: return True
    if not sig or not sig.startswith("sha256="): return False
    expected = "sha256=" + hmac.new(GITHUB_WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)

# ── github PR review → linear triage ────────────────────────────────────────

def _gh_api(path):
    """call github REST API via gh cli."""
    r = subprocess.run(
        ["gh", "api", path, "--paginate"],
        capture_output=True, text=True, cwd=REPO_DIR,
    )
    return json.loads(r.stdout) if r.returncode == 0 else []

def _linear_api(query, variables=None):
    """call linear graphql API."""
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(
        "https://api.linear.app/graphql", data=payload,
        headers={"Authorization": LINEAR_API_KEY, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"[linear] API error {e.code}: {body[:200]}", flush=True)
        return {"errors": [{"message": f"HTTP {e.code}"}]}
    except Exception as e:
        print(f"[linear] API exception: {e}", flush=True)
        return {"errors": [{"message": str(e)}]}

def handle_pr_review(pr_number, repo_full, bot_login):
    """fetch all reviews + comments from a bot on a PR, create/update a linear issue."""
    key = (pr_number, bot_login)
    if key in _pending_reviews:
        print(f"[github] debounce — already waiting for {REVIEW_BOTS[bot_login]} on PR #{pr_number}", flush=True)
        return
    _pending_reviews[key] = time.time()

    def _run():
        # wait 5 min for bot to finish all review passes
        bot_name = REVIEW_BOTS[bot_login]
        print(f"[github] waiting 5m for {bot_name} to finish PR #{pr_number}...", flush=True)
        time.sleep(300)

        # poll up to 10 min total — check if new reviews appeared in last 2 min
        start = _pending_reviews[key]
        while time.time() - start < 600:
            reviews = _gh_api(f"repos/{repo_full}/pulls/{pr_number}/reviews")
            bot_reviews = [r for r in reviews if r.get("user", {}).get("login") == bot_login]
            if not bot_reviews:
                break
            latest = max(r.get("submitted_at", "") for r in bot_reviews)
            # if latest review is older than 2 min, bot is done
            if latest:
                from datetime import datetime, timezone
                latest_dt = datetime.fromisoformat(latest.replace("Z", "+00:00"))
                age = (datetime.now(timezone.utc) - latest_dt).total_seconds()
                if age > 120:
                    break
            print(f"[github] {bot_name} still active on PR #{pr_number}, waiting 60s...", flush=True)
            time.sleep(60)

        try:
            _collect_and_create(pr_number, repo_full, bot_login)
        finally:
            _pending_reviews.pop(key, None)

    threading.Thread(target=_run, daemon=True).start()

def _collect_and_create(pr_number, repo_full, bot_login):
    """collect all bot findings and create/update linear issue."""
    bot_name = REVIEW_BOTS[bot_login]
    print(f"[github] collecting {bot_name} findings on PR #{pr_number}", flush=True)

    reviews = _gh_api(f"repos/{repo_full}/pulls/{pr_number}/reviews")
    comments = _gh_api(f"repos/{repo_full}/pulls/{pr_number}/comments")
    pr_comments = _gh_api(f"repos/{repo_full}/issues/{pr_number}/comments")

    bot_reviews = [r for r in reviews if r.get("user", {}).get("login") == bot_login]
    bot_inline = [c for c in comments if c.get("user", {}).get("login") == bot_login]
    bot_pr = [c for c in pr_comments if c.get("user", {}).get("login") == bot_login]

    if not bot_reviews and not bot_inline and not bot_pr:
        print(f"[github] no {bot_name} content found on PR #{pr_number}", flush=True)
        return

    desc = f"## {bot_name} Review — PR #{pr_number}\n\n"
    desc += f"**Source:** [{repo_full}#{pr_number}](https://github.com/{repo_full}/pull/{pr_number})\n\n"

    if bot_inline:
        desc += f"### Inline Comments ({len(bot_inline)})\n\n"
        for c in bot_inline:
            desc += f"**`{c.get('path', '?')}`** line {c.get('line') or c.get('original_line', '?')}\n\n"
            desc += f"{c.get('body', '')}\n\n---\n\n"

    if bot_reviews:
        bodies = [r["body"] for r in bot_reviews if r.get("body", "").strip()]
        if bodies:
            desc += f"### Review Summaries ({len(bodies)})\n\n"
            for body in bodies:
                desc += f"{body}\n\n---\n\n"

    if bot_pr:
        bodies = [c["body"] for c in bot_pr if c.get("body", "").strip()]
        if bodies:
            desc += f"### PR Comments ({len(bodies)})\n\n"
            for body in bodies:
                if len(body) > 4000:
                    body = body[:4000] + "\n\n_(truncated — see PR for full content)_"
                desc += f"{body}\n\n---\n\n"

    title = f"[review] {bot_name}: PR #{pr_number}"
    finding_count = len(bot_inline) + len([r for r in bot_reviews if r.get("body", "").strip()])

    search_result = _linear_api(
        '{ searchIssues(term: "' + title.replace('"', '\\"') + '", first: 1) { nodes { id identifier } } }'
    )
    existing = (search_result.get("data", {}).get("searchIssues", {}).get("nodes") or [None])[0]

    if existing:
        _linear_api(
            'mutation($id: String!, $desc: String!) { issueUpdate(id: $id, input: { description: $desc }) { success } }',
            {"id": existing["id"], "desc": desc},
        )
        print(f"[github] updated {existing['identifier']}: {title} ({finding_count} findings)", flush=True)
    else:
        result = _linear_api(
            'mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier } } }',
            {"input": {
                "title": title, "description": desc, "teamId": TEAM_ID,
                "stateId": TRIAGE_STATE, "labelIds": [REVIEW_LABEL, OPENSAAS_LABEL],
            }},
        )
        ident = result.get("data", {}).get("issueCreate", {}).get("issue", {}).get("identifier", "?")
        print(f"[github] created {ident}: {title} ({finding_count} findings)", flush=True)

# ── HTTP handler ─────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._json(200, {
                "status": "ok",
                "running_kiro": len(_running),
            })
        elif self.path.startswith("/oauth/callback"):
            qs = urllib.parse.urlparse(self.path).query
            code = urllib.parse.parse_qs(qs).get("code", [None])[0]
            if not code:
                self._json(400, {"error": "no code"})
                return
            try:
                token_data = self._exchange_code(code)
                with open(TOKEN_FILE, "w") as f:
                    json.dump(token_data, f, indent=2)
                print(f"[oauth] token saved to {TOKEN_FILE}", flush=True)
                self._json(200, {"status": "ok", "message": "token saved"})
            except Exception as e:
                self._json(500, {"error": str(e)})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        if self.path == "/webhook/github":
            sig = self.headers.get("X-Hub-Signature-256", "")
            if not verify_github_sig(body, sig):
                print(f"[github] ✗ bad signature (sig={sig[:20]}...)", flush=True)
                self._json(401, {"error": "bad signature"})
                return
            try:
                payload = json.loads(body)
            except json.JSONDecodeError:
                self._json(400, {"error": "bad json"})
                return
            event = self.headers.get("X-GitHub-Event", "")
            action = payload.get("action", "")
            print(f"[github] event={event} action={action}", flush=True)
            self._json(200, {"status": "accepted"})
            if event == "pull_request_review":
                reviewer = payload.get("review", {}).get("user", {}).get("login", "")
                pr_number = payload.get("pull_request", {}).get("number")
                repo_full = payload.get("repository", {}).get("full_name", "")
                print(f"[github] reviewer={reviewer} pr=#{pr_number} repo={repo_full}", flush=True)
                if action == "submitted" and reviewer in REVIEW_BOTS and pr_number:
                    handle_pr_review(pr_number, repo_full, reviewer)
                else:
                    print(f"[github] skipped — action={action} reviewer_known={reviewer in REVIEW_BOTS}", flush=True)
            return

        if self.path != "/webhook/linear":
            self._json(404, {"error": "not found"})
            return

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

        # respond fast — linear requires <5s
        self._json(200, {"status": "accepted"})

        if ptype == "AppUserNotification" and action == "issueAssignedToYou":
            issue = payload.get("issue") or payload.get("data", {}).get("issue") or {}
            identifier = issue.get("identifier", "")
            if not identifier:
                # try to extract from notification
                print(f"[assign-notify] payload keys: {list(payload.keys())}", flush=True)
                print(f"[assign-notify] full payload: {json.dumps(payload)[:500]}", flush=True)
            else:
                print(f"[assign-notify] {identifier} assigned to kiro", flush=True)
                handle_assign_direct(identifier)
            return

        if ptype == "AgentSessionEvent":
            session = payload.get("agentSession") or {}
            sid = session.get("id")
            issue = session.get("issue") or {}
            comment = session.get("comment")
            prompt_context = payload.get("promptContext", "")

            if not sid:
                print("[webhook] no session id", flush=True)
                return

            if action == "created":
                if comment:
                    # @mention in a comment → chat mode
                    print(f"[webhook] mention on {issue.get('identifier', '?')}", flush=True)
                    handle_mention(sid, prompt_context)
                else:
                    # delegation/assignment → task mode
                    print(f"[webhook] assign {issue.get('identifier', '?')}", flush=True)
                    handle_assign(sid, issue)

            elif action == "prompted":
                # check for stop signal first
                activity = payload.get("agentActivity") or {}
                signal = payload.get("signal") or activity.get("signal") or ""
                if signal == "stop":
                    print(f"[webhook] stop signal for {sid[:8]}", flush=True)
                    handle_stop(sid)
                    return

                # follow-up message in existing session
                msg = activity.get("body", "")
                if not msg:
                    msg = prompt_context
                print(f"[webhook] follow-up on {issue.get('identifier', '?')}", flush=True)
                handle_mention(sid, prompt_context, user_message=msg, is_followup=True)

            elif action == "stopped":
                handle_stop(sid)

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
    print(f"  POST /webhook/linear  — agent session events", flush=True)
    print(f"  POST /webhook/github  — PR review → linear triage", flush=True)
    print(f"  GET  /oauth/callback  — oauth code exchange", flush=True)
    print(f"  GET  /health          — health check", flush=True)
    print(f"", flush=True)
    print(f"  mention → kiro-cli chat (non-interactive, per turn)", flush=True)
    print(f"  assign  → run-tasks.sh in tmux:{TMUX_SESSION}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    main()
