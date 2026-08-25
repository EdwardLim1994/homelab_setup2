resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  chart            = "${path.module}/../helm/cert-manager"
  namespace        = kubernetes_namespace.cert_manager.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../helm/cert-manager/values.yaml")]

  depends_on = [kubernetes_namespace.cert_manager]
}

# ponytail: two-tier self-signed CA (not per-cert SelfSigned issuer) so the
# root CA can be imported into a browser/OS trust store once, instead of
# clicking through a warning on every homelab app. Real ACME/Let's Encrypt
# needs public DNS + port 80 reachability this cluster doesn't have.
resource "kubectl_manifest" "selfsigned_bootstrap" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: selfsigned-bootstrap
    spec:
      selfSigned: {}
  YAML

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "homelab_ca" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: homelab-ca
      namespace: cert-manager
    spec:
      isCA: true
      commonName: homelab-ca
      secretName: homelab-ca-secret
      privateKey:
        algorithm: ECDSA
        size: 256
      issuerRef:
        name: selfsigned-bootstrap
        kind: ClusterIssuer
        group: cert-manager.io
  YAML

  depends_on = [kubectl_manifest.selfsigned_bootstrap]
}

resource "kubectl_manifest" "homelab_ca_issuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: homelab-ca-issuer
    spec:
      ca:
        secretName: homelab-ca-secret
  YAML

  depends_on = [kubectl_manifest.homelab_ca]
}
