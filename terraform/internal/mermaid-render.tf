# Scale-to-zero mermaid-cli microservice for /plan_release diagram
# rendering — woken/scaled-down by helm/omp/scripts/render-mermaid.sh, not
# a standing service. No secrets, no new namespace (reuses `sdlc`, already
# created by kubernetes_namespace.sdlc in omp-agent.tf).
resource "helm_release" "mermaid_render" {
  name              = "mermaid-render"
  chart             = "${path.module}/../../helm/mermaid-render"
  namespace         = "sdlc"
  dependency_update = true

  # ponytail: the helm provider doesn't hash local chart files, so an edit
  # to server.js alone wouldn't trigger a helm upgrade — same gotcha
  # ansible.tf's chartHash works around.
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/mermaid-render", "**") :
      filesha1("${path.module}/../../helm/mermaid-render/${f}")
    ]))
  }

  depends_on = [kubernetes_namespace.sdlc]
}
