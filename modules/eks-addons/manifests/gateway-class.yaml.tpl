apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: aws-nlb
spec:
  controllerName: gateway.networking.k8s.io/aws-gateway-controller