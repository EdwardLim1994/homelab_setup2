"""
SDLC Pipe — OpenWebUI edition
Dispatches SDLC slash commands to n8n webhooks and streams progress back.

Install: OpenWebUI → Admin → Pipelines → Upload this file
Env vars to set in the pipe's Valve UI:
  N8N_BASE_URL        e.g. https://n8n.your-domain.com
  N8N_WEBHOOK_SECRET  shared secret for pipe→n8n auth (optional but recommended)
  CALLBACK_TOKEN      static token n8n uses when POSTing back to /pipe/callback

Flow:
  1. User types a slash command in chat  →  pipe parses it
  2. Pipe POSTs to n8n webhook with {body: {...}, flow_id: <uuid>}
  3. n8n runs asynchronously; each notify node POSTs back to /api/v1/pipe/callback
  4. Pipe streams those callback messages into the chat as they arrive (SSE)
"""

from __future__ import annotations

import asyncio
import json
import re
import uuid
from dataclasses import dataclass, field
from typing import AsyncGenerator, Optional

import aiohttp
from pydantic import BaseModel


# ── Valves (admin-configurable env vars) ─────────────────────────────────────

class Valves(BaseModel):
    N8N_BASE_URL: str = "http://n8n.n8n.svc.cluster.local:5678"
    N8N_WEBHOOK_SECRET: str = ""          # added as X-SDLC-Secret header on every call
    CALLBACK_TOKEN: str = ""              # n8n must include this when posting back
    CALLBACK_TIMEOUT_SECONDS: int = 300   # how long to wait for n8n to finish
    CALLBACK_POLL_INTERVAL: float = 1.0   # seconds between checking callback queue


# ── Command registry ──────────────────────────────────────────────────────────

@dataclass
class Command:
    name: str
    path: str
    method: str
    params: list[str]           # required body params extracted from user input
    optional: list[str]         # optional body params
    description: str
    example: str

COMMANDS: dict[str, Command] = {
    "/plan_release": Command(
        name="/plan_release",
        path="plan-release",
        method="POST",
        params=["version"],
        optional=[],
        description="Multi-agent release planning: Arch+DE → QA+Sec+UX → PM PRD",
        example="/plan_release v1.2.0",
    ),
    "/kickoff": Command(
        name="/kickoff",
        path="kickoff",
        method="POST",
        params=["version"],
        optional=[],
        description="Kickoff sprint: TL branches+pseudocode · PM GitLab artifacts · DevOps infra",
        example="/kickoff v1.2.0",
    ),
    "/develop": Command(
        name="/develop",
        path="develop",
        method="POST",
        params=["version"],
        optional=[],
        description="Gate A→B→C then fan out dev pods (backend, frontend, QA, security)",
        example="/develop v1.2.0",
    ),
    "/uat": Command(
        name="/uat",
        path="uat",
        method="POST",
        params=[],
        optional=[],
        description="UAT pipeline: safeguard → deploy → QA → Security → PO sign-off",
        example="/uat",
    ),
    "/release_staging": Command(
        name="/release_staging",
        path="release-staging",
        method="POST",
        params=[],
        optional=[],
        description="Stage release: UAT safeguard → release-plan ticket → promote/ branch → CI",
        example="/release_staging",
    ),
    "/release_production": Command(
        name="/release_production",
        path="release-production",
        method="POST",
        params=[],
        optional=[],
        description="Production release: rm:go safeguard → create promote→main MR for Edward",
        example="/release_production",
    ),
    "/rollback": Command(
        name="/rollback",
        path="rollback",
        method="POST",
        params=["version"],
        optional=[],
        description="ArgoCD rollback production + open incident ticket",
        example="/rollback v1.2.0",
    ),
    "/rollback_story": Command(
        name="/rollback_story",
        path="rollback-story",
        method="POST",
        params=["story_id"],
        optional=[],
        description="Dependency check → revert MR → TL review → Edward merges → re-UAT",
        example="/rollback_story GL-42",
    ),
    "/retro": Command(
        name="/retro",
        path="retro",
        method="POST",
        params=["version"],
        optional=[],
        description="4-pod parallel retro (TL+QA+Sec+RM) → PM 11-section report",
        example="/retro v1.2.0",
    ),
    "/escalate": Command(
        name="/escalate",
        path="escalate",
        method="POST",
        params=["reason"],
        optional=[],
        description="Pause DAG + open escalation ticket + immediate alert",
        example='/escalate "pipeline stuck at gate B for 2h"',
    ),
    "/projects": Command(
        name="/projects",
        path="projects",
        method="GET",
        params=[],
        optional=[],
        description="Instant DAG state query — stories/tasks open vs merged",
        example="/projects",
    ),
}

