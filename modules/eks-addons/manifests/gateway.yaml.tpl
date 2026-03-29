apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: ${gateway_namespace}
  annotations:
    # "external" = create the NLB with public-facing network interfaces
    # "internal" = create the NLB with internal-only network interfaces
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    # How the NLB routes traffic to pods:
    #   "ip"       → NLB sends traffic directly to pod IPs (fewer hops, lower latency)
    #   "instance" → NLB sends to EC2 node, kube-proxy forwards to pod
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    # Pin a static Elastic IP so the NLB address never changes
    service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "${nlb_eip_id}"
    service.beta.kubernetes.io/aws-load-balancer-subnets: "${public_subnet_id}"
spec:
  gatewayClassName: aws-nlb
  listeners:
    - name: http
      protocol: TCP
      port: 80
    - name: https
      protocol: TCP
      port: 443