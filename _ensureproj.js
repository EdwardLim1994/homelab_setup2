// ponytail: mirrors the old Taiga project-creation step, adapted to
// Kaneo's workspace -> project -> task hierarchy (no epic/userstory/issue
// resources -- see AGENT.md's "Kaneo" section). One shared 'sdlc' workspace
// holds every generated project, same role the single Taiga instance played.
const auth = { Authorization: `Bearer ${$env.KANEO_TOKEN}` };
const projectName = $node['Webhook Trigger'].json.body.body.project ?? 'hr-portal';
const slug = projectName.toString().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

// ponytail: verify this exact path against the deployed Kaneo version --
// GET /api/workspace (list) is inferred from the confirmed GET /api/project
// naming convention, not confirmed from docs.
const workspaces = await this.helpers.httpRequest({ method: 'GET', url: `${$env.KANEO_URL}/api/workspace`, headers: auth, json: true, ignoreHttpStatusErrors: true });
let workspace = (Array.isArray(workspaces) ? workspaces : workspaces?.workspaces || []).find(w => w.slug === 'sdlc' || w.name === 'sdlc');
if (!workspace) {
  // ponytail: verify this exact path/body against the deployed Kaneo version.
  workspace = await this.helpers.httpRequest({ method: 'POST', url: `${$env.KANEO_URL}/api/workspace`, headers: auth, json: true, body: { name: 'sdlc', slug: 'sdlc' } });
}
const workspaceId = workspace.id;

// GET /api/project -- confirmed endpoint, lists projects in a workspace.
const projects = await this.helpers.httpRequest({ method: 'GET', url: `${$env.KANEO_URL}/api/project`, headers: auth, json: true, qs: { workspaceId }, ignoreHttpStatusErrors: true });
const existing = (Array.isArray(projects) ? projects : projects?.projects || []).find(p => p.slug === slug || p.name === projectName);
if (existing) {
  return [{ json: { kaneo_workspace_id: workspaceId, kaneo_project_id: existing.id, kaneo_project_slug: existing.slug, kaneo_project_created: false } }];
}

// ponytail: verify this exact path/body against the deployed Kaneo version
// -- POST /api/project is inferred from the confirmed GET /api/project
// naming convention, not confirmed from docs.
const created = await this.helpers.httpRequest({ method: 'POST', url: `${$env.KANEO_URL}/api/project`, headers: auth, json: true, body: { name: projectName, slug, workspaceId, description: `${projectName} \u2014 created by /kickoff` } });
return [{ json: { kaneo_workspace_id: workspaceId, kaneo_project_id: created.id, kaneo_project_slug: created.slug, kaneo_project_created: true } }];