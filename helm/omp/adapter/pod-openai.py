#!/usr/bin/env python3
"""
pod-openai — OpenAI-compatible shim that runs INSIDE each omp pod on :4096.

Backs onto one of two agent CLIs, picked by BACKEND env (default "omp"):

- omp: has no HTTP server, speaks newline-delimited JSON-RPC over stdio
  (`omp --mode rpc`, see oh-my-pi docs/rpc.md). One long-running rpc child,
  turns `POST /v1/chat/completions` into a `prompt` command on that
  persistent session, accumulating the assistant text_delta stream back
  into one reply.
- claude: BACKEND=claude runs `claude -p` (Claude Code's headless print
  mode) per turn instead, using `--continue` to keep the conversation going
  in /workspace when the turn isn't a fresh session. Needs CLAUDE_CODE_OAUTH_TOKEN
  (values.yaml's claudeAuth secret) in the pod env.

ponytail: ONE session per pod, requests serialized by a lock. That is the
"long-running session" model — turns on a pod accrete context. A short chat
history (<=RESET_AT messages) is treated as a fresh conversation (omp:
`new_session`, claude: drop `--continue`).

ponytail: stdlib only. Mounted/baked as a plain script, run as the pod's PID 1.
The LiteLLM adapter (helm/omp/adapter/server.py) proxies to this and handles
scale-to-zero wake-up.
"""
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "4096"))
BACKEND = os.environ.get("BACKEND", "omp")
MODEL_NAME = os.environ.get("OMP_MODEL_NAME", "omp")
# ponytail: rpc mode does NOT honour config.yml's `model:` — it picks a default
# off the catalog (often the wrong one). Pin it explicitly. OMP_MODEL overrides.
OMP_MODEL = os.environ.get("OMP_MODEL", "ollama/qwen3.8:27b")
OMP_CMD = os.environ.get(
    "OMP_CMD", f"omp --mode rpc --model {OMP_MODEL}"
).split()
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL", "sonnet")
TURN_TIMEOUT = int(os.environ.get("OMP_TURN_TIMEOUT", "900"))
RESET_AT = int(os.environ.get("OMP_RESET_AT", "2"))


class ClaudeBackend:
    """BACKEND=claude: no persistent child, one `claude -p` per turn."""

    def __init__(self, model):
        self.model = model
        self.lock = threading.Lock()
        self.started = False

    def alive(self):
        return True  # stateless per-turn — nothing to keep alive between calls

    def prompt(self, message, fresh):
        with self.lock:
            cmd = ["claude", "-p", message, "--output-format", "text"]
            if self.model:
                cmd += ["--model", self.model]
            if not fresh and self.started:
                cmd.append("--continue")
            self.started = True
            try:
                r = subprocess.run(
                    cmd, cwd="/workspace", capture_output=True, text=True,
                    timeout=TURN_TIMEOUT,
                )
            except subprocess.TimeoutExpired:
                raise TimeoutError(f"claude turn exceeded {TURN_TIMEOUT}s")
            if r.returncode != 0:
                raise RuntimeError(
                    f"claude exited {r.returncode}: {r.stderr.strip()[:500]}"
                )
            return r.stdout.strip() or "(no assistant text)"


