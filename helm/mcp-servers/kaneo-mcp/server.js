// ponytail: Kaneo's own native MCP endpoint (/api/mcp) expects an
// OAuth-resolvable bearer with dynamic client registration/device-auth —
// built for interactive clients, awkward for a static per-role bearer in a
// batch Job. Mirrors taiga-mcp's shape exactly instead: Kaneo's REST API is
// already documented plainly (AGENTS.md's "Ticket & MR Conventions"), so
// this wraps it as 4 generic REST tools (get/post/patch/delete) instead of
// one bespoke tool per resource type. Stateless streamable-http, same shape
// as the other servers in this chart (grafana/sonarqube/gitlab/n8n/playwright).
//
// ponytail: NO static server-side credential and no separate caller-auth
// token (unlike taiga-mcp's AUTH_TOKEN) — this server is a transparent
// proxy. Whatever bearer the caller sends on /mcp IS forwarded verbatim as
// the Authorization header to Kaneo's own API, so each role's real Kaneo
// API key (minted per-role by role-accounts.yml) flows straight through as
// genuine per-role identity on every task/comment/etc it makes. Kaneo
// itself rejects a bad/missing key — no need to duplicate that check here.
import express from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';

const KANEO_URL = process.env.KANEO_URL;
const PORT = Number(process.env.PORT || 8300);

if (!KANEO_URL) {
  console.error('KANEO_URL is required');
  process.exit(1);
}

async function kaneoRequest(callerToken, method, path, { query, body } = {}) {
  const url = new URL(`/api/${path.replace(/^\/+/, '')}`, KANEO_URL);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${callerToken}`,
      'Content-Type': 'application/json',
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  if (!res.ok) {
    throw new Error(`Kaneo API ${method} ${path} -> HTTP ${res.status}: ${text}`);
  }
  return parsed;
}

function buildServer(callerToken) {
  const server = new McpServer({ name: 'kaneo-mcp', version: '1.0.0' });

  const pathArg = z.string().describe(
    "Path relative to Kaneo's /api/ (e.g. 'task/tasks/<projectId>', 'task/<taskId>', 'project', 'workspace/<id>/members'). See AGENTS.md's Ticket & MR Conventions for the full endpoint table."
  );

  server.registerTool(
    'kaneo_get',
    {
      description: 'GET a Kaneo API resource. Use for listing/reading workspaces, projects, tasks, labels, comments, workspace members, etc.',
      inputSchema: { path: pathArg, query: z.record(z.string()).optional().describe('Query string params') },
    },
    async ({ path, query }) => {
      const data = await kaneoRequest(callerToken, 'GET', path, { query });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'kaneo_post',
    {
      description: 'POST (create) a Kaneo API resource — new task/project/comment/label, etc.',
      inputSchema: { path: pathArg, body: z.record(z.any()).describe('JSON request body') },
    },
    async ({ path, body }) => {
      const data = await kaneoRequest(callerToken, 'POST', path, { body });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'kaneo_patch',
    {
      description: 'PATCH (update) a Kaneo API resource — e.g. status/column change, assignee change, comment edit.',
      inputSchema: { path: pathArg, body: z.record(z.any()).describe('JSON request body') },
    },
    async ({ path, body }) => {
      const data = await kaneoRequest(callerToken, 'PATCH', path, { body });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'kaneo_delete',
    {
      description: 'DELETE a Kaneo API resource.',
      inputSchema: { path: pathArg },
    },
    async ({ path }) => {
      await kaneoRequest(callerToken, 'DELETE', path);
      return { content: [{ type: 'text', text: 'deleted' }] };
    }
  );

  return server;
}

const app = express();
app.use(express.json());

app.post('/mcp', async (req, res) => {
  const callerToken = (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!callerToken) return res.status(401).json({ error: 'missing bearer token' });
  // ponytail: stateless mode — one Server+Transport per request, no session
  // store to manage. Fine at this call volume (a handful of SDLC pods).
  const server = buildServer(callerToken);
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  res.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`kaneo-mcp listening on :${PORT}`);
});
