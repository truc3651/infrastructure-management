resource "kubectl_manifest" "argocd_route" {
  yaml_body = templatefile("${path.module}/manifests/argocd-route.yaml.tpl", {
    argocd_namespace  = kubernetes_namespace.argocd.metadata[0].name
    gateway_namespace = var.gateway_namespace
  })

  depends_on = [
    kubectl_manifest.main_gateway,
    helm_release.argocd,
    data.kubernetes_service.argocd_server
  ]
}