resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      managed-by = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        # Set the domain where ArgoCD will be accessible
        # In production, you'd use a real domain with TLS
        domain = "argocd.${var.cluster_name}.local"
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }

      configs = {
        cm = {
          # It tells: which Kubernetes resources belong to which applications
          "application.resourceTrackingMethod" = "annotation"

          # Configure Git polling interval (default is 3 minutes)
          "timeout.reconciliation" = "180s"
        }

        repositories = {
          backend-deployments = {
            url  = "https://github.com/truc3651/backend-deployments.git"
            type = "git"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd
  ]

  timeout = 600 # 10 minutes
}

resource "kubernetes_namespace" "application" {
  metadata {
    name = var.environment

    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

data "kubernetes_secret" "argocd_initial_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}
