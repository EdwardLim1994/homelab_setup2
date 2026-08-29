terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig
    config_context = var.kube_context
  }

  # Off by default: without this, the provider only diffs its own resource arguments (chart
  # path string, `values` content, `version`) against state — it never re-renders the local
  # chart to check whether the *templates themselves* changed. Every services/*/helm chart here
  # is a local path edited directly (not a versioned upstream chart), so that's the normal
  # workflow, not an edge case — without this flag, `terraform apply` silently no-ops on a
  # template-only edit (e.g. a Deployment's env/annotations) even though the values are
  # unchanged, and the running cluster keeps the stale manifest.
  #
  # TEMPORARILY DISABLED: this flag's own predictive re-render (used to diff templates against
  # unchanged values) hits a known hashicorp/terraform-provider-helm bug — "Provider produced
  # inconsistent final plan" — on authentik/unleash's bundled postgresql subcharts, reproducing
  # on every retry. Only matters for detecting template-only edits on an existing release; a
  # from-scratch `create` has no prior manifest to diff against, so it's dead weight here too.
  # Re-enable once every environment's first apply has completed.
  # experiments {
  #   manifest = true
  # }
}

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}
