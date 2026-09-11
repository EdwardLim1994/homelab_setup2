"""
title: n8n Trigger
author: homelab
version: 0.1.0
description: >
  Routes an Open WebUI chat message to an n8n webhook. A message that starts
  with a slash command (e.g. "/plan-release 1.4.0") tells the n8n flow which
  sub-flow to fan out to; anything else is passed through as a plain prompt.
  Install: Workspace -> Functions -> + -> paste this file -> save, then set the
  `n8n_url` valve. Appears as the "n8n Trigger" model in the model picker.
requirements: requests
"""

import requests
from pydantic import BaseModel, Field


class Pipe:
    class Valves(BaseModel):
        n8n_url: str = Field(
            default="http://n8n.n8n.svc.cluster.local:5678/webhook/openwebui-trigger",
            description="n8n webhook URL for F-30 (in-cluster Service DNS).",
        )
        bearer_token: str = Field(
            default="",
            description="Optional bearer token, sent as Authorization header.",
        )
        timeout: int = Field(default=300, description="Request timeout (seconds).")

    def __init__(self):
        self.valves = self.Valves()

    def pipes(self):
        return [{"id": "n8n-trigger", "name": "n8n Trigger"}]

    def pipe(self, body: dict, __user__: dict = None):
        messages = body.get("messages", [])
        prompt = messages[-1]["content"] if messages else ""
        if not prompt:
            return "Empty message."

        headers = {"Content-Type": "application/json"}
        if self.valves.bearer_token:
            headers["Authorization"] = f"Bearer {self.valves.bearer_token}"

        user = __user__ or {}
        payload = {
            "prompt": prompt,
            "messages": messages,
            "user": user.get("email") or user.get("id") or "",
            "model": body.get("model", ""),
        }

        try:
            r = requests.post(
                self.valves.n8n_url, json=payload, headers=headers,
                timeout=self.valves.timeout,
            )
            r.raise_for_status()
        except requests.RequestException as e:
            return f"n8n request failed: {e}"

        try:
            data = r.json()
        except ValueError:
            return r.text or "(empty response)"

        if isinstance(data, dict):
            return data.get("response") or data.get("output") or data.get("text") or str(data)
        if isinstance(data, list) and data:
            first = data[0]
            if isinstance(first, dict):
                return first.get("response") or str(first)
        return str(data)
