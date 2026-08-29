allow_k8s_contexts('k3d-internal-dev')
k8s_context('k3d-internal-dev')

# ponytail: k3d-managed registry created by scripts/create-cluster.sh
# (--registry-create). Without this, Tilt has nowhere to put built images
# and falls back to pushing opencode-box to Docker Hub, which fails.
default_registry('localhost:5111', host_from_cluster='k3d-registry:5111')

include("./helm/Tiltfile")
