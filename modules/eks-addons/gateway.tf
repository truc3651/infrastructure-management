resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nlb-eip"
  }
}

resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "aws-nlb"
    }
    spec = {
      # This controller's responsible to create AWS NLB or ALB
      controllerName = "gateway.networking.k8s.io/aws-gateway-controller"
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubectl_manifest" "main_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = var.gateway_namespace
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = aws_eip.nlb.id
        "service.beta.kubernetes.io/aws-load-balancer-subnets"         = var.public_subnet_ids[0]
      }
    }
    spec = {
      gatewayClassName = kubectl_manifest.gateway_class.name
      listeners = [
        {
          name     = "http"
          protocol = "TCP"
          port     = 80
        },
        {
          name     = "https"
          protocol = "TCP"
          port     = 443
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.gateway_class,
    kubernetes_namespace.gateway
  ]
}
