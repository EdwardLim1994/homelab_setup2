#!/usr/bin/env python3
"""
omp-adapter — scale-to-zero waker + transparent proxy in front of the omp pods.

Each omp pod runs pod-openai.py, so it already serves an OpenAI-compatible API
on :4096. This adapter only adds what a pod can't do for itself:

  1. scale a scale-to-zero role pod to 1 on first request (SCALE_UP=1), and
  2. present one flat /v1 surface + /v1/models list for LiteLLM.

Model name -> target pod:
  "omp"          -> http://omp.<ns>.svc:4096          (always-on)
  "omp-<role>"   -> http://omp-<role>.<ns>.svc:4096   (scale-to-zero)

Scaling needs a Role granting deployments/scale patch (see templates/adapter.yaml).

ponytail: stdlib only, ConfigMap-mounted into a python:3-slim pod, no image
build. Streaming passes straight through from the pod.
"""
import json
import os
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NS = os.environ.get("OMP_NAMESPACE", "omp")
PORT = int(os.environ.get("PORT", "8000"))
OMP_PORT = os.environ.get("OMP_PORT", "4096")
SCALE_UP = os.environ.get("SCALE_UP", "1") == "1"
SCALE_TIMEOUT = int(os.environ.get("SCALE_TIMEOUT", "150"))
MODELS = [m.strip() for m in os.environ.get(
    "OMP_MODELS",
    "omp,omp-backend-developer,omp-data-engineer,omp-devops-engineer,"
    "omp-frontend-developer,omp-product-owner,omp-project-manager,"
    "omp-qa-engineer,omp-release-manager,omp-security-engineer,"
    "omp-solution-architect,omp-tech-lead,omp-uiux-designer",
).split(",") if m.strip()]

K8S = "https://kubernetes.default.svc"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def _sa_token():
    with open(f"{SA_DIR}/token") as f:
        return f.read().strip()


def _http(method, url, body=None, headers=None, timeout=600, cafile=None, raw=False):
    data = body if raw else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    ctx = None
    if url.startswith("https") and cafile:
        import ssl
        ctx = ssl.create_default_context(cafile=cafile)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        payload = r.read()
        return r.status, payload


def _deployment_for(model):
    if model in ("omp", ""):
        return "omp"
    if model.startswith("omp-"):
        return model
    return f"omp-{model}"


def _ensure_up(deploy):
    if not SCALE_UP or deploy == "omp":
        return
    tok = _sa_token()
    ca = f"{SA_DIR}/ca.crt"
    h = {"Authorization": f"Bearer {tok}"}
    base = f"{K8S}/apis/apps/v1/namespaces/{NS}/deployments/{deploy}"
    _http("PATCH", f"{base}/scale", {"spec": {"replicas": 1}},
          {**h, "Content-Type": "application/merge-patch+json"}, timeout=15, cafile=ca)
    deadline = time.time() + SCALE_TIMEOUT
    while time.time() < deadline:
        _, raw = _http("GET", base, None, h, timeout=15, cafile=ca)
        d = json.loads(raw)
        if (d.get("status") or {}).get("readyReplicas", 0) >= 1:
            return
        time.sleep(3)
    raise RuntimeError(f"{deploy} not ready after {SCALE_TIMEOUT}s")


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

    def do_GET(self):
        p = self.path.rstrip("/")
        if p in ("/health", "/healthz"):
            return self._send(200, {"status": "ok"})
        if p == "/v1/models":
            now = int(time.time())
            return self._send(200, {"object": "list", "data": [
                {"id": m, "object": "model", "created": now, "owned_by": "omp"}
                for m in MODELS
            ]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            return self._send(404, {"error": "not found"})
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n) or b"{}"
        try:
            body = json.loads(raw)
        except ValueError:
            return self._send(400, {"error": "bad json"})
        deploy = _deployment_for(body.get("model", "omp"))
        try:
            _ensure_up(deploy)
            url = f"http://{deploy}.{NS}.svc:{OMP_PORT}/v1/chat/completions"
            code, payload = _http("POST", url, raw,
                                  {"Content-Type": "application/json"}, raw=True)
        except (urllib.error.URLError, RuntimeError, TimeoutError) as e:
            return self._send(502, {"error": {"message": f"omp adapter: {e}", "type": "upstream_error"}})
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def _selftest():
    assert _deployment_for("omp") == "omp"
    assert _deployment_for("omp-tech-lead") == "omp-tech-lead"
    assert _deployment_for("tech-lead") == "omp-tech-lead"
    print("selftest ok")


if __name__ == "__main__":
    if os.environ.get("SELFTEST"):
        _selftest()
        raise SystemExit(0)
    print(f"omp-adapter on :{PORT} ns={NS} models={len(MODELS)} scale_up={SCALE_UP}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
