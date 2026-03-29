resource "kubectl_manifest" "argocd_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "argocd-route"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name      = kubectl_manifest.main_gateway.name
          namespace = var.gateway_namespace
        }
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/argocd"
              }
            }
          ]
          backendRefs = [
            {
              name      = "argocd-server"
              namespace = kubernetes_namespace.argocd.metadata[0].name
              port      = 80
            }
          ]
          filters = [
            {
              type = "URLRewrite"
              urlRewrite = {
                path = {
                  type               = "ReplacePrefixMatch"
                  replacePrefixMatch = "/"
                }
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.main_gateway,
    helm_release.argocd,
    data.kubernetes_service.argocd_server
  ]
}