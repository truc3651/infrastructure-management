resource "kubectl_manifest" "argocd_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "argocd-route"
      namespace = kubernetes_namespace.gateway.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name = "main-gateway"
          # Cross namespace with ReferenceGrant
          namespace = "ingress-nginx"
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
              name = "argocd-server"
              port = 80
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

  depends_on = [helm_release.argocd]
}
