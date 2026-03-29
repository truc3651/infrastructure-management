resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nlb-eip"
  }
}

# Install Gateway API CRDs - required before creating GatewayClass/Gateway resources
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body = each.value

  depends_on = [helm_release.aws_load_balancer_controller]
}

# It's saying "anyone creates a Gateway using this class, the AWS Load Balancer Controller is responsible for implementing it."
resource "kubectl_manifest" "gateway_class" {
  yaml_body = templatefile("${path.module}/manifests/gateway-class.yaml.tpl", {})

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubectl_manifest.gateway_api_crds
  ]
}

resource "kubectl_manifest" "main_gateway" {
  yaml_body = templatefile("${path.module}/manifests/gateway.yaml.tpl", {
    gateway_namespace = var.gateway_namespace
    nlb_eip_id        = aws_eip.nlb.id
    public_subnet_id  = var.public_subnet_ids[0]
  })

  depends_on = [
    kubectl_manifest.gateway_class,
    kubernetes_namespace.gateway
  ]
}
