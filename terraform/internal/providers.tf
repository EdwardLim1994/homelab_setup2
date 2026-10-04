terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    # ponytail: native kubernetes_manifest needs the CRD schema at plan time,
    # which doesn't exist until cert-manager's helm_release has applied —
    # kubectl_manifest avoids that chicken-and-egg problem
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ponytail: override with TF_VAR_kube_context if your cluster isn't named
# "internal" (create-cluster.sh default -> context "k3d-internal").
variable "kube_context" {
  type    = string
  default = "k3d-internal"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "kubectl" {
  config_path      = "~/.kube/config"
  config_context   = var.kube_context
  load_config_file = true
}
