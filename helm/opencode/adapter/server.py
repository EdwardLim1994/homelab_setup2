#!/usr/bin/env python3
"""
opencode-adapter — a tiny OpenAI-compatible shim in front of `opencode serve`.

opencode's server API is not OpenAI-shaped (POST /session, POST /session/:id/
message). This translates POST /v1/chat/completions into that two-step call so
LiteLLM (and anything else) can treat an opencode pod as a normal model.

Model name -> target pod:
  "opencode"          -> http://opencode.<ns>.svc:4096          (always-on)
  "opencode-<role>"   -> http://opencode-<role>.<ns>.svc:4096   (scale-to-zero)

Scale-to-zero role pods are scaled to 1 on first request (SCALE_UP=1) using the
mounted ServiceAccount token; needs a Role granting deployments/scale patch.

ponytail: stdlib only — no framework, no image build. Mounted from a ConfigMap
into a python:3-slim pod. opencode itself is non-streaming, so on stream=true
we still wait for the full reply then emit it as a single SSE chunk (enough for
OpenWebUI, which refuses to render a non-streamed response).
"""
import json
import os
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NS = os.environ.get("OPENCODE_NAMESPACE", "opencode")
PORT = int(os.environ.get("PORT", "8000"))
OPENCODE_PORT = os.environ.get("OPENCODE_PORT", "4096")
SCALE_UP = os.environ.get("SCALE_UP", "1") == "1"
SCALE_TIMEOUT = int(os.environ.get("SCALE_TIMEOUT", "150"))
MODELS = [m.strip() for m in os.environ.get(
    "OPENCODE_MODELS",
    "opencode,opencode-backend-developer,opencode-data-engineer,"
    "opencode-devops-engineer,opencode-frontend-developer,opencode-product-owner,"
    "opencode-project-manager,opencode-qa-engineer,opencode-release-manager,"
    "opencode-security-engineer,opencode-solution-architect,opencode-tech-lead,"
    "opencode-uiux-designer",
).split(",") if m.strip()]

K8S = "https://kubernetes.default.svc"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def _sa_token():
    with open(f"{SA_DIR}/token") as f:
        return f.read().strip()


def _http(method, url, body=None, headers=None, timeout=600, cafile=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    ctx = None
    if url.startswith("https") and cafile:
        import ssl
        ctx = ssl.create_default_context(cafile=cafile)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw else {})


def _deployment_for(model):
    if model in ("opencode", ""):
        return "opencode"
    if model.startswith("opencode-"):
        return model
    # allow bare role names too
    return f"opencode-{model}"


def _ensure_up(deploy):
    if not SCALE_UP or deploy == "opencode":
        return
    tok = _sa_token()
    ca = f"{SA_DIR}/ca.crt"
    h = {"Authorization": f"Bearer {tok}"}
    base = f"{K8S}/apis/apps/v1/namespaces/{NS}/deployments/{deploy}"
    _http("PATCH", f"{base}/scale", {"spec": {"replicas": 1}},
          {**h, "Content-Type": "application/merge-patch+json"}, timeout=15, cafile=ca)
    deadline = time.time() + SCALE_TIMEOUT
    while time.time() < deadline:
        _, d = _http("GET", base, None, h, timeout=15, cafile=ca)
        if (d.get("status") or {}).get("readyReplicas", 0) >= 1:
            return
        time.sleep(3)
    raise RuntimeError(f"{deploy} not ready after {SCALE_TIMEOUT}s")


def _prompt_from(messages):
    # last user turn; fall back to whole transcript
    for m in reversed(messages or []):
        if m.get("role") == "user":
            c = m.get("content")
            return c if isinstance(c, str) else json.dumps(c)
    return "\n".join(m.get("content", "") for m in (messages or []) if isinstance(m.get("content"), str))


def _extract_text(obj):
    out = []

    def walk(x):
        if isinstance(x, dict):
            if x.get("type") == "text" and isinstance(x.get("text"), str):
                out.append(x["text"])
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(obj)
    return "\n".join(t for t in out if t).strip()


def _run(model, messages):
    deploy = _deployment_for(model)
    _ensure_up(deploy)
    base = f"http://{deploy}.{NS}.svc:{OPENCODE_PORT}"
    _, sess = _http("POST", f"{base}/session", {}, timeout=30)
    sid = sess.get("id") or (sess.get("info") or {}).get("id")
    if not sid:
        raise RuntimeError(f"no session id in {sess!r}")
    _, msg = _http(
        "POST", f"{base}/session/{sid}/message",
        {"parts": [{"type": "text", "text": _prompt_from(messages)}]},
    )
    text = _extract_text(msg) or "(no text in opencode response)"
    return text


class H(BaseHTTPRequestHandler):
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

    def log_message(self, *a):  # quieter
        pass

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/healthz"):
            return self._send(200, {"status": "ok"})
        if self.path.rstrip("/") == "/v1/models":
            now = int(time.time())
            return self._send(200, {"object": "list", "data": [
                {"id": m, "object": "model", "created": now, "owned_by": "opencode"}
                for m in MODELS
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
        model = body.get("model", "opencode")
        try:
            text = _run(model, body.get("messages"))
        except (urllib.error.URLError, RuntimeError, TimeoutError) as e:
            return self._send(502, {"error": {"message": f"opencode adapter: {e}", "type": "upstream_error"}})
        now = int(time.time())
        if body.get("stream"):
            # OpenWebUI always streams; emit the whole reply as one SSE chunk.
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
    import io
    buf = io.BytesIO()
    h = H.__new__(H)
    h.wfile = buf
    h.send_response = lambda *a: None
    h.send_header = lambda *a: None
    h.end_headers = lambda: None
    h._send_stream("m", 1, "hi there")
    s = buf.getvalue().decode()
    assert s.count("data: ") == 3 and s.endswith("[DONE]\n\n"), s
    assert '"content": "hi there"' in s and '"finish_reason": "stop"' in s, s
    print("selftest ok")


if __name__ == "__main__":
    if os.environ.get("SELFTEST"):
        _selftest()
        raise SystemExit(0)
    print(f"opencode-adapter on :{PORT} ns={NS} models={len(MODELS)} scale_up={SCALE_UP}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
