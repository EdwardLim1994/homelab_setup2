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

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-internal"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-internal"
}

provider "kubectl" {
  config_path      = "~/.kube/config"
  config_context   = "k3d-internal"
  load_config_file = true
}
