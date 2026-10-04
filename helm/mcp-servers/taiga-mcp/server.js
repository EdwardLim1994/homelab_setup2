// ponytail: no maintained Taiga MCP server exists to reuse (checked before
// building this) — every SKILL.md/n8n-flow in this repo already talks to
// Taiga via plain curl against its REST API (AGENTS.md's "Ticket & MR
// Conventions"), so this wraps that same API as 4 generic REST tools
// (get/post/patch/delete) instead of one bespoke tool per Taiga resource
// type (epics/userstories/tasks/issues/wiki/...) — the resource surface is
// already documented in AGENTS.md and changes there would otherwise need
// mirroring here forever. Stateless streamable-http, same shape as the
// other servers in this chart (grafana/sonarqube/gitlab/n8n/playwright).
import express from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';

const TAIGA_URL = process.env.TAIGA_URL;
const TAIGA_TOKEN = process.env.TAIGA_TOKEN;
const AUTH_TOKEN = process.env.AUTH_TOKEN; // per-caller bearer, same pattern as gitlab-mcp's STREAMABLE_HTTP_AUTH_TOKEN
const PORT = Number(process.env.PORT || 8300);

if (!TAIGA_URL || !TAIGA_TOKEN) {
  console.error('TAIGA_URL and TAIGA_TOKEN are required');
  process.exit(1);
}

async function taigaRequest(method, path, { query, body } = {}) {
  const url = new URL(`/api/v1/${path.replace(/^\/+/, '')}`, TAIGA_URL);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${TAIGA_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  if (!res.ok) {
    throw new Error(`Taiga API ${method} ${path} -> HTTP ${res.status}: ${text}`);
  }
  return parsed;
}

function buildServer() {
  const server = new McpServer({ name: 'taiga-mcp', version: '1.0.0' });

  const pathArg = z.string().describe(
    "Path relative to Taiga's /api/v1/ (e.g. 'userstories', 'userstories/42', 'epics', 'issues', 'wiki', 'userstory-statuses'). See AGENTS.md's Ticket & MR Conventions for the full endpoint table."
  );

  server.registerTool(
    'taiga_get',
    {
      description: 'GET a Taiga API resource. Use for listing/reading epics, userstories, tasks, issues, wiki pages, statuses, priorities, severities, project modules, etc.',
      inputSchema: { path: pathArg, query: z.record(z.string()).optional().describe('Query string params, e.g. {"project": "1", "tags": "v1.2.0"}') },
    },
    async ({ path, query }) => {
      const data = await taigaRequest('GET', path, { query });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'taiga_post',
    {
      description: 'POST (create) a Taiga API resource — new epic/userstory/task/issue/wiki page/comment, etc.',
      inputSchema: { path: pathArg, body: z.record(z.any()).describe('JSON request body') },
    },
    async ({ path, body }) => {
      const data = await taigaRequest('POST', path, { body });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'taiga_patch',
    {
      description: 'PATCH (update) a Taiga API resource — e.g. status change, comment, wiki edit. Taiga uses optimistic locking: include the resource\'s current "version" field (GET it first) or the request 400s.',
      inputSchema: { path: pathArg, body: z.record(z.any()).describe('JSON request body, must include "version"') },
    },
    async ({ path, body }) => {
      const data = await taigaRequest('PATCH', path, { body });
      return { content: [{ type: 'text', text: JSON.stringify(data) }] };
    }
  );

  server.registerTool(
    'taiga_delete',
    {
      description: 'DELETE a Taiga API resource.',
      inputSchema: { path: pathArg },
    },
    async ({ path }) => {
      await taigaRequest('DELETE', path);
      return { content: [{ type: 'text', text: 'deleted' }] };
    }
  );

  return server;
}

const app = express();
app.use(express.json());

app.post('/mcp', async (req, res) => {
  if (AUTH_TOKEN) {
    const got = (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (got !== AUTH_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  }
  // ponytail: stateless mode — one Server+Transport per request, no session
  // store to manage. Matches the SDK's own documented stateless example;
  // fine at this call volume (a handful of SDLC pods, not a public API).
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  res.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`taiga-mcp listening on :${PORT}`);
});