HELP_TEXT = """**SDLC Commands**

| Command | Params | Description |
|---|---|---|
| `/plan_release <version>` | version | Multi-agent release planning |
| `/kickoff <version>` | version | Sprint kickoff |
| `/develop <version>` | version | Dev gates + pod fan-out |
| `/uat` | — | UAT pipeline |
| `/release_staging` | — | Stage the release |
| `/release_production` | — | Create production MR |
| `/rollback <version>` | version | ArgoCD rollback |
| `/rollback_story <story_id>` | story_id | Revert a story |
| `/retro <version>` | version | Retrospective |
| `/escalate <reason>` | reason | Pause DAG + alert |
| `/projects` | — | DAG state snapshot |

**Examples**
```
/kickoff v1.2.0
/develop v1.2.0
/rollback_story GL-42
/escalate "staging deploy hung"
```
"""


# ── In-memory callback queue ──────────────────────────────────────────────────
# Maps flow_id → asyncio.Queue of progress message strings.
# The callback endpoint (registered separately) puts messages here.
_callback_queues: dict[str, asyncio.Queue] = {}


def _get_or_create_queue(flow_id: str) -> asyncio.Queue:
    if flow_id not in _callback_queues:
        _callback_queues[flow_id] = asyncio.Queue()
    return _callback_queues[flow_id]


def _cleanup_queue(flow_id: str) -> None:
    _callback_queues.pop(flow_id, None)


# ── Parser ────────────────────────────────────────────────────────────────────

def parse_command(text: str) -> tuple[Optional[Command], dict, Optional[str]]:
    """
    Returns (command, body_dict, error_string).
    error_string is set when parsing fails.
    """
    text = text.strip()
    if not text.startswith("/"):
        return None, {}, None

    # split on whitespace respecting quoted strings
    parts = re.findall(r'"[^"]*"|\S+', text)
    cmd_name = parts[0].lower()

    if cmd_name == "/help" or cmd_name == "/sdlc":
        return None, {}, "__help__"

    cmd = COMMANDS.get(cmd_name)
    if cmd is None:
        return None, {}, f"Unknown command `{cmd_name}`. Type `/help` to see available commands."

    # build body from positional args
    positional = [p.strip('"') for p in parts[1:]]
    body: dict = {}

    for i, param in enumerate(cmd.params):
        if i < len(positional):
            body[param] = positional[i]
        else:
            return cmd, {}, (
                f"Missing required parameter `{param}` for `{cmd_name}`.\n"
                f"Usage: `{cmd.example}`"
            )

    # remaining positional → reason (for /escalate multi-word)
    if cmd_name == "/escalate" and len(positional) > 1:
        body["reason"] = " ".join(positional)

    return cmd, body, None


# ── Pipe class ────────────────────────────────────────────────────────────────

