"""
mcp_tools_filter — gives every chat model access to LiteLLM's MCP servers by
default (gitlab, sonarqube, grafana, playwright, n8n — see
helm/litellm/templates/config.yaml's mcp_servers: block).

OpenWebUI never attaches an MCP `tools` array to a chat completion request on
its own. This Filter's inlet hook adds one before the request reaches
LiteLLM, so any model — Ollama included — gets LiteLLM's MCP bridge
(`server_url: "litellm_proxy"`) without per-model setup. LiteLLM executes the
actual tool call server-side and folds the result into the reply.

Install: OpenWebUI -> Admin -> Functions -> import this file, then mark it
Global (installed automatically by playbooks/openwebui.yml).

ponytail: whether the underlying model actually calls a tool it's given is a
separate, model-capability problem (small local models often don't) — this
filter only makes the tools available, it doesn't make the model use them.
"""
from typing import Optional

from pydantic import BaseModel


class Filter:
    class Valves(BaseModel):
        enabled: bool = True
        require_approval: str = "never"

    def __init__(self):
        self.valves = self.Valves()

    def inlet(self, body: dict, __user__: Optional[dict] = None) -> dict:
        if not self.valves.enabled:
            return body
        if body.get("tools"):
            # ponytail: don't clobber a caller-supplied tools array
            return body
        body["tools"] = [
            {
                "type": "mcp",
                "server_label": "litellm",
                "server_url": "litellm_proxy",
                "require_approval": self.valves.require_approval,
            }
        ]
        return body
