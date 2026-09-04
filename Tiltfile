allow_k8s_contexts('k3d-internal-dev')
k8s_context('k3d-internal-dev')

# ponytail: load .env so every app Tiltfile's os.getenv() works even on bare
# `tilt up` (Windows/Tilt-Desktop can't `source .env` like dev-up.sh does).
# Naive parser: KEY=VALUE lines, strips ' #' inline comments and surrounding
# quotes. Real env vars still win (os.getenv reads them first).
for _line in str(read_file('.env', default='')).splitlines():
    _line = _line.strip()
    if _line and not _line.startswith('#') and '=' in _line:
        _k, _v = _line.split('=', 1)
        _v = _v.split(' #')[0].strip().strip('"').strip("'")
        if os.getenv(_k.strip()) == None:
            os.putenv(_k.strip(), _v)

# ponytail: k3d-managed registry created by scripts/create-cluster.sh
# (--registry-create). Without this, Tilt has nowhere to put built images
# and falls back to pushing omp-box to Docker Hub, which fails.
default_registry('localhost:5111', host_from_cluster='k3d-registry:5111')

include("./helm/Tiltfile")