class Rpc:
    def __init__(self, cmd):
        self.lock = threading.Lock()
        self.n = 0
        self.p = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self._wait_for({"ready"})

    def alive(self):
        return self.p.poll() is None

    def _send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def _lines(self):
        for line in self.p.stdout:
            line = line.strip()
            if line:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue

    def _wait_for(self, types, deadline=None):
        for obj in self._lines():
            if obj.get("type") in types:
                return obj
            if deadline and time.time() > deadline:
                raise TimeoutError("rpc: no matching frame")
        raise RuntimeError("rpc: stream closed")

    def prompt(self, message, fresh):
        with self.lock:
            if self.p.poll() is not None:
                raise RuntimeError(f"omp rpc child exited ({self.p.returncode})")
            if fresh:
                self._send({"type": "new_session"})
                self._wait_for({"response"})
            self.n += 1
            rid = f"p{self.n}"
            self._send({"id": rid, "type": "prompt", "message": message})
            deadline = time.time() + TURN_TIMEOUT
            text = []
            for obj in self._lines():
                t = obj.get("type")
                if t == "response" and obj.get("command") == "prompt" and not obj.get("success", True):
                    raise RuntimeError(f"omp prompt rejected: {obj.get('error')}")
                if t == "message_update":
                    ev = obj.get("assistantMessageEvent") or {}
                    if ev.get("type") == "text_delta" and isinstance(ev.get("delta"), str):
                        text.append(ev["delta"])
                if t == "agent_end" and obj.get("isTerminal") is not False:
                    break
                if time.time() > deadline:
                    raise TimeoutError(f"omp turn exceeded {TURN_TIMEOUT}s")
            return "".join(text).strip() or "(no assistant text)"


RPC = None


def _prompt_from(messages):
    for m in reversed(messages or []):
        if m.get("role") == "user":
            c = m.get("content")
            return c if isinstance(c, str) else json.dumps(c)
    return "\n".join(
        m.get("content", "") for m in (messages or [])
        if isinstance(m.get("content"), str)
    )


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _send_stream(self, model, now, text):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        base = {"id": f"chatcmpl-{now}", "object": "chat.completion.chunk",
                "created": now, "model": model}

        def chunk(delta, finish=None):
            d = {**base, "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            self.wfile.write(f"data: {json.dumps(d)}\n\n".encode())
            self.wfile.flush()

        chunk({"role": "assistant", "content": text})
        chunk({}, "stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def do_GET(self):
        p = self.path.rstrip("/")
        if p in ("/health", "/healthz"):
            alive = RPC is not None and RPC.alive()
            return self._send(200 if alive else 503, {"status": "ok" if alive else "down"})
        if p == "/v1/models":
            now = int(time.time())
            return self._send(200, {"object": "list", "data": [
                {"id": MODEL_NAME, "object": "model", "created": now, "owned_by": "omp"}
            ]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            return self._send(404, {"error": "not found"})
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})
        messages = body.get("messages") or []
        fresh = len([m for m in messages if m.get("role") != "system"]) <= RESET_AT
        try:
            text = RPC.prompt(_prompt_from(messages), fresh)
        except (RuntimeError, TimeoutError) as e:
            return self._send(502, {"error": {"message": f"omp pod: {e}", "type": "upstream_error"}})
        now = int(time.time())
        model = body.get("model") or MODEL_NAME
        if body.get("stream"):
            return self._send_stream(model, now, text)
        self._send(200, {
            "id": f"chatcmpl-{now}",
            "object": "chat.completion",
            "created": now,
            "model": model,
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        })


def _selftest():
    # ponytail: no omp in the test env — exercise the pure helpers only.
    assert _prompt_from([{"role": "user", "content": "hi"}]) == "hi"
    assert _prompt_from([{"role": "system", "content": "s"},
                         {"role": "user", "content": "a"},
                         {"role": "assistant", "content": "b"},
                         {"role": "user", "content": "c"}]) == "c"
    print("selftest ok")


if __name__ == "__main__":
    if os.environ.get("SELFTEST"):
        _selftest()
        raise SystemExit(0)
    if BACKEND == "claude":
        RPC = ClaudeBackend(CLAUDE_MODEL)
        print(f"pod-openai on :{PORT} backend=claude model={CLAUDE_MODEL}", flush=True)
    else:
        # ponytail: the baked models.db has no entries (the image builds with no
        # Ollama reachable). omp resolves the config.yml model off this catalog, so
        # without a refresh the first rpc turn picks no model and returns empty.
        # One blocking refresh at boot; non-fatal if it can't reach the backend.
        try:
            subprocess.run(["omp", "models", "refresh"], timeout=120,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except Exception:
            pass
        RPC = Rpc(OMP_CMD)
        print(f"pod-openai on :{PORT} backend=omp cmd={' '.join(OMP_CMD)}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
