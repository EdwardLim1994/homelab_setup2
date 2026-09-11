# Open WebUI functions

Open WebUI stores functions in its own DB (the PVC), not in config — there's
no declarative install. Each file here is pasted in once via the UI and
survives restarts (`RESET_CONFIG_ON_START` only resets *config*, not the DB).

## `n8n_pipe.py` — "n8n Trigger" model

Routes a chat message to n8n's F-30 webhook. A message starting with a slash
command (`/plan-release 1.4.0`) fans out to that flow; anything else returns a
help string.

Install:

1. Open WebUI → Workspace → Functions → **+**
2. Paste `n8n_pipe.py`, save.
3. Enable it. It shows up as the **n8n Trigger** model in the model picker.
4. Function → valves → set `n8n_url` if the default is wrong
   (`http://n8n.n8n.svc.cluster.local:5678/webhook/openwebui-trigger`).

The n8n side (`helm/n8n/flows/F-30-openwebui-trigger.json`) is seeded
automatically by `helm/n8n/flows/seed.sh` on n8n deploy.
