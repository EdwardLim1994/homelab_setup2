"""
SDLC Pipe — OpenWebUI edition
Dispatches SDLC slash commands to n8n webhooks and streams progress back.

Install: OpenWebUI -> Admin -> Functions -> import this file
Env vars to set in the pipe's Valve UI:
  N8N_BASE_URL        e.g. https://n8n.your-domain.com
  N8N_WEBHOOK_SECRET  shared secret for pipe->n8n auth (optional but recommended)

Flow:
  1. User types a slash command in chat  ->  pipe parses it
  2. Pipe POSTs to n8n's command webhook with {flow_id, body: {...}}
  3. n8n runs asynchronously; each "Notify: ..." node POSTs progress to n8n's
     own F-29 Flow Progress Sink (self-call), which inserts into the
     sdlc_flow_progress Postgres table
  4. Pipe polls n8n's F-30 Flow Progress Poll webhook for new rows and
     streams them into the chat as they arrive

ponytail: this used to expect n8n to push progress into a
/api/v1/pipe/callback route this module registered via an on_startup(app,
valves) hook. That never worked — OpenWebUI's function loader
(backend/open_webui/utils/plugin.py) only ever instantiates the Pipe/Filter/
Action/Event class and calls its own methods; it has no mechanism for a
Function to register arbitrary FastAPI routes. Polling F-30 instead needs
nothing from OpenWebUI beyond what every other Pipe already gets.
"""

from __future__ import annotations

import asyncio
import re
import uuid
from dataclasses import dataclass
from typing import AsyncGenerator, Optional

import aiohttp
from pydantic import BaseModel


# ── Valves (admin-configurable env vars) ─────────────────────────────────────

class Valves(BaseModel):
    N8N_BASE_URL: str = "http://n8n.n8n.svc.cluster.local:5678"
    N8N_WEBHOOK_SECRET: str = ""          # added as X-SDLC-Secret header on every call
    POLL_TIMEOUT_SECONDS: int = 300       # how long to wait for n8n to finish
    POLL_INTERVAL_SECONDS: float = 1.0    # seconds between polling F-30


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
        description="Multi-agent release planning: Arch+DE -> QA+Sec+UX -> PM PRD",
        example="/plan_release v1.2.0",
    ),
    "/kickoff": Command(
        name="/kickoff",
        path="kickoff",
        method="POST",
        params=["version"],
        optional=[],
        description="Kickoff sprint: TL branches+pseudocode - PM GitLab artifacts - DevOps infra",
        example="/kickoff v1.2.0",
    ),
    "/develop": Command(
        name="/develop",
        path="develop",
        method="POST",
        params=["version"],
        optional=[],
        description="Gate A->B->C then fan out dev pods (backend, frontend, QA, security)",
        example="/develop v1.2.0",
    ),
    "/uat": Command(
        name="/uat",
        path="uat",
        method="POST",
        params=[],
        optional=[],
        description="UAT pipeline: safeguard -> deploy -> QA -> Security -> PO sign-off",
        example="/uat",
    ),
    "/release_staging": Command(
        name="/release_staging",
        path="release-staging",
        method="POST",
        params=[],
        optional=[],
        description="Stage release: UAT safeguard -> release-plan ticket -> promote/ branch -> CI",
        example="/release_staging",
    ),
    "/release_production": Command(
        name="/release_production",
        path="release-production",
        method="POST",
        params=[],
        optional=[],
        description="Production release: rm:go safeguard -> create promote->main MR for Edward",
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
        description="Dependency check -> revert MR -> TL review -> Edward merges -> re-UAT",
        example="/rollback_story GL-42",
    ),
    "/retro": Command(
        name="/retro",
        path="retro",
        method="POST",
        params=["version"],
        optional=[],
        description="4-pod parallel retro (TL+QA+Sec+RM) -> PM 11-section report",
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

    # remaining positional -> reason (for /escalate multi-word)
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

        # ── dispatch ──────────────────────────────────────────────────────────
        flow_id = str(uuid.uuid4())
        webhook_url = f"{self.valves.N8N_BASE_URL.rstrip('/')}/webhook/{cmd.path}"
        headers = {"Content-Type": "application/json"}
        if self.valves.N8N_WEBHOOK_SECRET:
            headers["X-SDLC-Secret"] = self.valves.N8N_WEBHOOK_SECRET

        request_payload = {
            "flow_id": flow_id,
            "body": payload_body,
        }

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
                    return

        except aiohttp.ClientConnectorError as e:
            yield f"❌ Cannot reach n8n at `{self.valves.N8N_BASE_URL}`: {e}"
            return

        except Exception as e:
            yield f"❌ Dispatch error: {e}"
            return

        yield f"✅ `{cmd.name}` accepted by n8n (flow_id: `{flow_id}`)\n\n---\n\n"

        # ── poll for progress ────────────────────────────────────────────────
        # /projects is near-instant — short timeout
        timeout = 30 if cmd.name == "/projects" else self.valves.POLL_TIMEOUT_SECONDS
        poll_url = f"{self.valves.N8N_BASE_URL.rstrip('/')}/webhook/flow-progress-poll"
        deadline = asyncio.get_event_loop().time() + timeout
        since = "1970-01-01T00:00:00Z"
        idle_since = asyncio.get_event_loop().time()

        done_signals = [
            "complete", "complete —", "confirmed", "failed", "blocked",
            "escalating", "deferred", "sleeping", "publishing"
        ]

        try:
            async with aiohttp.ClientSession() as session:
                while True:
                    now = asyncio.get_event_loop().time()
                    if now > deadline:
                        yield "\n⏱ Timeout waiting for n8n updates. Flow may still be running."
                        break

                    try:
                        resp = await session.get(
                            poll_url,
                            params={"flow_id": flow_id, "since": since},
                            timeout=aiohttp.ClientTimeout(total=10),
                        )
                        rows = await resp.json(content_type=None) if resp.status == 200 else []
                    except Exception:
                        rows = []

                    if not isinstance(rows, list):
                        rows = [rows] if rows else []

                    if not rows:
                        idle = asyncio.get_event_loop().time() - idle_since
                        if idle > 60 and cmd.name in ("/projects", "/escalate"):
                            break
                        await asyncio.sleep(self.valves.POLL_INTERVAL_SECONDS)
                        continue

                    idle_since = asyncio.get_event_loop().time()
                    stop = False
                    for row in rows:
                        msg = row.get("message", "")
                        notes = row.get("notes") or ""
                        since = row.get("created_at", since)
                        full_msg = f"{msg}\n> {notes}" if notes else msg
                        yield f"{full_msg}\n\n"
                        if any(s in msg.lower() for s in done_signals):
                            stop = True
                    if stop:
                        break

        except Exception as e:
            yield f"\n❌ Error polling flow progress: {e}"