class Pipe:
    """
    OpenWebUI pipe — SDLC command dispatcher.
    """

    class Valves(Valves):
        pass

    def __init__(self):
        self.valves = self.Valves()
        self.name = "SDLC"

    # ── public API called by OpenWebUI ────────────────────────────────────────

    async def pipe(
        self,
        body: dict,
        __user__: Optional[dict] = None,
        __event_emitter__=None,
    ) -> AsyncGenerator[str, None]:

        messages = body.get("messages", [])
        if not messages:
            yield "No message received."
            return

        user_text = messages[-1].get("content", "").strip()

        # ── help ──────────────────────────────────────────────────────────────
        if not user_text.startswith("/") or user_text in ("/help", "/sdlc"):
            yield HELP_TEXT
            return

        # ── parse ─────────────────────────────────────────────────────────────
        cmd, payload_body, error = parse_command(user_text)

        if error == "__help__":
            yield HELP_TEXT
            return

        if error:
            yield f"❌ {error}"
            return

        # ── build request ─────────────────────────────────────────────────────
        flow_id = str(uuid.uuid4())
        queue = _get_or_create_queue(flow_id)

        webhook_url = f"{self.valves.N8N_BASE_URL.rstrip('/')}/webhook/{cmd.path}"
        headers = {"Content-Type": "application/json"}
        if self.valves.N8N_WEBHOOK_SECRET:
            headers["X-SDLC-Secret"] = self.valves.N8N_WEBHOOK_SECRET

        request_payload = {
            "flow_id": flow_id,
            "body": payload_body,
        }

        # ── dispatch ──────────────────────────────────────────────────────────
        yield f"⏳ Dispatching `{cmd.name}`...\n\n"

        try:
            async with aiohttp.ClientSession() as session:
                if cmd.method == "GET":
                    resp = await session.get(webhook_url, headers=headers, params=payload_body)
                else:
                    resp = await session.post(webhook_url, headers=headers, json=request_payload)

                if resp.status >= 400:
                    body_text = await resp.text()
                    yield f"❌ n8n returned HTTP {resp.status}: {body_text}"
                    _cleanup_queue(flow_id)
                    return

        except aiohttp.ClientConnectorError as e:
            yield f"❌ Cannot reach n8n at `{self.valves.N8N_BASE_URL}`: {e}"
            _cleanup_queue(flow_id)
            return

        except Exception as e:
            yield f"❌ Dispatch error: {e}"
            _cleanup_queue(flow_id)
            return

        yield f"✅ `{cmd.name}` accepted by n8n (flow_id: `{flow_id}`)\n\n---\n\n"

        # ── stream callbacks ──────────────────────────────────────────────────
        # /projects is near-instant — short timeout
        timeout = 30 if cmd.name == "/projects" else self.valves.CALLBACK_TIMEOUT_SECONDS
        deadline = asyncio.get_event_loop().time() + timeout
        last_activity = asyncio.get_event_loop().time()

        try:
            while True:
                now = asyncio.get_event_loop().time()
                if now > deadline:
                    yield "\n⏱ Timeout waiting for n8n updates. Flow may still be running."
                    break

                try:
                    msg = await asyncio.wait_for(
                        queue.get(),
                        timeout=self.valves.CALLBACK_POLL_INTERVAL
                    )
                except asyncio.TimeoutError:
                    # no message — check if we've been quiet for a while
                    idle = asyncio.get_event_loop().time() - last_activity
                    if idle > 60 and cmd.name in ("/projects", "/escalate"):
                        # short-lived flows — bail after 60s idle
                        break
                    continue

                last_activity = asyncio.get_event_loop().time()
                yield f"{msg}\n\n"

                # terminal signals sent by n8n notify nodes
                done_signals = [
                    "complete", "complete —", "confirmed", "failed", "blocked",
                    "escalating", "deferred", "sleeping", "publishing"
                ]
                if any(s in msg.lower() for s in done_signals):
                    break

        finally:
            _cleanup_queue(flow_id)


# ── Callback endpoint (registered as a separate OpenWebUI route) ──────────────
#
# n8n's HTTP Request notify nodes POST here:
#   POST /api/v1/pipe/callback
#   Body: { "flow_id": "...", "message": "...", "notes": "..." }
#   Header: X-Callback-Token: <CALLBACK_TOKEN>
#
# OpenWebUI supports custom endpoint registration via the pipe's
# `on_startup` / router hooks. The implementation below uses the
# FastAPI router pattern that OpenWebUI exposes.

from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import JSONResponse

router = APIRouter()

_pipe_valves_ref: Optional[Valves] = None


@router.post("/api/v1/pipe/callback")
async def sdlc_callback(request: Request):
    global _pipe_valves_ref

    # token check
    if _pipe_valves_ref and _pipe_valves_ref.CALLBACK_TOKEN:
        token = request.headers.get("X-Callback-Token", "")
        if token != _pipe_valves_ref.CALLBACK_TOKEN:
            raise HTTPException(status_code=401, detail="Invalid callback token")

    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    flow_id = data.get("flow_id", "")
    message = data.get("message", "")
    notes = data.get("notes", "")

    if not flow_id or not message:
        raise HTTPException(status_code=400, detail="flow_id and message required")

    full_msg = message
    if notes:
        full_msg = f"{message}\n> {notes}"

    queue = _callback_queues.get(flow_id)
    if queue:
        await queue.put(full_msg)
        return JSONResponse({"status": "queued"})
    else:
        # flow already finished or unknown — still 200 so n8n doesn't retry
        return JSONResponse({"status": "no_listener", "flow_id": flow_id})


# register valve ref so callback can check token
def on_startup(app, valves: Valves):
    global _pipe_valves_ref
    _pipe_valves_ref = valves
    app.include_router(router)
