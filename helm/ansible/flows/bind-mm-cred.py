#!/usr/bin/env python3
"""Point every seeded workflow's `mattermostApi` node at a real credential.

The flow JSON files carry a placeholder credential ref (`id: mm-creds`). n8n's
public API can't create a credential with a chosen id and can't list existing
ones, so playbooks/mattermost.yml creates the credential fresh, then runs this
to rebind the seeded workflows to whatever id it got.

Env:
  N8N_URL        base url (e.g. http://n8n.n8n.svc.cluster.local:5678)
  N8N_API_KEY    public API key
  MM_CRED_ID     credential id to bind
  MM_CRED_NAME   credential name (default "Mattermost SDLC Bot")

ponytail: stdlib only, runs in the alpine ansible runner. Idempotent — a
re-run just re-writes the same id.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ["N8N_URL"].rstrip("/")
KEY = os.environ["N8N_API_KEY"]
CRED_ID = os.environ["MM_CRED_ID"]
CRED_NAME = os.environ.get("MM_CRED_NAME", "Mattermost SDLC Bot")


def api(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        method=method,
        headers={"X-N8N-API-KEY": KEY, "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main():
    workflows = api("GET", "/api/v1/workflows?limit=250").get("data", [])
    bound = 0
    for wf in workflows:
        full = api("GET", f"/api/v1/workflows/{wf['id']}")
        touched = False
        for node in full.get("nodes", []):
            creds = node.get("credentials") or {}
            if "mattermostApi" in creds:
                creds["mattermostApi"] = {"id": CRED_ID, "name": CRED_NAME}
                node["credentials"] = creds
                touched = True
        if not touched:
            continue
        payload = {k: full[k] for k in ("name", "nodes", "connections", "settings") if k in full}
        api("PUT", f"/api/v1/workflows/{wf['id']}", payload)
        if full.get("active"):
            try:
                api("POST", f"/api/v1/workflows/{wf['id']}/activate")
            except urllib.error.HTTPError:
                pass
        bound += 1
        print(f"  bound: {full['name']}")
    print(f"{bound} workflow(s) bound to credential {CRED_ID} ({CRED_NAME})")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        sys.exit(f"n8n API {e.code}: {e.read().decode()[:300]}")
