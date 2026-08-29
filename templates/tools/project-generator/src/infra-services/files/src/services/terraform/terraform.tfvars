kube_context = "k3d-sit"
namespace    = "infra"
environment  = "sit"
tailscale          = true
tailscale_hostname = "desktop-qv5aogf.tail60240b.ts.net"

# Fill these in yourself — never committed (*.tfvars* is gitignored).
authentik_secret_key         = "6ctp47ak8U4HgDBapkEdip2DlERIxF4jZP0yqEdlr48UTYbI0Ts58xI7fGqMxNCm1dQ="
authentik_postgres_password  = "yhJLnszvNS27Pgt4SYNqAc6w21RvPHKZ"
authentik_bootstrap_password = "PhlODqSjy6FvZm8ttQWXRu9viwGJsu/m"
